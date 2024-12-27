local message_types = require("llm-sidekick.message_types")
local gemini = {}

function gemini.new(url)
  local api_key = require("llm-sidekick.settings").get_gemini_api_key()

  return setmetatable({
      base_url = url or 'https://generativelanguage.googleapis.com/v1beta/models',
      api_key = api_key
    },
    { __index = gemini }
  )
end

function gemini:chat(messages, settings, callback)
  callback = vim.schedule_wrap(callback)

  local system_message = nil
  for _, msg in ipairs(messages) do
    if msg.role == "system" then
      system_message = msg
      break
    end
  end

  local contents = vim.tbl_map(function(msg)
    if msg.role == "system" then
      return nil
    end
    if type(msg.content) == "table" then
      local parts = {}
      for _, item in ipairs(msg.content) do
        if item.type == "image" then
          table.insert(parts, { inlineData = item.inlineData })
        elseif item.type == "text" then
          table.insert(parts, { text = item.text })
        end
      end
      return {
        role = msg.role == "assistant" and "model" or "user",
        parts = parts,
      }
    else
      return {
        role = msg.role == "assistant" and "model" or "user",
        parts = {
          {
            text = msg.content,
          },
        },
      }
    end
  end, messages)
  contents = vim.tbl_filter(function(msg) return msg ~= nil end, contents)

  local data = {
    contents = contents,
    generationConfig = {
      temperature = settings.temperature,
      maxOutputTokens = settings.max_tokens,
      topK = require("llm-sidekick").get_models()[settings.model].top_k,
      topP = 0.95,
      responseMimeType = "text/plain"
    },
    safetySettings = {
      { category = "HARM_CATEGORY_HARASSMENT",        threshold = "BLOCK_NONE" },
      { category = "HARM_CATEGORY_HATE_SPEECH",       threshold = "BLOCK_NONE" },
      { category = "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold = "BLOCK_NONE" },
      { category = "HARM_CATEGORY_DANGEROUS_CONTENT", threshold = "BLOCK_NONE" },
      { category = "HARM_CATEGORY_CIVIC_INTEGRITY",   threshold = "BLOCK_NONE" }
    }
  }

  if system_message then
    data.systemInstruction = {
      role = "user",
      parts = {
        {
          text = system_message.content
        }
      }
    }
  end

  local url = string.format("%s/%s:streamGenerateContent?alt=sse&key=%s",
    self.base_url, settings.model, self.api_key)

  local curl = require("llm-sidekick.executables").get_curl_executable()
  local args = {
    '-s',
    '--no-buffer',
    '-H', 'Content-Type: application/json',
    '-d', vim.json.encode(data),
    url
  }

  require('plenary.job'):new({
    command = curl,
    args = args,
    on_stdout = function(_, line)
      line = line:gsub("^data: ", "")
      if line == "" then
        return
      end

      local ok, decoded = pcall(vim.json.decode, line)
      if ok and decoded and decoded.candidates and decoded.candidates[1] and
          decoded.candidates[1].content and decoded.candidates[1].content.parts then
        for _, part in ipairs(decoded.candidates[1].content.parts) do
          if part.text then
            callback(message_types.DATA, part.text)
          end
        end
      end
    end,
    on_stderr = function(_, text)
      vim.schedule(function()
        vim.api.nvim_err_writeln("Error: API request failed with error " .. text)
      end)
    end,
    on_exit = function(_, return_val)
      callback(message_types.DONE, "")

      if return_val ~= 0 then
        vim.schedule(function()
          vim.api.nvim_err_writeln("Error: API request failed with exit code " .. return_val)
        end)
      end
    end,
  }):start()
end

return gemini
