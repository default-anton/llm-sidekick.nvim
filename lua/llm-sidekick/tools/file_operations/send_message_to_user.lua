local chat = require("llm-sidekick.chat")
local sjson = require("llm-sidekick.sjson")

local description = vim.json.encode([[
Allows direct communication with the user through messages.

CRITICAL REQUIREMENTS:
- `message`: The text message to display to the user.]])

local spec_json = [[{
  "name": "send_message_to_user",
  "description": ]] .. description .. [[,
  "input_schema": {
    "type": "object",
    "properties": {
      "message": {
        "type": "string"
      }
    },
    "required": [
      "message"
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
