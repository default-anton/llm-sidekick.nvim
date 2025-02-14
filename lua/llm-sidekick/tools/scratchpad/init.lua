local chat = require("llm-sidekick.chat")

local spec = {
  name = "scratchpad",
  description = [[
A tool for Zir to organize thoughts, plan steps, and make notes during the conversation.
This is an internal thinking and planning space that helps structure the problem-solving process.

CRITICAL REQUIREMENTS:
- `title`: A brief description of what you're thinking about or planning
- `content`: The actual notes, thoughts, or planning content]],
  input_schema = {
    type = "object",
    properties = {
      title = {
        type = "string"
      },
      content = {
        type = "string"
      }
    },
    required = {
      "title",
      "content"
    }
  }
}

local json_props = [[{
  "title": { "type": "string" },
  "content": { "type": "string" }
}]]

return {
  spec = spec,
  json_props = json_props,
  show_diagnostics = function(_) return false end,
  is_auto_acceptable = function(_)
    return true -- Scratchpad is always auto-acceptable as it's an internal tool
  end,
  -- Initialize the scratchpad display
  start = function(tool_call, opts)
    chat.paste_at_end("📝 **Thinking: ", opts.buffer)
    -- Store the starting line number for later updates
    tool_call.state.title_line = vim.api.nvim_buf_line_count(opts.buffer)

    chat.paste_at_end("**\n```markdown\n", opts.buffer)
    tool_call.state.content_start_line = vim.api.nvim_buf_line_count(opts.buffer)
  end,
  -- Handle incremental updates for streaming title and content
  delta = function(tool_call, opts)
    tool_call.parameters.title = vim.trim(tool_call.parameters.title or "")

    local title_written = tool_call.state.title_written or 0
    local content_written = tool_call.state.content_written or 0

    if tool_call.parameters.title and title_written < #tool_call.parameters.title then
      vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.title_line - 1, tool_call.state.title_line, false,
        { string.format("📝 **Thinking: %s**", tool_call.parameters.title) })
      tool_call.state.title_written = #tool_call.parameters.title
    end

    if tool_call.parameters.content and content_written < #tool_call.parameters.content then
      chat.paste_at_end(tool_call.parameters.content:sub(content_written + 1), opts.buffer)
      tool_call.state.content_written = #tool_call.parameters.content
    end
  end,
  -- Finish the scratchpad display
  stop = function(tool_call, opts)
    if #tool_call.parameters.content > 0 then
      chat.paste_at_end("\n```", opts.buffer)
    else
      chat.paste_at_end("```", opts.buffer)
    end
  end,
  run = function()
    return true
  end
}
