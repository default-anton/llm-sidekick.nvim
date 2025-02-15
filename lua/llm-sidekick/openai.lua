local message_types = require("llm-sidekick.message_types")
local sjson = require("llm-sidekick.sjson")
local openai = {}

function openai.new(opts)
  return setmetatable({
      url = opts.url or 'https://api.openai.com/v1/chat/completions',
      api_key = opts.api_key,
    },
    { __index = openai }
  )
end

function openai:chat(opts, callback)
  local messages = opts.messages
  local settings = opts.settings
  callback = vim.schedule_wrap(callback)

  local openai_converter = require("llm-sidekick.tools.openai")
  local data = {
    model = settings.model,
    stream = settings.stream,
    messages = messages,
    max_tokens = settings.max_tokens,
    max_completion_tokens = settings.max_completion_tokens,
    temperature = settings.temperature,
    tools = vim.tbl_map(function(tool) return openai_converter.convert_spec(tool.spec) end, opts.tools),
    tool_choice = "required",
    parallel_tool_calls = true,
  }
  if settings.model:find("o3") then
    data.parallel_tool_calls = nil
  end

  if settings.response_format then
    data.response_format = settings.response_format
  end

  if settings.reasoning_effort then
    data.reasoning_effort = settings.reasoning_effort
  end

  local body = vim.json.encode(data)
  for _, tool in ipairs(opts.tools) do
    body = body:gsub(vim.json.encode(tool.spec.input_schema.properties), tool.json_props)
  end

  local curl = require("llm-sidekick.executables").get_curl_executable()
  local args = {
    '-s',
    '--no-buffer',
    '-H', 'Content-Type: application/json',
    '-d', body,
  }

  if self.api_key then
    table.insert(args, '-H')
    table.insert(args, 'Authorization: Bearer ' .. self.api_key)
  end
  table.insert(args, self.url)

  if os.getenv("LLM_SIDEKICK_DEBUG") == "true" then
    vim.notify("Request: " .. vim.inspect(data), vim.log.levels.INFO)
  end

  local tool = nil

  local job = require('plenary.job'):new({
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

      local ok, decoded = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })

      if not ok or not decoded then
        vim.schedule(function()
          vim.notify(line, vim.log.levels.ERROR)
        end)
      end

      if os.getenv("LLM_SIDEKICK_DEBUG") == "true" then
        vim.schedule(function()
          vim.notify("Decoded: " .. vim.inspect(decoded))
        end)
      end

      if ok and decoded and decoded.choices and decoded.choices[1] and decoded.choices[1].delta then
        local reasoning_content = decoded.choices[1].delta.reasoning_content
        if reasoning_content and reasoning_content ~= "" then
          callback(message_types.REASONING, reasoning_content)
        end

        local content = decoded.choices[1].delta.content
        if content and content ~= "" then
          callback(message_types.DATA, content)
        end

        local tool_calls = decoded.choices[1].delta.tool_calls
        if tool_calls and tool_calls[1] and tool_calls[1]["function"] then
          local function_data = tool_calls[1]["function"]
          if tool_calls[1].id then
            if tool then
              callback(
                message_types.TOOL_STOP,
                vim.tbl_extend("force", {}, tool, { parameters = sjson.decode(tool.parameters) })
              )
            end

            tool = {
              id = tool_calls[1].id,
              name = function_data.name,
              parameters = "",
              state = {},
            }
            callback(
              message_types.TOOL_START,
              vim.tbl_extend("force", {}, tool, { parameters = sjson.decode(tool.parameters) })
            )
          end

          if tool and function_data.arguments and function_data.arguments ~= "" then
            tool.parameters = tool.parameters .. function_data.arguments
            callback(
              message_types.TOOL_DELTA,
              vim.tbl_extend("force", {}, tool, { parameters = sjson.decode(tool.parameters) })
            )
          end
        end
      end

      if decoded.choices and decoded.choices and decoded.choices[1].finish_reason == "tool_calls" then
        callback(
          message_types.TOOL_STOP,
          vim.tbl_extend("force", {}, tool, { parameters = sjson.decode(tool.parameters) })
        )
        tool = nil
      end
    end,
    on_stderr = function(_, text)
      if not text or text == "" then
        return
      end

      vim.schedule(function()
        vim.api.nvim_err_writeln("Error: " .. vim.inspect(text))
      end)
    end,
    on_exit = function(j, return_val)
      if j:result() and not vim.tbl_isempty(j:result()) then
        vim.schedule(function()
          local ok, res = pcall(sjson.decode, table.concat(j:result(), "\n"))
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
      local ok, decoded = pcall(sjson.decode, result)
      if not ok or not decoded or not decoded.choices or not decoded.choices[1] or not decoded.choices[1].message then
        vim.schedule(function()
          vim.api.nvim_err_writeln("Error: Failed to parse API response: " .. result)
        end)
        return
      end

      local reasoning_content = decoded.choices[1].message.reasoning_content
      if reasoning_content and reasoning_content ~= "" then
        callback(message_types.REASONING, reasoning_content)
      end

      local content = decoded.choices[1].message.content
      if content and content ~= "" and vim.NIL ~= content then
        callback(message_types.DATA, content)
      end
      callback(message_types.DONE, "")
    end,
  })

  job:start()

  return job
end

return openai
