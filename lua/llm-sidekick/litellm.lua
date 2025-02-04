local Job = require("plenary.job")
local M = {}

local function get_log_dir()
  local state_home = vim.env.XDG_STATE_HOME
  if not state_home or state_home == "" then
    state_home = vim.fn.expand("~/.local/state")
  end
  return state_home .. "/nvim/llm-sidekick"
end

local function ensure_log_dir()
  local log_dir = get_log_dir()
  if vim.fn.isdirectory(log_dir) == 0 then
    vim.fn.mkdir(log_dir, "p")
  end
  return log_dir
end

local function command_exists(cmd)
  local exists = false
  Job:new({
    command = 'which',
    args = { cmd },
    on_exit = function(_, return_val)
      exists = (return_val == 0)
    end,
  }):sync()
  return exists
end

local ENV_VARS = {
  PATH = "PATH",
  AWS_ACCESS_KEY_ID = "AWS_ACCESS_KEY_ID",
  AWS_SECRET_ACCESS_KEY = "AWS_SECRET_ACCESS_KEY",
  AWS_DEFAULT_REGION = "AWS_REGION_NAME",
  AWS_REGION = "AWS_REGION_NAME",
  AWS_REGION_NAME = "AWS_REGION_NAME",
  ROLE_ARN = "AWS_ROLE_NAME",
  AWS_ROLE_ARN = "AWS_ROLE_NAME",
  AWS_ROLE_NAME = "AWS_ROLE_NAME",
  ROLE_SESSION_NAME = "AWS_SESSION_NAME",
  AWS_ROLE_SESSION_NAME = "AWS_SESSION_NAME",
  AWS_SESSION_NAME = "AWS_SESSION_NAME",
  ANTHROPIC_API_KEY = "ANTHROPIC_API_KEY",
  GROQ_API_KEY = "GROQ_API_KEY",
  OPENAI_API_KEY = "OPENAI_API_KEY",
  DEEPSEEK_API_KEY = "DEEPSEEK_API_KEY",
  GEMINI_API_KEY = "GEMINI_API_KEY",
}

local function is_port_in_use(port)
  vim.fn.system(string.format('lsof -i:%d -P -n | grep LISTEN', port))
  return vim.v.shell_error == 0
end

function M.start_web_server(port)
  if not command_exists('uv') then
    vim.schedule(function()
      vim.api.nvim_err_writeln("Error: 'uv' command is not available")
    end)
    return
  end

  if is_port_in_use(port) then
    return
  end

  local plugin_root = vim.fn.fnamemodify(vim.fn.resolve(debug.getinfo(1, "S").source:sub(2)), ":h:h:h")

  local env = {}
  for env_var, required_name in pairs(ENV_VARS) do
    if vim.env["LLM_SIDEKICK_" .. env_var] then
      env[required_name] = vim.env["LLM_SIDEKICK_" .. env_var]
    elseif vim.env[env_var] then
      env[required_name] = vim.env[env_var]
    end
  end

  Job:new({
    command = 'uv',
    detached = true,
    env = env,
    args = {
      'run', '--python', '3.12', '--with', 'litellm[proxy]', '--with', 'boto3',
      'litellm', '--port', tostring(port), '--config', plugin_root .. '/python/litellm_config.yaml',
    },
    on_error = function(_, error)
      vim.schedule(function()
        vim.api.nvim_err_writeln("Error starting web server: " .. tostring(error))
      end)
    end,
    on_stdout = function(_, data)
      if data then
        vim.schedule(function()
          local log_file = io.open(ensure_log_dir() .. "/litellm.log", "a")
          if log_file then
            log_file:write(os.date("%Y-%m-%d %H:%M:%S") .. " [stdout] " .. data .. "\n")
            log_file:close()
          end
        end)
      end
    end,
    on_stderr = function(_, data)
      if data then
        vim.schedule(function()
          local log_file = io.open(ensure_log_dir() .. "/litellm.log", "a")
          if log_file then
            log_file:write(os.date("%Y-%m-%d %H:%M:%S") .. " [stderr] " .. data .. "\n")
            log_file:close()
          end
        end)
      end
    end,
  }):start()
end

function M.stop_web_server(port)
  local output = vim.fn.system(string.format('lsof -ti:%s | xargs kill -9', port))
  local exit_code = vim.v.shell_error

  -- NOTE: 1 = no process found on port
  if exit_code == 0 or exit_code == 1 then
    return
  end

  if exit_code == 127 then
    vim.notify("Command 'lsof' not found", vim.log.levels.ERROR)
  else
    vim.notify(
      string.format("Command failed with exit code %d: %s", exit_code, output),
      vim.log.levels.ERROR
    )
  end
end

return M
