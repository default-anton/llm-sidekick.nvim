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
  ["gemini-exp-1206"] = {
    max_tokens = 8192,
    temperature = 1.0,
    top_k = 64,
  },
  ["gemini-2.0-flash-exp"] = {
    max_tokens = 8192,
    temperature = 1.0,
    top_k = 40,
  },
  ["gemini-2.0-flash-thinking-exp-1219"] = {
    max_tokens = 8192,
    temperature = 1.0,
    top_k = 64,
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
    -- Check for llm_sidekick_image tags
    for image_path in text:gmatch("<llm_sidekick_image>(.-)</llm_sidekick_image>") do
      if not vim.fn.filereadable(image_path) == 1 then
        goto continue
      end

      local function get_base64_command()
        if vim.fn.has("mac") == 1 then
          return { "base64", "-i", image_path }
        else
          return { "base64", "-w0", image_path }
        end
      end

      local base64_image = vim.fn.system(get_base64_command())
      if vim.v.shell_error ~= 0 then
        vim.api.nvim_err_writeln("Failed to read image: " .. image_path)
        goto continue
      end

      -- Remove any newlines that might be present in the base64 output
      base64_image = base64_image:gsub("[\n\r]", "")
      text = text:gsub("<llm_sidekick_image>" .. vim.pesc(image_path) .. "</llm_sidekick_image>", "")
      local mime_type = vim.fn.systemlist({ "file", "--mime-type", "--brief", image_path })[1]

      local image
      if vim.startswith(options.settings.model, "claude") or vim.startswith(options.settings.model, "anthropic.claude") then
        image = {
          type = "image",
          source = {
            data = base64_image,
            type = "base64",
            media_type = mime_type,
          },
        }
      elseif vim.startswith(options.settings.model, "gpt") then
        image = {
          type = "image_url",
          image_url = { url = string.format("data:%s;base64,%s", mime_type, base64_image) },
        }
      elseif vim.startswith(options.settings.model, "gemini") then
        image = {
          type = "image",
          inlineData = {
            data = base64_image,
            mimeType = mime_type,
          },
        }
      else
        vim.api.nvim_err_writeln("Model not supported: " .. options.settings.model)
        return options
      end

      options.messages[#options.messages] = {
        role = "user",
        content = {
          image,
          { type = "text", text = text },
        },
      }

      ::continue::
    end
  end

  return options
end

function M.ask(prompt_bufnr)
  local buf_lines = vim.api.nvim_buf_get_lines(prompt_bufnr, 0, -1, false)
  local full_prompt = table.concat(buf_lines, "\n")
  local prompt = M.parse_prompt(full_prompt)

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
  elseif vim.startswith(prompt.settings.model, "gemini") then
    client = require "llm-sidekick.gemini".new()
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
      pcall(function()
        vim.api.nvim_buf_set_lines(prompt_bufnr, -1, -1, false, { "", "USER: " })
      end)
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
