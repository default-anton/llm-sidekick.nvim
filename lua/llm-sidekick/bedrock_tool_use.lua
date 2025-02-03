local message_types = require("llm-sidekick.message_types")
local Job = require("plenary.job")
local bedrock = {}

function bedrock.new(opts)
  return setmetatable(
    {
      url = opts.url or 'http://localhost:5500/invoke',
      include_modifications = opts.include_modifications,
    },
    { __index = bedrock }
  )
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

function bedrock.start_web_server()
  if not command_exists('uv') then
    vim.schedule(function()
      vim.api.nvim_err_writeln("Error: 'uv' command is not available")
    end)
    return
  end

  local plugin_root = vim.fn.fnamemodify(vim.fn.resolve(debug.getinfo(1, "S").source:sub(2)), ":h:h:h")

  Job:new({
    command = 'uv',
    detached = true,
    args = {
      'run',
      '--python', '3.12',
      '--with', 'gunicorn',
      '--with', 'boto3',
      '--with', 'flask-cors',
      'gunicorn',
      '--bind', '0.0.0.0:5500',
      '--timeout', '300',
      '--keep-alive', '300',
      '--access-logfile', '/tmp/llm-sidekick-access.log',
      '--error-logfile', '/tmp/llm-sidekick-error.log',
      '--pid', '/tmp/llm-sidekick.pid',
      '--pythonpath', plugin_root,
      'python.bedrock:app'
    },
    on_error = function(_, error)
      vim.schedule(function()
        vim.api.nvim_err_writeln("Error starting web server: " .. tostring(error))
      end)
    end,
    on_stderr = function(_, data)
      if data and data ~= "" and not string.find(data, "Already running on PID", 1, true) then
        vim.schedule(function()
          vim.api.nvim_err_writeln("Web server stderr: " .. data)
        end)
      end
    end,
  }):start()
end

function bedrock:chat(opts, callback)
  local messages = opts.messages
  local settings = opts.settings
  callback = vim.schedule_wrap(callback)

  local data = {
    model_id = settings.model,
    body = {
      temperature = settings.temperature,
      max_tokens = settings.max_tokens,
      messages = messages,
    },
  }

  if self.include_modifications then
    data.body.tools = vim.tbl_map(function(tool) return tool.spec end, opts.tools)
  end

  local us_west_2_models = { "anthropic.claude-3-5-sonnet-20241022-v2:0", "anthropic.claude-3-5-haiku-20241022-v1:0" }
  if vim.tbl_contains(us_west_2_models, settings.model) then
    data["region"] = "us-west-2"
  end

  for i, message in ipairs(data.body.messages) do
    if message.role == "system" then
      data.body.system = message.content
      table.remove(data.body.messages, i)
      break
    end
  end

  local body = vim.json.encode(data)
  if data.tools then
    for _, tool in ipairs(opts.tools) do
      local unordered_json = vim.json.encode(tool.spec)
      local ordered_json = tool.spec_json
      if body:find(unordered_json, 1, true) then
        body = body:gsub(unordered_json, ordered_json, 1)
      else
        error("Failed to find tool in request body")
      end
    end
  end

  local curl = require("llm-sidekick.executables").get_curl_executable()
  local args = {
    '-s',
    '--no-buffer',
    '-H', 'Content-Type: application/json',
    '-H', 'anthropic-version: bedrock-2023-05-31',
    '-d', body,
    self.url,
  }

  local tool = nil

  Job:new({
    command = curl,
    args = args,
    on_stdout = function(_, line)
      line = line:gsub("^data: ", "")
      if line == "" then
        return
      end
      local ok, decoded = pcall(vim.json.decode, line)
      if not ok or not decoded then
        vim.schedule(function()
          vim.api.nvim_err_writeln("Error: Failed to decode JSON line: " .. line)
        end)
        return
      end

      if decoded.type == "content_block_start" then
        if decoded.content_block and decoded.content_block.type == "tool_use" then
          tool = {
            id = decoded.content_block.id,
            name = decoded.content_block.name,
            parameters = "",
            state = {},
          }
          callback(message_types.TOOL_START, vim.tbl_extend("force", {}, tool))
        else
          tool = nil
        end
      elseif decoded.type == "content_block_stop" then
        if tool then
          callback(message_types.TOOL_STOP, vim.tbl_extend("force", {}, tool))
          tool = nil
        end
      elseif decoded.type == "content_block_delta" then
        if decoded.delta.type == "text_delta" and decoded.delta.text then
          callback(message_types.DATA, decoded.delta.text)
        elseif decoded.delta.type == "input_json_delta" and decoded.delta.partial_json then
          tool.parameters = tool.parameters .. decoded.delta.partial_json
          callback(message_types.TOOL_DELTA, vim.tbl_extend("force", {}, tool))
        end
      elseif decoded.type == "message_delta" then
        if decoded.delta and decoded.delta.stop_reason then
          if decoded.delta.stop_reason == "max_tokens" then
            callback(message_types.ERROR_MAX_TOKENS, "")
          else
            callback(message_types.DONE, "")
          end
        end
      elseif decoded.error then
        callback(message_types.ERROR, decoded.error.message)
      end
    end,
    on_stderr = function(_, text)
      if not text or text == "" then
        return
      end

      vim.schedule(function()
        vim.api.nvim_err_writeln("Error: " .. tostring(text))
      end)
    end,
    on_exit = function(_, return_val)
      if return_val == 0 then
        return
      end

      vim.schedule(function()
        vim.api.nvim_err_writeln("Error: API request failed with exit code " .. return_val)
      end)
    end,
  }):start()
end

return bedrock
