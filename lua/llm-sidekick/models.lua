return {
  ["deepseek-chat"] = {
    name = "deepseek/deepseek-chat",
    max_tokens = 8192,
    temperature = {
      coding = 0.0,
      chat = 1.3, -- https://api-docs.deepseek.com/quick_start/parameter_settings
    }
  },
  ["deepseek-reasoner"] = {
    name = "deepseek/deepseek-reasoner",
    max_tokens = 8192,
    temperature = {
      coding = 0.6,
      chat = 0.6,
    },
    no_system_prompt = true,
    reasoning = true,
  },
  ["deepseek-r1-distill-llama-70b"] = {
    name = "groq/deepseek-r1-distill-llama-70b",
    temperature = {
      coding = 0.6,
      chat = 0.6,
    },
    no_system_prompt = true,
    reasoning = true,
  },
  ["claude-3-5-sonnet-latest"] = {
    name = "anthropic/claude-3-5-sonnet-latest",
    max_tokens = 8192,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    }
  },
  ["claude-3-5-haiku-latest"] = {
    name = "anthropic/claude-3-5-haiku-latest",
    max_tokens = 8192,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    }
  },
  ["anthropic.claude-3-5-sonnet-20241022-v2:0"] = {
    name = "bedrock/anthropic.claude-3-5-sonnet-20241022-v2:0",
    max_tokens = 8192,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    }
  },
  ["anthropic.claude-3-5-sonnet-20240620-v1:0"] = {
    name = "bedrock/anthropic.claude-3-5-sonnet-20240620-v1:0",
    max_tokens = 4096,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    }
  },
  ["anthropic.claude-3-5-haiku-20241022-v1:0"] = {
    name = "bedrock/anthropic.claude-3-5-haiku-20241022-v1:0",
    max_tokens = 8192,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    }
  },
  ["anthropic.claude-3-haiku-20240307-v1:0"] = {
    name = "bedrock/anthropic.claude-3-haiku-20240307-v1:0",
    max_tokens = 4096,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    }
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
  ["o1-mini"] = {
    name = "openai/o1-mini",
    temperature = nil, -- temperature is not supported
    reasoning = true,
    no_system_prompt = true,
  },
  ["o1-preview"] = {
    name = "openai/o1-preview",
    temperature = nil, -- temperature is not supported
    reasoning = true,
    no_system_prompt = true,
  },
  ["gpt-4o"] = {
    name = "openai/gpt-4o",
    max_tokens = 16384,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    },
  },
  ["gpt-4o-2024-11-20"] = {
    name = "openai/gpt-4o-2024-11-20",
    max_tokens = 16384,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    },
  },
  ["gpt-4o-2024-08-06"] = {
    name = "openai/gpt-4o-2024-08-06",
    max_tokens = 16384,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    },
  },
  ["gpt-4o-2024-05-13"] = {
    name = "openai/gpt-4o-2024-05-13",
    max_tokens = 4096,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    },
  },
  ["gpt-4o-mini"] = {
    name = "openai/gpt-4o-mini",
    max_tokens = 16384,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    },
  },
  ["gemini-2.0-pro"] = {
    name = "gemini/gemini-2.0-pro-exp-02-05",
    max_tokens = 8192,
    top_k = 64,
    temperature = {
      coding = 0.4,
      chat = 0.7,
    }
  },
  ["gemini-2.0-flash"] = {
    name = "gemini/gemini-2.0-flash",
    max_tokens = 8192,
    top_k = 40,
    temperature = {
      coding = 0.4,
      chat = 0.7,
    }
  },
  ["gemini-2.0-flash-thinking"] = {
    name = "gemini/gemini-2.0-flash-thinking-exp-01-21",
    max_tokens = 65536,
    temperature = {
      coding = 0.5,
      chat = 1.0,
    },
    top_k = 64,
    reasoning = true,
  },
  ["gemini-exp-1206"] = {
    name = "gemini/gemini-exp-1206",
    max_tokens = 8192,
    top_k = 64,
    temperature = {
      coding = 0.4,
      chat = 0.7,
    }
  },
}
