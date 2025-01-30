local message_types = require("llm-sidekick.message_types")
local openai = {}

function openai.new(opts)
  return setmetatable({
      url = opts.url or 'https://api.openai.com/v1/chat/completions',
      api_key = opts.api_key
    },
    { __index = openai }
  )
end

function openai:chat(opts, callback)
  local messages = opts.messages
  local settings = opts.settings
  local tools = opts.tools
  callback = vim.schedule_wrap(callback)
  local data = {
    model = settings.model,
    stream = settings.stream,
    messages = messages,
    max_tokens = settings.max_tokens,
    temperature = settings.temperature,
  }

  if settings.response_format then
    data.response_format = settings.response_format
  end

  if settings.reasoning_effort then
    data.reasoning_effort = settings.reasoning_effort
  end

  if vim.startswith(data.model, "o1") or vim.startswith(data.model, "o3") then
    data.max_tokens = nil
    data.max_completion_tokens = settings.max_tokens
  end

  local curl = require("llm-sidekick.executables").get_curl_executable()
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
      if ok and decoded and decoded.choices and decoded.choices[1] and decoded.choices[1].delta then
        local reasoning_content = decoded.choices[1].delta.reasoning_content
        if reasoning_content and reasoning_content ~= "" and vim.NIL ~= reasoning_content then
          callback(message_types.REASONING, reasoning_content)
        end

        local content = decoded.choices[1].delta.content
        if content and content ~= "" and vim.NIL ~= content then
          callback(message_types.DATA, content)
        end
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
    on_exit = function(j, return_val)
      if j:result() and not vim.tbl_isempty(j:result()) then
        vim.schedule(function()
          local ok, res = pcall(vim.json.decode, table.concat(j:result(), "\n"))
          if ok and res and res.error then
            vim.notify("Error: " .. res.error.message, vim.log.levels.ERROR)
          end
        end)
      end

      if return_val ~= 0 then
        vim.schedule(function()
          if j:result() and not vim.tbl_isempty(j:result()) then
            vim.notify("Error: " .. table.concat(j:result(), "\n"), vim.log.levels.ERROR)
          end

          if j:stderr_result() and not vim.tbl_isempty(j:stderr_result()) then
            vim.notify("Error: " .. table.concat(j:stderr_result(), "\n"), vim.log.levels.ERROR)
          end
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

      local reasoning_content = decoded.choices[1].message.reasoning_content
      if reasoning_content and reasoning_content ~= "" and vim.NIL ~= reasoning_content then
        callback(message_types.REASONING, reasoning_content)
      end

      local content = decoded.choices[1].message.content
      if content and content ~= "" and vim.NIL ~= content then
        callback(message_types.DATA, content)
      end
      callback(message_types.DONE, "")
    end,
  }):start()
end

return openai
