local sjson = require("llm-sidekick.sjson")
local chat = require("llm-sidekick.chat")

local description = vim.json.encode([[
Deletes the file at the given path.

Technical details:
- Supports both relative and absolute file paths.
- Will not delete directories, only files.]])

local spec_json = [[{
  "name": "delete_file",
  "description": ]] .. description .. [[,
  "input_schema": {
    "type": "object",
    "properties": {
      "path": {
        "type": "string",
        "description": "Path to the file to delete. Accepts relative (from CWD) or absolute paths. Use forward slashes even on Windows. Examples: 'docs/old_report.txt', '/home/user/temp_files/outdated.txt', 'C:/Users/name/trash/temp.log'"
      }
    },
    "required": [ "path" ]
  }
}]]

return {
  spec_json = spec_json,
  spec = sjson.decode(spec_json),
  start = function(_, opts)
    chat.paste_at_end("\n\n**Path:**\n```\n", opts.buffer)
  end,
  delta = function(tool_call, opts)
    local path_written = tool_call.state.path_written or 0

    if opts.parameters.path and path_written < #opts.parameters.path then
      chat.paste_at_end(opts.parameters.path:sub(path_written + 1), opts.buffer)
      tool_call.state.path_written = #opts.parameters.path
    end
  end,
  stop = function(_, opts)
    chat.paste_at_end("\n```\n**Delete:**\n```\nN/A\n```\n", opts.buffer)
  end,
  callback = function(tool)
    -- tool.input
  end
}
