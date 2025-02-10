local chat = require("llm-sidekick.chat")
local sjson = require("llm-sidekick.sjson")

local description = vim.json.encode([[
Sends a message directly to the user.

CRITICAL REQUIREMENTS:
- `message`: What you want to say to the user
- `message_type`: The type of message being sent. Must be one of:
  - "question": Requires user input/response
  - "info": General informational message, no action required
  - "all_tasks_done": Indicates all tasks are finished, nothing more to do
  - "alert": Indicates issues requiring attention (includes both errors and warnings)
  - "progress": Updates during longer operations or multi-step tasks, no action required
  - "suggestion": Proactive recommendations and advice that user can choose to act on]])

local spec_json = [[{
  "name": "send_message_to_user",
  "description": ]] .. description .. [[,
  "input_schema": {
    "type": "object",
    "properties": {
      "message": {
        "type": "string"
      },
      "message_type": {
        "type": "string",
        "enum": ["question", "info", "all_tasks_done", "alert", "progress", "suggestion"]
      },
    },
    "required": [
      "message", "message_type"
    ]
  }
}]]

return {
  spec_json = spec_json,
  spec = sjson.decode(spec_json),
  delta = function(tool_call, opts)
    tool_call.parameters.message = tool_call.parameters.message or ""
    tool_call.state.message_written = tool_call.state.message_written or 0

    if tool_call.parameters.message and tool_call.state.message_written < #tool_call.parameters.message then
      chat.paste_at_end(tool_call.parameters.message:sub(tool_call.state.message_written + 1), opts.buffer)
      tool_call.state.message_written = #tool_call.parameters.message
    end
  end
}
