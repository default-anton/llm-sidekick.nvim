local MODELS = require "llm-sidekick.models"

local M = {}

local settings = {
  aliases = {
    sonnet = "claude-3-5-sonnet-latest",
  },
  default = "sonnet",
  models = vim.deepcopy(MODELS),
  yolo_mode = {
    file_operations = false,     -- Automatically accept file operations
    terminal_commands = false,   -- Automatically accept terminal commands
    auto_commit_changes = false, -- Automatically commit changes made by file operation tools
  },
  auto_commit_model = nil,       -- Model to use for auto-commit messages (nil = use default model)
  guidelines = "",               -- Global guidelines
  safe_terminal_commands = {},
  instruction_filenames = { "AGENTS.md" }, -- Filenames for project-specific instructions
}

function M.get_models()
  return settings.models
end

function M.get_model_settings(model)
  return settings.models[model] or error("Model not found: " .. model)
end

function M.get_model_settings_by_name(model)
  for _, s in pairs(settings.models) do
    if s.name == model then
      return s
    end
  end

  error("Model not found: " .. model)
end

function M.setup(opts)
  if opts == nil then
    opts = settings
  else
    vim.validate({
      aliases = { opts.aliases, "table", true },
      default = { opts.default, "string" },
      models = { opts.models, "table", true },
      yolo_mode = { opts.yolo_mode, "table", true },
      auto_commit_model = { opts.auto_commit_model, "string", true },
      guidelines = { opts.guidelines, "string", true },
      safe_terminal_commands = { opts.safe_terminal_commands, "table", true },
      instruction_filenames = { opts.instruction_filenames, "table", true },
    })

    opts.models = vim.tbl_deep_extend("force", settings.models, opts.models or {})
    opts.yolo_mode = vim.tbl_deep_extend("force", settings.yolo_mode, opts.yolo_mode or {})
    opts.guidelines = opts.guidelines or settings.guidelines
    opts.safe_terminal_commands = opts.safe_terminal_commands or settings.safe_terminal_commands
    opts.auto_commit_model = opts.auto_commit_model or settings.auto_commit_model
    opts.instruction_filenames = opts.instruction_filenames or settings.instruction_filenames

    settings = opts
  end

  -- Validate that default alias exists
  if not settings.aliases[settings.default] then
    error(string.format("Default alias '%s' is not defined in aliases", settings.default))
  end

  -- Validate all models
  local models = vim.tbl_keys(M.get_models())
  for alias, model in pairs(settings.aliases) do
    if not vim.tbl_contains(models, model) then
      vim.notify(
        string.format("Invalid model '%s' for alias '%s'", model, alias),
        vim.log.levels.WARN
      )
    end
  end
end

function M.has_model_for(alias)
  return settings.aliases[alias] ~= nil
end

function M.get_model(alias)
  if not alias then
    alias = settings.default
  end

  local model = settings.aliases[alias]
  if not model then
    vim.notify(
      string.format("Alias '%s' not found, using default", alias),
      vim.log.levels.WARN
    )
    return settings.aliases[settings.default]
  end
  return model
end

function M.get_aliases()
  return vim.tbl_keys(settings.aliases)
end

function M.auto_accept_file_operations()
  return settings.yolo_mode.file_operations
end

function M.auto_accept_terminal_commands()
  return settings.yolo_mode.terminal_commands
end

function M.auto_commit_changes()
  return settings.yolo_mode.auto_commit_changes
end

function M.safe_terminal_commands()
  return settings.safe_terminal_commands
end

function M.get_auto_commit_model()
  return settings.auto_commit_model or settings.default
end

function M.get_global_guidelines()
  return settings.guidelines
end

function M.get_openai_api_key()
  local api_key = vim.env.LLM_SIDEKICK_OPENAI_API_KEY or vim.env.OPENAI_API_KEY
  if not api_key then
    error("No API key found. Set LLM_SIDEKICK_OPENAI_API_KEY or OPENAI_API_KEY in your environment.")
  end

  return api_key
end

function M.get_gemini_api_key()
  local api_key = vim.env.LLM_SIDEKICK_GEMINI_API_KEY or vim.env.GEMINI_API_KEY
  if not api_key then
    error("No API key found. Set LLM_SIDEKICK_GEMINI_API_KEY or GEMINI_API_KEY in your environment.")
  end

  return api_key
end

function M.get_groq_api_key()
  local api_key = vim.env.LLM_SIDEKICK_GROQ_API_KEY or vim.env.GROQ_API_KEY
  if not api_key then
    error("No API key found. Set LLM_SIDEKICK_GROQ_API_KEY or GROQ_API_KEY in your environment.")
  end

  return api_key
end

function M.get_instruction_filenames()
  return settings.instruction_filenames
end

return M
