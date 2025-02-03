return {
  ["deepseek-chat"] = {
    name = "deepseek-chat",
    max_tokens = 8192,
    temperature = {
      coding = 0.0,
      chat = 1.3, -- https://api-docs.deepseek.com/quick_start/parameter_settings
    }
  },
  ["deepseek-reasoner"] = {
    name = "deepseek-reasoner",
    max_tokens = 8192,
    temperature = {
      coding = 0.6,
      chat = 0.6,
    },
    no_system_prompt = true,
    reasoning = true,
  },
  ["groq.deepseek-r1-distill-llama-70b"] = {
    name = "groq.deepseek-r1-distill-llama-70b",
    max_tokens = 15000,
    temperature = {
      coding = 0.6,
      chat = 0.6,
    },
    no_system_prompt = true,
    reasoning = true,
  },
  ["claude-3-5-sonnet-latest"] = {
    name = "claude-3-5-sonnet-latest",
    max_tokens = 8192,
    tools = true,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    }
  },
  ["claude-3-5-haiku-latest"] = {
    name = "claude-3-5-haiku-latest",
    max_tokens = 8192,
    tools = true,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    }
  },
  ["anthropic.claude-3-5-sonnet-20241022-v2:0"] = {
    name = "anthropic.claude-3-5-sonnet-20241022-v2:0",
    max_tokens = 8192,
    tools = true,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    }
  },
  ["anthropic.claude-3-5-sonnet-20240620-v1:0"] = {
    name = "anthropic.claude-3-5-sonnet-20240620-v1:0",
    tools = true,
    max_tokens = 4096,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    }
  },
  ["anthropic.claude-3-5-haiku-20241022-v1:0"] = {
    name = "anthropic.claude-3-5-haiku-20241022-v1:0",
    max_tokens = 8192,
    tools = true,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    }
  },
  ["anthropic.claude-3-haiku-20240307-v1:0"] = {
    name = "anthropic.claude-3-haiku-20240307-v1:0",
    max_tokens = 4096,
    tools = true,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    }
  },
  ["o1-low"] = {
    name = "o1",
    max_tokens = 65536,
    reasoning_effort = "low", -- can be "low", "medium", "high"
    temperature = nil, -- temperature is not supported
    reasoning = true,
    no_system_prompt = true,
  },
  ["o1-medium"] = {
    name = "o1",
    max_tokens = 65536,
    reasoning_effort = "medium", -- can be "low", "medium", "high"
    temperature = nil, -- temperature is not supported
    reasoning = true,
    no_system_prompt = true,
  },
  ["o1-high"] = {
    name = "o1",
    max_tokens = 65536,
    reasoning_effort = "high", -- can be "low", "medium", "high"
    temperature = nil, -- temperature is not supported
    reasoning = true,
    no_system_prompt = true,
  },
  ["o3-mini-low"] = {
    name = "o3-mini",
    max_tokens = 65536,
    reasoning_effort = "low", -- can be "low", "medium", "high"
    temperature = nil, -- temperature is not supported
    reasoning = true,
    tools = true,
    no_system_prompt = true,
  },
  ["o3-mini-medium"] = {
    name = "o3-mini",
    max_tokens = 65536,
    reasoning_effort = "medium", -- can be "low", "medium", "high"
    temperature = nil, -- temperature is not supported
    reasoning = true,
    tools = true,
    no_system_prompt = true,
  },
  ["o3-mini-high"] = {
    name = "o3-mini",
    max_tokens = 65536,
    reasoning_effort = "high", -- can be "low", "medium", "high"
    temperature = nil, -- temperature is not supported
    reasoning = true,
    tools = true,
    no_system_prompt = true,
  },
  ["o1-mini"] = {
    name = "o1-mini",
    max_tokens = 65536,
    temperature = nil, -- temperature is not supported
    reasoning = true,
    no_system_prompt = true,
  },
  ["o1-preview"] = {
    name = "o1-preview",
    max_tokens = 32768,
    temperature = nil, -- temperature is not supported
    reasoning = true,
    no_system_prompt = true,
  },
  ["gpt-4o"] = {
    name = "gpt-4o",
    max_tokens = 16384,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    },
    tools = true,
  },
  ["gpt-4o-2024-11-20"] = {
    name = "gpt-4o-2024-11-20",
    max_tokens = 16384,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    },
    tools = true,
  },
  ["gpt-4o-2024-08-06"] = {
    name = "gpt-4o-2024-08-06",
    max_tokens = 16384,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    },
    tools = true,
  },
  ["gpt-4o-2024-05-13"] = {
    name = "gpt-4o-2024-05-13",
    max_tokens = 4096,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    },
  },
  ["gpt-4o-mini"] = {
    name = "gpt-4o-mini",
    max_tokens = 16384,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    },
  },
  ["gemini-exp-1206"] = {
    name = "gemini-exp-1206",
    max_tokens = 8192,
    top_k = 64,
    temperature = {
      coding = 0.4,
      chat = 0.7,
    }
  },
  ["gemini-2.0-flash-exp"] = {
    name = "gemini-2.0-flash-exp",
    max_tokens = 8192,
    top_k = 40,
    temperature = {
      coding = 0.4,
      chat = 0.7,
    }
  },
  ["gemini-2.0-flash-thinking-exp-01-21"] = {
    name = "gemini-2.0-flash-thinking-exp-01-21",
    max_tokens = 65536,
    temperature = {
      coding = 0.5,
      chat = 1.0,
    },
    top_k = 64,
    reasoning = true,
  },
  ["gemini-2.0-flash-thinking-exp-1219"] = {
    name = "gemini-2.0-flash-thinking-exp-1219",
    max_tokens = 65536,
    temperature = {
      coding = 0.5,
      chat = 1.0,
    },
    top_k = 64,
    reasoning = true,
  },
  ["ollama.qwen2.5-coder:1.5b"] = {
    name = "ollama.qwen2.5-coder:1.5b",
    max_tokens = 8192,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    }
  },
}
