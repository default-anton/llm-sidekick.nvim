local message_types = require("llm-sidekick.message_types")
local Job = require("plenary.job")
local anthropic = {}

function anthropic.new(url)
  local api_key = require("llm-sidekick.settings").get_anthropic_api_key()

  return setmetatable({ url = url or 'https://api.anthropic.com/v1/messages', api_key = api_key },
    { __index = anthropic }
  )
end

function anthropic:chat(opts, callback)
  local messages = opts.messages
  local settings = opts.settings
  local tools = opts.tools
  callback = vim.schedule_wrap(callback)

  local data = {
    stream = true,
    model = settings.model,
    temperature = settings.temperature,
    max_tokens = settings.max_tokens,
    messages = messages,
  }

  for i, message in ipairs(data.messages) do
    if message.role == "system" then
      data.system = message.content
      table.remove(data.messages, i)
      break
    end
  end

  local curl = require("llm-sidekick.executables").get_curl_executable()
  local json_data = vim.json.encode(data)
  local args = {
    '-s',
    '--no-buffer',
    '-H', 'content-type: application/json',
    '-H', 'x-api-key: ' .. self.api_key,
    '-H', 'anthropic-version: 2023-06-01',
    '-d', json_data,
    self.url,
  }

  Job:new({
    command = curl,
    args = args,
    on_stdout = function(_, line)
      if not line:match("^data: ") then
        return
      end
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

      if decoded.type == "content_block_delta" then
        if decoded.delta and decoded.delta.text then
          callback(message_types.DATA, decoded.delta.text)
        end
      elseif decoded.type == "message_delta" then
        if decoded.delta and decoded.delta.stop_reason then
          callback(message_types.DONE, "")
        end
      elseif decoded.error then
        callback(message_types.DONE, "")
        vim.schedule(function()
          vim.api.nvim_err_writeln("Error " .. decoded.error.type .. ": " .. decoded.error.message)
        end)
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

return anthropic
