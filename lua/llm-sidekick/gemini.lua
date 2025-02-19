local message_types = require("llm-sidekick.message_types")
local sjson = require("llm-sidekick.sjson")

local gemini = {}

function gemini.new()
  local api_key = require("llm-sidekick.settings").get_gemini_api_key()

  return setmetatable({
      base_url = 'https://generativelanguage.googleapis.com/v1alpha/models',
      api_key = api_key,
    },
    { __index = gemini }
  )
end

function gemini:chat(opts, callback)
  local messages = opts.messages
  local settings = opts.settings
  callback = vim.schedule_wrap(callback)

  local model_settings = require("llm-sidekick.settings").get_model_settings_by_name(settings.model)

  local system_message = nil
  for _, msg in ipairs(messages) do
    if msg.role == "system" then
      system_message = msg
      break
    end
  end

  local tool_name_by_id = {}
  local contents = {}

  for index, msg in ipairs(messages) do
    if msg.role ~= "system" then
      if type(msg.content) == "table" then
        local parts = {}
        for _, item in ipairs(msg.content) do
          if item.type == "image_url" then
            local _, _, mime_type, base64_data = item.image_url.url:find("data:(.+);base64,(.+)")
            table.insert(parts, {
              inlineData = {
                data = base64_data,
                mimeType = mime_type,
              },
            })
          elseif item.type == "text" then
            table.insert(parts, { text = item.text })
          end
        end

        table.insert(contents, {
          role = msg.role == "assistant" and "model" or "user",
          parts = parts,
        })
      elseif msg.tool_calls then
        local parts = {}
        for _, tool_call in ipairs(msg.tool_calls) do
          tool_name_by_id[tool_call.id] = tool_call["function"].name
          table.insert(parts, {
            {
              functionCall = {
                name = tool_call["function"].name,
                args = sjson.decode(tool_call["function"].arguments),
              }
            },
          })
        end

        table.insert(contents, { role = "model", parts = parts })
      elseif msg.role == "tool" then
        -- Detect contiguous tool responses and merge them
        local prev = messages[index - 1]
        if prev and prev.role == "user" and prev.parts and prev.parts[1] and prev.parts[1].functionResponse then
          table.insert(prev.parts, {
            functionResponse = {
              name = tool_name_by_id[msg.tool_call_id],
              response = {
                result = msg.content,
              }
            },
          })
        else
          table.insert(contents, {
            role = "user",
            parts = {
              {
                functionResponse = {
                  name = tool_name_by_id[msg.tool_call_id],
                  response = {
                    result = msg.content,
                  }
                },
              },
            },
          })
        end
      else
        table.insert(contents, {
          role = msg.role == "assistant" and "model" or "user",
          parts = { { text = msg.content } },
        })
      end
    end
  end

  local data = {
    contents = contents,
    generationConfig = {
      temperature = settings.temperature,
      maxOutputTokens = settings.max_tokens,
      topK = model_settings.top_k,
      topP = 0.95,
      responseMimeType = "text/plain",
    },
    safetySettings = {
      { category = "HARM_CATEGORY_HARASSMENT",        threshold = "BLOCK_NONE" },
      { category = "HARM_CATEGORY_HATE_SPEECH",       threshold = "BLOCK_NONE" },
      { category = "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold = "BLOCK_NONE" },
      { category = "HARM_CATEGORY_DANGEROUS_CONTENT", threshold = "BLOCK_NONE" },
      { category = "HARM_CATEGORY_CIVIC_INTEGRITY",   threshold = "BLOCK_NONE" }
    },
  }

  if opts.tools then
    local gemini_converter = require("llm-sidekick.tools.gemini")
    data.tools = {
      { functionDeclarations = vim.tbl_map(function(tool) return gemini_converter.convert_spec(tool.spec) end, opts.tools) },
    }
    data.toolConfig = {
      functionCallingConfig = {
        mode = "ANY"
      }
    }
  end

  -- Include thoughts for thinking models
  if model_settings.reasoning then
    data.generationConfig.thinkingConfig = {
      includeThoughts = true
    }
  end

  if system_message then
    data.systemInstruction = {
      role = "user",
      parts = { { text = system_message.content } }
    }
  end

  local url = string.format(
    "%s/%s:streamGenerateContent?alt=sse&key=%s",
    self.base_url,
    settings.model,
    self.api_key
  )

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
    url
  }

  if os.getenv("LLM_SIDEKICK_DEBUG") == "true" then
    vim.notify("Request: " .. vim.inspect(data), vim.log.levels.INFO)
  end

  local job = require('plenary.job'):new({
    command = curl,
    args = args,
    on_stdout = function(_, line)
      line = line:gsub("^data: ", "")
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

      if decoded.candidates and decoded.candidates[1] and
          decoded.candidates[1].content and decoded.candidates[1].content.parts then
        for _, part in ipairs(decoded.candidates[1].content.parts) do
          if part.thought then
            callback(message_types.REASONING, part.text)
          elseif part.functionCall then
            vim.g.llm_sidekick_gemini_tool_call_counter = (vim.g.llm_sidekick_gemini_tool_call_counter or 0) + 1
            local tool = {
              id = tostring(vim.g.llm_sidekick_gemini_tool_call_counter),
              name = part.functionCall.name,
              parameters = part.functionCall.args,
              state = {},
            }
            callback(message_types.TOOL_START,
              vim.tbl_extend("force", {}, tool, { parameters = vim.deepcopy(tool.parameters) }))
            callback(message_types.TOOL_DELTA,
              vim.tbl_extend("force", {}, tool, { parameters = vim.deepcopy(tool.parameters) }))
            callback(message_types.TOOL_STOP,
              vim.tbl_extend("force", {}, tool, { parameters = vim.deepcopy(tool.parameters) }))
          else
            callback(message_types.DATA, part.text)
          end
        end
      end
    end,
    on_stderr = function(_, text)
      if not text or text == "" then
        return
      end

      vim.schedule(function()
        vim.notify("Error: " .. vim.inspect(text), vim.log.levels.ERROR)
      end)
    end,
    on_exit = function(j, return_val)
      callback(message_types.DONE, "")

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
    end,
  })

  job:start()

  return job
end

return gemini
