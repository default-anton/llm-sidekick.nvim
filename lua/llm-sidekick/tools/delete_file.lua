local chat = require("llm-sidekick.chat")

local spec = {
  name = "delete_file",
  description = [[
      Deletes the file at the given path.

      Technical details:
      - Supports both relative and absolute file paths.
      - Will not delete directories, only files.
    ]],
  input_schema = {
    type = "object",
    properties = {
      path = {
        type = "string",
        description =
        "Path to the file to delete. Accepts relative (from CWD) or absolute paths. Use forward slashes even on Windows. Examples: 'docs/old_report.txt', '/home/user/temp_files/outdated.txt', 'C:/Users/name/trash/temp.log'"
      }
    },
    required = { "path" }
  }
}

return {
  spec = spec,
  start = function(_)
    chat.paste_at_end("\n\n**Path:**\n```\n")
  end,
  delta = function(tool_call)
    local path_written = tool_call.state.path_written or 0

    if tool_call.input.path and path_written < #tool_call.input.path then
      chat.paste_at_end(tool_call.input.path:sub(path_written + 1))
      tool_call.state.path_written = #tool_call.input.path
    end
  end,
  stop = function(_)
    chat.paste_at_end("\n```\n**Delete:**\n```\nN/A\n```\n")
  end,
  callback = function(tool)
    -- tool.input
  end
}
