return {
  ["deepseek-chat"] = {
    max_tokens = 8192,
    temperature = {
      coding = 0.0,
      chat = 1.3, -- https://api-docs.deepseek.com/quick_start/parameter_settings
    }
  },
  ["claude-3-5-sonnet-latest"] = {
    max_tokens = 8192,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    }
  },
  ["claude-3-5-haiku-latest"] = {
    max_tokens = 8192,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    }
  },
  ["anthropic.claude-3-5-sonnet-20241022-v2:0"] = {
    max_tokens = 8192,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    }
  },
  ["anthropic.claude-3-5-sonnet-20240620-v1:0"] = {
    max_tokens = 4096,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    }
  },
  ["anthropic.claude-3-5-haiku-20241022-v1:0"] = {
    max_tokens = 8192,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    }
  },
  ["anthropic.claude-3-haiku-20240307-v1:0"] = {
    max_tokens = 4096,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    }
  },
  ["o1"] = {
    max_tokens = 100000,
    temperature = {
      coding = 0.0,
      chat = 0.0,
    },
    reasoning = true,
  },
  ["o1-mini"] = {
    max_tokens = 65536,
    temperature = {
      coding = 0.0,
      chat = 0.0,
    },
    reasoning = true,
  },
  ["o1-preview"] = {
    max_tokens = 32768,
    temperature = {
      coding = 0.0,
      chat = 0.0,
    },
    reasoning = true,
  },
  ["gpt-4o"] = {
    max_tokens = 16384,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    },
  },
  ["gpt-4o-2024-11-20"] = {
    max_tokens = 16384,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    },
  },
  ["gpt-4o-2024-08-06"] = {
    max_tokens = 16384,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    },
  },
  ["gpt-4o-2024-05-13"] = {
    max_tokens = 4096,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    },
  },
  ["gpt-4o-mini"] = {
    max_tokens = 16384,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    },
  },
  ["gemini-exp-1206"] = {
    max_tokens = 8192,
    top_k = 64,
    temperature = {
      coding = 0.4,
      chat = 0.7,
    }
  },
  ["gemini-2.0-flash-exp"] = {
    max_tokens = 8192,
    top_k = 40,
    temperature = {
      coding = 0.4,
      chat = 0.7,
    }
  },
  ["gemini-2.0-flash-thinking-exp-1219"] = {
    max_tokens = 8192,
    temperature = {
      coding = 0.5,
      chat = 1.0,
    },
    top_k = 64,
    reasoning = true,
  },
  ["ollama-qwen2.5-coder:1.5b"] = {
    max_tokens = 8192,
    temperature = {
      coding = 0.3,
      chat = 0.7,
    }
  },
}

