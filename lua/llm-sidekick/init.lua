local message_types = require "llm-sidekick.message_types"
local fs = require "llm-sidekick.fs"
local MODELS = require "llm-sidekick.models"

local M = {}

function M.setup(opts)
  require("llm-sidekick.settings").setup(opts or {})
end

function M.get_models()
  return MODELS
end

function M.get_default_model_settings(model)
  return MODELS[model] or error("Model not found: " .. model)
end

local DEFAULT_SETTTINGS = {
  stream = true,
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
  local processed_keys = {}
  local lines = vim.split(prompt, "\n", { plain = true })
  for _, line in ipairs(lines) do
    if line:sub(1, 7) == "SYSTEM:" and not processed_keys.system then
      options.messages[#options.messages + 1] = { role = "system", content = line:sub(8) }
      processed_keys.system = true
      goto continue
    end
    if line:sub(1, 5) == "USER:" then
      options.messages[#options.messages + 1] = { role = "user", content = line:sub(6) }
      goto continue
    end
    if line:sub(1, 10) == "ASSISTANT:" then
      local content = line:sub(11)
      -- NOTE: delete all <llm_sidekick_thinking> tags
      content = content:gsub("<llm_sidekick_thinking>.-</llm_sidekick_thinking>", "")
      options.messages[#options.messages + 1] = { role = "assistant", content = content }
      goto continue
    end
    if line:sub(1, 6) == "MODEL:" and not processed_keys.model then
      options.settings.model = vim.trim(line:sub(7))
      processed_keys.model = true
      goto continue
    end
    if line:sub(1, 11) == "MAX_TOKENS:" and not processed_keys.max_tokens then
      options.settings.max_tokens = tonumber(vim.trim(line:sub(12)))
      processed_keys.max_tokens = true
      goto continue
    end
    if line:sub(1, 7) == "STREAM:" and not processed_keys.stream then
      options.settings.stream = vim.trim(line:sub(8)) == "true"
      processed_keys.stream = true
      goto continue
    end
    if line:sub(1, 12) == "TEMPERATURE:" and not processed_keys.temperature then
      options.settings.temperature = tonumber(vim.trim(line:sub(13)))
      processed_keys.temperature = true
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
      elseif vim.startswith(options.settings.model, "gpt") or options.settings.model == "o1" then
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
        vim.api.nvim_err_writeln("Model does not support images: " .. options.settings.model)
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

  local model_settings = M.get_default_model_settings(prompt.settings.model)
  if model_settings.no_system_prompt then
    -- prepend the system prompt to the first message
    local system_prompt = vim.tbl_filter(function(m) return m.role == "system" end, prompt.messages)[1]
    prompt.messages = vim.tbl_filter(function(m) return m.role ~= "system" end, prompt.messages)
    if system_prompt then
      prompt.messages[1].content = system_prompt.content .. "\n\n" .. prompt.messages[1].content
    end
  end

  local current_line = "ASSISTANT: "
  vim.api.nvim_buf_set_lines(prompt_bufnr, -1, -1, false, { "", current_line })

  local client
  if vim.startswith(prompt.settings.model, "claude-") then
    client = require "llm-sidekick.anthropic".new()
  elseif vim.startswith(prompt.settings.model, "o1") or vim.startswith(prompt.settings.model, "gpt-") then
    client = require "llm-sidekick.openai".new({ api_key = require("llm-sidekick.settings").get_openai_api_key() })
  elseif vim.startswith(prompt.settings.model, "ollama-") then
    client = require "llm-sidekick.openai".new({ url = "http://localhost:11434/v1/chat/completions" })
  elseif vim.startswith(prompt.settings.model, "deepseek") then
    local api_key = require("llm-sidekick.settings").get_deepseek_api_key()
    client = require "llm-sidekick.openai".new({ url = "https://api.deepseek.com/v1/chat/completions", api_key = api_key })
  elseif vim.startswith(prompt.settings.model, "anthropic.") then
    client = require "llm-sidekick.bedrock".new()
  elseif vim.startswith(prompt.settings.model, "gemini") then
    client = require "llm-sidekick.gemini".new()
  else
    error("Model not supported: " .. prompt.settings.model)
  end

  local in_reasoning_tag = false

  client:chat(prompt.messages, prompt.settings, function(state, chars)
    if not vim.api.nvim_buf_is_valid(prompt_bufnr) then
      return
    end

    local lines = vim.split(chars, "\n")
    local success = pcall(function()
      if state == message_types.REASONING and not in_reasoning_tag then
        vim.api.nvim_buf_set_lines(prompt_bufnr, -1, -1, false, { "", "<llm_sidekick_thinking>", "" })
        in_reasoning_tag = true
      end

      if state == message_types.DATA and in_reasoning_tag then
        vim.api.nvim_buf_set_lines(prompt_bufnr, -1, -1, false, { "</llm_sidekick_thinking>", "", "" })
        in_reasoning_tag = false
      end

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
      if vim.b[prompt_bufnr].llm_sidekick_auto_apply then
        require("llm-sidekick.file_editor").apply_modifications(prompt_bufnr, true)
        pcall(function()
          vim.api.nvim_win_close(0, true)

          if vim.api.nvim_buf_is_valid(prompt_bufnr) then
            vim.api.nvim_buf_delete(prompt_bufnr, { force = true })
          end
        end)
      else
        pcall(function()
          vim.api.nvim_buf_set_lines(prompt_bufnr, -1, -1, false, { "", "USER: " })
        end)
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
