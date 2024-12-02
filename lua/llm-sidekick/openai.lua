local message_types = require("llm-sidekick.message_types")
local openai = {}

function openai.new(url)
  local api_key = require("llm-sidekick.settings").get_openai_api_key()

  return setmetatable({
      url = url or 'https://api.openai.com/v1/chat/completions',
      api_key = api_key
    },
    { __index = openai }
  )
end

function openai:chat(messages, settings, callback)
  callback = vim.schedule_wrap(callback)
  local data = {
    model = vim.startswith(settings.model, "ollama-") and string.sub(settings.model, 8) or settings.model,
    stream = settings.stream,
    messages = messages,
    max_tokens = settings.max_tokens,
    temperature = settings.temperature,
  }

  if settings.response_format then
    data.response_format = settings.response_format
  end

  if vim.startswith(data.model, "o1") then
    data.messages = vim.tbl_filter(function(message) return message.role == "user" or message.role == "assistant" end,
      messages)
    data.max_tokens = nil
    data.max_completion_tokens = settings.max_tokens
    data.temperature = nil
    -- prepend the system prompt to the first message
    local system_prompt = vim.tbl_filter(function(message) return message.role == "system" end, messages)[1]
    if system_prompt then
      data.messages[1].content = system_prompt.content .. "\n\n" .. data.messages[1].content
    end
  end

  local curl = require("llm-sidekick.curl").get_curl_executable()
  local args = {
    '-s',
    '--no-buffer',
    '-H', 'Content-Type: application/json',
    '-d', vim.json.encode(data),
  }
  if self.api_key then
    table.insert(args, '-H')
    table.insert(args, 'Authorization: Bearer ' .. self.api_key)
  end
  table.insert(args, self.url)

  require('plenary.job'):new({
    command = curl,
    args = args,
    on_stdout = function(_, line)
      if not data.stream then
        return
      end

      -- Remove "data: " prefix if present
      line = line:gsub("^data: ", "")
      if line == "[DONE]" then
        callback(message_types.DONE, "")
        return
      end
      if line == "" then
        return
      end

      local ok, decoded = pcall(vim.json.decode, line)
      if ok and decoded and decoded.choices and decoded.choices[1] and decoded.choices[1].delta and decoded.choices[1].delta.content then
        local content = decoded.choices[1].delta.content
        callback(message_types.DATA, content)
      end
    end,
    on_stderr = function(_, text)
      vim.schedule(function()
        vim.api.nvim_err_writeln("Error: " .. text)
      end)
    end,
    on_exit = function(j, return_val)
      if return_val ~= 0 then
        vim.schedule(function()
          vim.api.nvim_err_writeln("Error: API request failed with exit code " .. return_val)
        end)
        return
      end

      if data.stream then
        return
      end

      local result = table.concat(j:result(), "\n")
      local ok, decoded = pcall(vim.json.decode, result)
      if not ok or not decoded or not decoded.choices or not decoded.choices[1] or not decoded.choices[1].message then
        vim.schedule(function()
          vim.api.nvim_err_writeln("Error: Failed to parse API response: " .. result)
        end)
        return
      end

      local content = decoded.choices[1].message.content
      callback(message_types.DATA, content)
      callback(message_types.DONE, "")
    end,
  }):start()
end

return openai
