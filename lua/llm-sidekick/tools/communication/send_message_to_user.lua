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
  - "suggestion": Proactive recommendations and advice that user can choose to act on
- `conversation_control`: Controls the flow of conversation. Must be one of:
  - "expect_input": You are waiting for user input
  - "continue": You have more to process or say
  - "done": You have completed the task and are ready for new instructions]],
  input_schema = {
    type = "object",
    properties = {
      message = {
        type = "string",
      },
      message_type = {
        type = "string",
        enum = { "question", "chat", "alert", "progress", "suggestion" },
      },
      conversation_control = {
        type = "string",
        enum = { "expect_input", "continue", "done" },
      },
    },
    required = { "message", "message_type", "conversation_control" },
  },
}

return {
  spec = spec,
  delta = function(tool_call, opts)
    tool_call.parameters.message = tool_call.parameters.message or ""
    tool_call.state.message_written = tool_call.state.message_written or 0

    if tool_call.parameters.message and tool_call.state.message_written < #tool_call.parameters.message then
      chat.paste_at_end(tool_call.parameters.message:sub(tool_call.state.message_written + 1), opts.buffer)
      tool_call.state.message_written = #tool_call.parameters.message
    end
  end
}
