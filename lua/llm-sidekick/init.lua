local message_types = require "llm-sidekick.message_types"
local fs = require "llm-sidekick.fs"

local M = {}

local MODELS = {
  ["o1"] = {
    max_tokens = 100000,
    temperature = 0.0,
  },
  ["claude-3-5-sonnet-latest"] = {
    max_tokens = 8192,
    temperature = 0.3,
  },
  ["claude-3-5-haiku-latest"] = {
    max_tokens = 8192,
    temperature = 0.3,
  },
  ["anthropic.claude-3-5-sonnet-20241022-v2:0"] = {
    max_tokens = 8192,
    temperature = 0.3,
  },
  ["anthropic.claude-3-5-sonnet-20240620-v1:0"] = {
    max_tokens = 4096,
    temperature = 0.3,
  },
  ["anthropic.claude-3-5-haiku-20241022-v1:0"] = {
    max_tokens = 8192,
    temperature = 0.3,
  },
  ["anthropic.claude-3-haiku-20240307-v1:0"] = {
    max_tokens = 4096,
    temperature = 0.3,
  },
  ["o1-preview"] = {
    max_tokens = 32768,
    temperature = 0.0,
  },
  ["o1-mini"] = {
    max_tokens = 65536,
    temperature = 0.0,
  },
  ["gpt-4o"] = {
    max_tokens = 16384,
    temperature = 0.5,
  },
  ["gpt-4o-2024-11-20"] = {
    max_tokens = 16384,
    temperature = 0.5,
  },
  ["gpt-4o-2024-08-06"] = {
    max_tokens = 16384,
    temperature = 0.5,
  },
  ["gpt-4o-2024-05-13"] = {
    max_tokens = 4096,
    temperature = 0.5,
  },
  ["gpt-4o-mini"] = {
    max_tokens = 16384,
    temperature = 0.5,
  },
  ["ollama-qwen2.5-coder:1.5b"] = {
    max_tokens = 8192,
    temperature = 0.2,
  },
}

function M.setup(opts)
  require("llm-sidekick.settings").setup(opts or {})
end

function M.get_models()
  return MODELS
end

function M.get_model_default_settings(model)
  return MODELS[model] or error("Model not found: " .. model)
end

local DEFAULT_SETTTINGS = {
  model = "",
  max_tokens = 4096,
  stream = true,
  temperature = 0.0,
}

function M.get_prompt(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local full_prompt = table.concat(lines, "\n")
  return full_prompt
end

function M.parse_prompt(prompt)
  local options = {
    messages = {},
    settings = vim.deepcopy(DEFAULT_SETTTINGS),
  }
  local lines = vim.split(prompt, "\n", { plain = true })
  for _, line in ipairs(lines) do
    if line:sub(1, 7) == "SYSTEM:" then
      options.messages[#options.messages + 1] = { role = "system", content = line:sub(8) }
      goto continue
    end
    if line:sub(1, 5) == "USER:" then
      options.messages[#options.messages + 1] = { role = "user", content = line:sub(6) }
      goto continue
    end
    if line:sub(1, 10) == "ASSISTANT:" then
      options.messages[#options.messages + 1] = { role = "assistant", content = line:sub(11) }
      goto continue
    end
    if line:sub(1, 6) == "MODEL:" then
      options.settings.model = vim.trim(line:sub(7))
      goto continue
    end
    if line:sub(1, 11) == "MAX_TOKENS:" then
      options.settings.max_tokens = tonumber(vim.trim(line:sub(12)))
      goto continue
    end
    if line:sub(1, 7) == "STREAM:" then
      options.settings.stream = vim.trim(line:sub(8)) == "true"
      goto continue
    end
    if line:sub(1, 12) == "TEMPERATURE:" then
      options.settings.temperature = tonumber(vim.trim(line:sub(13)))
      goto continue
    end

    if #options.messages > 0 then
      options.messages[#options.messages].content = options.messages[#options.messages].content .. "\n" .. line
    end

    ::continue::
  end

  for _, message in ipairs(options.messages) do
    message.content = vim.trim(message.content)
  end

  if #options.messages > 0 and options.messages[#options.messages].role == "user" then
    local text = options.messages[#options.messages].content
    if text:find("imgimgimg") then
      local base64_image = vim.fn.system("pngpaste -b")
      if vim.v.shell_error == 0 then
        vim.notify("Image found in clipboard", vim.log.levels.INFO)
        text = text:gsub("imgimgimg", "")

        options.messages[#options.messages] = {
          role = "user",
          content = {
            {
              type = "image",
              source = {
                data = base64_image,
                type = "base64",
                media_type = "image/png",
              },
            },
            { type = "text", text = text },
          },
        }
      else
        vim.notify("No image found in clipboard", vim.log.levels.WARN)
        options.messages[#options.messages].content = text:gsub("imgimgimg", "")
      end
    end
  end

  return options
end

local function get_last_user_message(options)
  if not options or not options.messages then
    return nil
  end
  for i = #options.messages, 1, -1 do
    local message = options.messages[i]
    if message.role == "user" then
      local content = message.content
      if type(content) == "string" then
        -- Handle text-only messages
        local _, end_pos = content:find("</editor_context>")
        if end_pos then
          return content:sub(end_pos + 1):gsub("^%s*", "")
        else
          return content
        end
      elseif type(content) == "table" then
        -- Handle mixed content messages (with images and text)
        for _, item in ipairs(content) do
          if item.type == "text" then
            local text = item.text
            local _, end_pos = text:find("</editor_context>")
            if end_pos then
              return text:sub(end_pos + 1):gsub("^%s*", "")
            else
              return text
            end
          end
        end
      end
    end
  end
  return nil
end

local function create_temporary_chat_file(sanitized_message)
  local temp_dir = vim.fn.tempname()
  vim.fn.mkdir(temp_dir, "p")
  local file_name = temp_dir .. sanitized_message .. ".llmchat"
  vim.api.nvim_buf_set_name(0, file_name)
end

function M.ask(prompt_bufnr)
  local buf_lines = vim.api.nvim_buf_get_lines(prompt_bufnr, 0, -1, false)
  local full_prompt = table.concat(buf_lines, "\n")
  local prompt = M.parse_prompt(full_prompt)

  local current_name = vim.api.nvim_buf_get_name(0)
  if current_name == "" then
    local last_user_message = get_last_user_message(prompt)
    if last_user_message then
      local trimmed_message = vim.trim(last_user_message)
      local sanitized_message = trimmed_message:gsub('[^%w-]', '_')
      local max_length = 50
      if #sanitized_message > max_length then
        sanitized_message = sanitized_message:sub(1, max_length) .. '...'
      end

      create_temporary_chat_file(sanitized_message)
    end
  end

  local current_line = "ASSISTANT: "
  vim.api.nvim_buf_set_lines(prompt_bufnr, -1, -1, false, { "", current_line })

  local client
  if vim.startswith(prompt.settings.model, "claude-") then
    client = require "llm-sidekick.anthropic".new()
  elseif vim.startswith(prompt.settings.model, "o1") or vim.startswith(prompt.settings.model, "gpt-") then
    client = require "llm-sidekick.openai".new()
  elseif vim.startswith(prompt.settings.model, "ollama-") then
    client = require "llm-sidekick.openai".new("http://localhost:11434/v1/chat/completions")
  elseif vim.startswith(prompt.settings.model, "anthropic.") then
    client = require "llm-sidekick.bedrock".new()
  else
    error("Model not supported: " .. prompt.settings.model)
  end

  client:chat(prompt.messages, prompt.settings, function(state, chars)
    if not vim.api.nvim_buf_is_valid(prompt_bufnr) then
      return
    end

    local lines = vim.split(chars, "\n", { plain = true })
    local success = pcall(function()
      local last_line = vim.api.nvim_buf_get_lines(prompt_bufnr, -2, -1, false)[1]
      local new_last_line = last_line .. lines[1]
      vim.api.nvim_buf_set_lines(prompt_bufnr, -2, -1, false, { new_last_line })
      if #lines > 1 then
        vim.api.nvim_buf_set_lines(prompt_bufnr, -1, -1, false, vim.list_slice(lines, 2))
      end
    end)

    if not success then
      return
    end

    if message_types.DONE == state and vim.api.nvim_buf_is_valid(prompt_bufnr) then
      success = pcall(function()
        vim.api.nvim_buf_set_lines(prompt_bufnr, -1, -1, false, { "", "USER: " })
      end)
      if success then
        vim.cmd('write')
      end
    end
  end)
end

---Read the entire contents of a file
---@param path string The path to the file to read
---@return string content The file contents or an empty string if file cannot be opened
function M.read_file(path)
  return fs.read_file(path) or ""
end

return M
