local Job = require("plenary.job")
local M = {}

local LITELLM_VERSION = "1.63.0"

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

local function has_env_var(name)
  return vim.env["LLM_SIDEKICK_" .. name] ~= nil or vim.env[name] ~= nil
end

local function add_aws_auth_params(params)
  if has_env_var("AWS_ROLE_NAME") or has_env_var("ROLE_ARN") or has_env_var("AWS_ROLE_ARN") then
    params.aws_role_name = "os.environ/AWS_ROLE_NAME"
  end
  if has_env_var("AWS_SESSION_NAME") or has_env_var("ROLE_SESSION_NAME") or has_env_var("AWS_ROLE_SESSION_NAME") then
    params.aws_session_name = "os.environ/AWS_SESSION_NAME"
  end
  return params
end

local function generate_config()
  local config = {
    model_list = {},
    litellm_settings = {
      drop_params = true,
      num_retries = 3,
      request_timeout = 600,
      telemetry = false
    }
  }

  -- Add Bedrock models if AWS credentials are available
  if has_env_var("AWS_ACCESS_KEY_ID") and has_env_var("AWS_SECRET_ACCESS_KEY") or
      (has_env_var("AWS_ROLE_NAME") and has_env_var("AWS_SESSION_NAME")) then
    table.insert(config.model_list, {
      model_name = "bedrock/anthropic.claude-3-5-sonnet-20241022-v2:0",
      litellm_params = add_aws_auth_params({
        model = "bedrock/converse/anthropic.claude-3-5-sonnet-20241022-v2:0",
        aws_region_name = "us-west-2",
      })
    })

    table.insert(config.model_list, {
      model_name = "bedrock/anthropic.claude-3-5-haiku-20241022-v1:0",
      litellm_params = add_aws_auth_params({
        model = "bedrock/converse/anthropic.claude-3-5-haiku-20241022-v1:0",
        aws_region_name = "us-west-2",
      })
    })

    table.insert(config.model_list, {
      model_name = "bedrock/*",
      litellm_params = add_aws_auth_params({
        model = "bedrock/converse/*",
      })
    })
  end

  if has_env_var("DEEPSEEK_API_KEY") then
    table.insert(config.model_list, {
      model_name = "deepseek/*",
      litellm_params = {
        model = "deepseek/*",
        api_key = "os.environ/DEEPSEEK_API_KEY"
      }
    })
  end

  if has_env_var("OPENAI_API_KEY") then
    table.insert(config.model_list, {
      model_name = "openai/*",
      litellm_params = {
        model = "openai/*",
        api_key = "os.environ/OPENAI_API_KEY"
      }
    })
  end

  if has_env_var("ANTHROPIC_API_KEY") then
    table.insert(config.model_list, {
      model_name = "anthropic/*",
      litellm_params = {
        model = "anthropic/*",
        api_key = "os.environ/ANTHROPIC_API_KEY"
      }
    })
  end

  if has_env_var("GROQ_API_KEY") then
    table.insert(config.model_list, {
      model_name = "groq/*",
      litellm_params = {
        model = "groq/*",
        api_key = "os.environ/GROQ_API_KEY"
      }
    })
  end

  if has_env_var("GEMINI_API_KEY") then
    table.insert(config.model_list, {
      model_name = "gemini/*",
      litellm_params = {
        model = "gemini/*",
        api_key = "os.environ/GEMINI_API_KEY"
      }
    })
  end

  -- Convert to YAML
  local yaml = "model_list:\n"
  for _, model in ipairs(config.model_list) do
    yaml = yaml .. "  - model_name: \"" .. model.model_name .. "\"\n"
    yaml = yaml .. "    litellm_params:\n"
    for k, v in pairs(model.litellm_params) do
      yaml = yaml .. "      " .. k .. ": " .. tostring(v) .. "\n"
    end
    yaml = yaml .. "\n"
  end

  yaml = yaml .. "litellm_settings:\n"
  for k, v in pairs(config.litellm_settings) do
    yaml = yaml .. "  " .. k .. ": " .. tostring(v) .. "\n"
  end

  return yaml
end

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

  -- Generate dynamic config
  local config_content = generate_config()
  local config_path = ensure_log_dir() .. "/litellm_config.yaml"
  local config_file = io.open(config_path, "w")
  if not config_file then
    vim.schedule(function()
      vim.api.nvim_err_writeln("Error: Unable to create config file")
    end)
    return
  end
  config_file:write(config_content)
  config_file:close()

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
      'run', '--python', '3.12', '--with', string.format('litellm[proxy]==%s', LITELLM_VERSION), '--with', 'boto3',
      'litellm', '--port', tostring(port), '--config', config_path,
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

function M.is_server_ready(port)
  local output = vim.fn.system(
    string.format('curl -s -o /dev/null -w "%%{http_code}" http://0.0.0.0:%d/health/readiness', port)
  )
  return output == "200"
end

return M
