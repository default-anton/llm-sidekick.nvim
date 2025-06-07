local message_types = require("llm-sidekick.message_types")
local sjson = require("llm-sidekick.sjson")
local utils = require("llm-sidekick.utils")
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

  local data = {
    model = settings.model,
    stream = settings.stream,
    messages = messages,
    max_tokens = settings.max_tokens,
    max_completion_tokens = settings.max_completion_tokens,
    temperature = settings.temperature,
  }

  if opts.tools then
    local openai_converter = require("llm-sidekick.tools.openai")
    data.tools = vim.tbl_map(function(tool) return openai_converter.convert_spec(tool.spec) end, opts.tools)

    if settings.parallel_tool_calls then
      data.parallel_tool_calls = true
    end
  end

  if settings.response_format then
    data.response_format = settings.response_format
  end

  if settings.reasoning_effort then
    data.reasoning_effort = settings.reasoning_effort
  end

  local body = vim.json.encode(data)
  if opts.tools then
    for _, tool in ipairs(opts.tools) do
      body = body:gsub(vim.json.encode(tool.spec.input_schema.properties), tool.json_props)
    end
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
    utils.log("Request: " .. vim.inspect(data), vim.log.levels.DEBUG)
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
      if line == "[DONE]" or line == "" then
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
          utils.log("Decoded: " .. vim.inspect(decoded), vim.log.levels.DEBUG)
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
        if tool_calls then
          for _, tool_call in ipairs(tool_calls) do
            if tool_call["function"] then
              local function_data = tool_call["function"]
              if tool_call.id then
                if tool then
                  callback(
                    message_types.TOOL_STOP,
                    vim.tbl_extend("force", {}, tool, { parameters = sjson.decode(tool.parameters) })
                  )
                end

                tool = {
                  id = tool_call.id,
                  name = function_data.name,
                  parameters = "",
                  state = {},
                }
                callback(
                  message_types.TOOL_START,
                  vim.tbl_extend("force", {}, tool, { parameters = {} })
                )

                if function_data.arguments and function_data.arguments ~= "" then
                  local params = sjson.decode(function_data.arguments)
                  callback(message_types.TOOL_DELTA, vim.tbl_extend("force", {}, tool, { parameters = params }))
                  callback(message_types.TOOL_STOP, vim.tbl_extend("force", {}, tool, { parameters = params }))
                  tool = nil
                end
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
        end
      end

      if tool and decoded.choices and decoded.choices and decoded.choices[1].finish_reason then
        callback(
          message_types.TOOL_STOP,
          vim.tbl_extend("force", {}, tool, { parameters = sjson.decode(tool.parameters) })
        )
        tool = nil
      end
    end,
    on_exit = function(j, return_val)
      if data.stream then
        callback(message_types.DONE, "")
      end

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
          vim.notify("Error: Failed to parse API response: " .. result, vim.log.levels.ERROR)
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

-- Generates a single, non-streaming completion.
-- @param opts table: Contains messages and settings (model, temperature, etc.).
-- @param callback function: Called with (err, content). err is nil on success.
function openai:generate_completion(opts, callback)
  local messages = opts.messages
  local settings = opts.settings
  callback = vim.schedule_wrap(callback)

  local data = {
    model = settings.model,
    stream = false, -- Ensure stream is false for single completion
    messages = messages,
    max_tokens = settings.max_tokens,
    max_completion_tokens = settings.max_completion_tokens,
    temperature = settings.temperature,
    -- No tools for simple completion
  }

  if settings.response_format then
    data.response_format = settings.response_format
  end

  local body = vim.json.encode(data)
  local curl = require("llm-sidekick.executables").get_curl_executable()
  local args = {
    '-s',
    '-H', 'Content-Type: application/json',
    '-d', body,
  }

  if self.api_key then
    table.insert(args, '-H')
    table.insert(args, 'Authorization: Bearer ' .. self.api_key)
  end
  table.insert(args, self.url)

  if os.getenv("LLM_SIDEKICK_DEBUG") == "true" then
    utils.log("Completion Request: " .. vim.inspect(data), vim.log.levels.DEBUG)
  end

  require('plenary.job'):new({
    command = curl,
    args = args,
    on_exit = function(j, return_val)
      if return_val ~= 0 then
        local stderr = table.concat(j:stderr_result() or {}, "\n")
        local stdout = table.concat(j:result() or {}, "\n")
        local err_msg = string.format("Completion API error (exit %d): %s %s", return_val, stderr, stdout)
        utils.log(err_msg, vim.log.levels.ERROR)
        callback(err_msg, nil)
        return
      end

      local result = table.concat(j:result(), "\n")
      local ok, decoded = pcall(vim.json.decode, result, { luanil = { object = true, array = true } })

      if not ok or not decoded then
        local err_msg = string.format("Failed to decode completion API response: %s", result)
        utils.log(err_msg, vim.log.levels.ERROR)
        callback(err_msg, nil)
        return
      end

      if decoded.error then
        local err_msg = string.format("Completion API returned error: %s",
          decoded.error.message or vim.inspect(decoded.error))
        utils.log(err_msg, vim.log.levels.ERROR)
        callback(err_msg, nil)
        return
      end

      if not decoded.choices or not decoded.choices[1] or not decoded.choices[1].message or not decoded.choices[1].message.content then
        local err_msg = string.format("Unexpected completion API response structure: %s", result)
        utils.log(err_msg, vim.log.levels.ERROR)
        callback(err_msg, nil)
        return
      end

      if os.getenv("LLM_SIDEKICK_DEBUG") == "true" then
        utils.log("Completion Response: " .. vim.inspect(decoded), vim.log.levels.DEBUG)
      end

      callback(nil, decoded.choices[1].message.content)
    end,
  }):start()
end

return openai
