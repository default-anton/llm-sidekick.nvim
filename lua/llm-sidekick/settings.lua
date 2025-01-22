local M = {}

local defaults = {
  aliases = {
    sonnet = "claude-3-5-sonnet-latest",
  },
  default = "sonnet",
}

local settings = vim.deepcopy(defaults)

function M.setup(opts)
  if opts == nil then
    opts = settings
  else
    vim.validate({
      aliases = { opts.aliases, "table", true },
      default = { opts.default, "string" },
    })

    settings = opts
  end

  -- Validate that default alias exists
  if not settings.aliases[settings.default] then
    error(string.format("Default alias '%s' is not defined in aliases", settings.default))
  end

  -- Validate all models
  local models = vim.tbl_keys(require("llm-sidekick").get_models())
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

function M.get_anthropic_api_key()
  local api_key = vim.env.LLM_SIDEKICK_ANTHROPIC_API_KEY or vim.env.ANTHROPIC_API_KEY
  if not api_key then
    error("No API key found. Set LLM_SIDEKICK_ANTHROPIC_API_KEY or ANTHROPIC_API_KEY in your environment.")
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

function M.get_openai_api_key()
  local api_key = vim.env.LLM_SIDEKICK_OPENAI_API_KEY or vim.env.OPENAI_API_KEY
  if not api_key then
    error("No API key found. Set LLM_SIDEKICK_OPENAI_API_KEY or OPENAI_API_KEY in your environment.")
  end

  return api_key
end

function M.get_deepseek_api_key()
  local api_key = vim.env.LLM_SIDEKICK_DEEPSEEK_API_KEY or vim.env.DEEPSEEK_API_KEY
  if not api_key then
    error("No API key found. Set LLM_SIDEKICK_DEEPSEEK_API_KEY or DEEPSEEK_API_KEY in your environment.")
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

return M
