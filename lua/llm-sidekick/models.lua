return {
  ["deepseek-chat"] = {
    name = "deepseek/deepseek-chat",
    max_tokens = 8192,
    -- https://api-docs.deepseek.com/quick_start/parameter_settings
    temperature = 0.0,
  },
  ["claude-3-7-sonnet-latest"] = {
    name = "anthropic/claude-3-7-sonnet-latest",
    max_tokens = 32768,
    temperature = 0.6,
  },
  ["claude-3-5-sonnet-latest"] = {
    name = "anthropic/claude-3-5-sonnet-latest",
    max_tokens = 8192,
    temperature = 0.6,
  },
  ["claude-3-5-haiku-latest"] = {
    name = "anthropic/claude-3-5-haiku-latest",
    max_tokens = 8192,
    temperature = 0.6,
  },
  ["anthropic.claude-3-7-sonnet"] = {
    name = "bedrock/us.anthropic.claude-3-7-sonnet-20250219-v1:0",
    max_tokens = 32768,
    temperature = 0.6,
  },
  ["anthropic.claude-3-5-sonnet-20241022-v2:0"] = {
    name = "bedrock/anthropic.claude-3-5-sonnet-20241022-v2:0",
    max_tokens = 8192,
    temperature = 0.6,
  },
  ["anthropic.claude-3-5-sonnet-20240620-v1:0"] = {
    name = "bedrock/anthropic.claude-3-5-sonnet-20240620-v1:0",
    max_tokens = 4096,
    temperature = 0.6,
  },
  ["anthropic.claude-3-5-haiku-20241022-v1:0"] = {
    name = "bedrock/anthropic.claude-3-5-haiku-20241022-v1:0",
    max_tokens = 8192,
    temperature = 0.6,
  },
  ["anthropic.claude-3-haiku-20240307-v1:0"] = {
    name = "bedrock/anthropic.claude-3-haiku-20240307-v1:0",
    max_tokens = 4096,
    temperature = 0.6,
  },
  ["o1-low"] = {
    name = "openai/o1",
    reasoning_effort = "low", -- can be "low", "medium", "high"
    temperature = nil,        -- temperature is not supported
    reasoning = true,
  },
  ["o1-medium"] = {
    name = "openai/o1",
    reasoning_effort = "medium", -- can be "low", "medium", "high"
    temperature = nil,           -- temperature is not supported
    reasoning = true,
  },
  ["o1-high"] = {
    name = "openai/o1",
    reasoning_effort = "high", -- can be "low", "medium", "high"
    temperature = nil,         -- temperature is not supported
    reasoning = true,
  },
  ["o1-low-chat"] = {
    name = "openai/o1",
    reasoning_effort = "low", -- can be "low", "medium", "high"
    temperature = nil,        -- temperature is not supported
    reasoning = true,
    just_chatting = true,
  },
  ["o1-medium-chat"] = {
    name = "openai/o1",
    reasoning_effort = "medium", -- can be "low", "medium", "high"
    temperature = nil,           -- temperature is not supported
    reasoning = true,
    just_chatting = true,
  },
  ["o1-high-chat"] = {
    name = "openai/o1",
    reasoning_effort = "high", -- can be "low", "medium", "high"
    temperature = nil,         -- temperature is not supported
    reasoning = true,
    just_chatting = true,
  },
  ["o3-mini-low"] = {
    name = "openai/o3-mini",
    reasoning_effort = "low", -- can be "low", "medium", "high"
    temperature = nil,        -- temperature is not supported
    reasoning = true,
  },
  ["o3-mini-medium"] = {
    name = "openai/o3-mini",
    reasoning_effort = "medium", -- can be "low", "medium", "high"
    temperature = nil,           -- temperature is not supported
    reasoning = true,
  },
  ["o3-mini-high"] = {
    name = "openai/o3-mini",
    reasoning_effort = "high", -- can be "low", "medium", "high"
    temperature = nil,         -- temperature is not supported
    reasoning = true,
  },
  ["o3-mini-low-chat"] = {
    name = "openai/o3-mini",
    reasoning_effort = "low", -- can be "low", "medium", "high"
    temperature = nil,        -- temperature is not supported
    reasoning = true,
    just_chatting = true,
  },
  ["o3-mini-medium-chat"] = {
    name = "openai/o3-mini",
    reasoning_effort = "medium", -- can be "low", "medium", "high"
    temperature = nil,           -- temperature is not supported
    reasoning = true,
    just_chatting = true,
  },
  ["o3-mini-high-chat"] = {
    name = "openai/o3-mini",
    reasoning_effort = "high", -- can be "low", "medium", "high"
    temperature = nil,         -- temperature is not supported
    reasoning = true,
    just_chatting = true,
  },
  ["o1-preview"] = {
    name = "openai/o1-preview",
    temperature = nil, -- temperature is not supported
    reasoning = true,
    no_system_prompt = true,
  },
  ["o1-preview-chat"] = {
    name = "openai/o1-preview",
    temperature = nil, -- temperature is not supported
    reasoning = true,
    no_system_prompt = true,
    just_chatting = true
  },
  ["gpt-4o"] = {
    name = "openai/gpt-4o",
    max_tokens = 16384,
    temperature = 0.6,
  },
  ["gpt-4o-2024-11-20"] = {
    name = "openai/gpt-4o-2024-11-20",
    max_tokens = 16384,
    temperature = 0.6,
  },
  ["gpt-4o-2024-08-06"] = {
    name = "openai/gpt-4o-2024-08-06",
    max_tokens = 16384,
    temperature = 0.6,
  },
  ["gpt-4o-2024-05-13"] = {
    name = "openai/gpt-4o-2024-05-13",
    max_tokens = 4096,
    temperature = 0.6,
  },
  ["gpt-4o-mini"] = {
    name = "openai/gpt-4o-mini",
    max_tokens = 16384,
    temperature = 0.3,
  },
  ["gemini-2.5-pro"] = {
    name = "gemini/gemini-2.5-pro-preview-03-25",
    max_tokens = 65536,
    top_k = 64,
    temperature = 0.6,
  },
  ["gemini-2.5-pro-exp"] = {
    name = "gemini/gemini-2.5-pro-exp-03-25",
    max_tokens = 65536,
    top_k = 64,
    temperature = 0.6,
  },
  ["gemini-2.0-flash"] = {
    name = "gemini/gemini-2.0-flash",
    max_tokens = 8192,
    top_k = 40,
    temperature = 0.6,
  },
  ["gemini-2.0-flash-thinking-chat"] = {
    name = "gemini/gemini-2.0-flash-thinking-exp-01-21",
    max_tokens = 65536,
    top_k = 64,
    temperature = 0.7,
    reasoning = true,
    just_chatting = true
  },
  ["gemini-2.0-flash-exp"] = {
    name = "gemini/gemini-2.0-flash-exp",
    max_tokens = 8192,
    top_k = 40,
    temperature = 0.6,
  },
  ["gemini-2.0-flash-lite"] = {
    name = "gemini/gemini-2.0-flash-lite",
    max_tokens = 8192,
    top_k = 40,
    temperature = 0.6,
  },
  ["deepseek-r1-distill-llama-70b"] = {
    name = "groq/deepseek-r1-distill-llama-70b",
    max_tokens = 32768,
    temperature = 0.6,
    reasoning = true,
    no_system_prompt = true,
  }
}
