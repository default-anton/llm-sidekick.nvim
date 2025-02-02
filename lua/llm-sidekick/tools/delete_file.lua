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
  start = function(tool_call, opts)
    chat.paste_at_end("\n\n**Path:**\n```\n<path will be determined...>\n```\n**Delete:**\n```\nN/A\n```\n", opts.buffer)
    -- Store the line number where path will be updated
    local lines = vim.api.nvim_buf_line_count(opts.buffer)
    tool_call.state.path_line = lines - 6
  end,
  delta = function(tool_call, opts)
    local path_written = tool_call.state.path_written or 0

    if tool_call.parameters.path and path_written < #tool_call.parameters.path then
      vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.path_line - 1, tool_call.state.path_line, false,
        { tool_call.parameters.path })
      tool_call.state.path_written = #tool_call.parameters.path
    end
  end,
  stop = function(_, opts)
    -- Nothing additional needed for stop since format is already complete
  end,
  callback = function(tool)
    -- tool.input
  end
}
