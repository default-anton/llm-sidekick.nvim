local chat = require("llm-sidekick.chat")

local spec = {
  name = "send_message_to_user",
  description = [[
Sends a message directly to the user.

CRITICAL REQUIREMENTS:
- `message`: What you want to say to the user
- `message_type`: The type of message being sent. Must be one of:
  - "question": Requires user input/response
  - "chat": General conversational message or response
  - "alert": Indicates issues requiring attention (includes both errors and warnings)
  - "progress": Updates during longer operations or multi-step tasks, no action required
  - "suggestion": Proactive recommendations and advice that user can choose to act on]],
  input_schema = {
    type = "object",
    properties = {
      message_type = {
        type = "string",
        enum = { "question", "chat", "alert", "progress", "suggestion" },
      },
      message = {
        type = "string",
      },
    },
    required = { "message", "message_type" },
  },
}

local json_props = string.format([[{
  "message_type": %s,
  "message": %s
}]], vim.json.encode(spec.input_schema.properties.message_type), vim.json.encode(spec.input_schema.properties.message))

return {
  spec = spec,
  json_props = json_props,
  is_show_diagnostics = function(_) return false end,
  is_auto_acceptable = function(tool_call)
    return tool_call.parameters.message_type == "chat" or tool_call.parameters.message_type == "progress"
  end,
  delta = function(tool_call, opts)
    tool_call.parameters.message = tool_call.parameters.message or ""
    tool_call.state.message_written = tool_call.state.message_written or 0

    if tool_call.parameters.message and tool_call.state.message_written < #tool_call.parameters.message then
      chat.paste_at_end(tool_call.parameters.message:sub(tool_call.state.message_written + 1), opts.buffer)
      tool_call.state.message_written = #tool_call.parameters.message
    end
  end,
  run = function()
    return true
  end
}
