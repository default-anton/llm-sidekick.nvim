local M = {}

local defaults = {
  smart_model = "anthropic.claude-3-5-sonnet-20241022-v2:0",
  fast_model = "anthropic.claude-3-5-haiku-20241022-v1:0",
  reasoning_model = "o1-preview",
}

local settings = vim.deepcopy(defaults)

function M.setup(opts)
  settings = vim.tbl_deep_extend("force", defaults, opts or {})
  local models = vim.tbl_keys(require("llm-sidekick").get_models())
  for key, model in pairs(settings) do
    if not vim.tbl_contains(models, model) then
      vim.notify(
        string.format("Invalid model '%s' for setting '%s'. Using default.", model, key),
        vim.log.levels.WARN
      )
      settings[key] = defaults[key]
    end
  end
end

function M.get_smart_model() return settings.smart_model end

function M.get_fast_model() return settings.fast_model end

function M.get_reasoning_model() return settings.reasoning_model end

function M.get_anthropic_api_key()
  local api_key = vim.env.LLM_SIDEKICK_ANTHROPIC_API_KEY or vim.env.ANTHROPIC_API_KEY
  if not api_key then
    error("No API key found. Set LLM_SIDEKICK_ANTHROPIC_API_KEY or ANTHROPIC_API_KEY in your environment.")
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

return M
