local M = require('llm-sidekick.init')

describe("M.parse_prompt", function()
  -- Table to store original functions
  local originals = {}

  before_each(function()
    -- Mock vim.notify
    originals.vim_notify = vim.notify
    vim.notify = function(msg, level, opts)
      print("Mocked vim.notify called with message:", msg)
    end
  end)

  after_each(function()
    -- Restore vim.notify
    if originals.vim_notify then
      vim.notify = originals.vim_notify
    end
  end)

  it("parses settings correctly", function()
    local prompt = [[
MAX_TOKENS: 4096
TEMPERATURE: 0.5
MODEL: anthropic.claude-3-5-sonnet-20241022-v2:0
]]

    local options = M.parse_prompt(prompt)

    assert.are.same({
      messages = {},
      settings = {
        model = "anthropic.claude-3-5-sonnet-20241022-v2:0",
        max_tokens = 4096,
        stream = true,
        temperature = 0.5,
      },
    }, options)
  end)

  it("parses user messages", function()
    local prompt = [[
SYSTEM: System message.


USER: Tell me a story.

It should be about a brave knight.
ASSISTANT: Once upon a time...
]]

    local options = M.parse_prompt(prompt)

    assert.are.same({
      { role = "system",    content = "System message." },
      { role = "user",      content = "Tell me a story.\n\nIt should be about a brave knight." },
      { role = "assistant", content = "Once upon a time..." },
    }, options.messages)
  end)
end)
