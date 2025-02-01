local markdown = require("llm-sidekick.markdown")
local chat = require("llm-sidekick.chat")

local spec = {
  name = "replace_in_file",
  description = [[
      Replaces specific content in a file with exact matching. Use this to make precise modifications to existing files.

      Technical details:
      - Performs literal string replacement (no regex)
      - Case-sensitive, exact character-for-character matching
      - Works with any text file encoding
      - Replaces only the first match
      - Whitespace, newlines, indentation, and comments must match exactly
      - For multiple changes to the same file, call this tool multiple times
      - Prefer small, targeted replacements over large block changes
      - Target the minimum unique code segment needed for each change
      - Direct file modification - make sure you mean it
      - Won't work on binary files
    ]],
  input_schema = {
    type = "object",
    properties = {
      path = {
        type = "string",
        description =
        "Path to target file. Accepts relative (from CWD) or absolute paths. Use forward slashes even on Windows. Examples: 'docs/report.txt', '/home/user/docs/report.txt', 'C:/Users/name/file.txt'"
      },
      find = {
        type = "string",
        description =
        "Text to find. Must match exactly, including indentation, whitespace, newlines and comments. Case-sensitive, no regex. Even a single space difference in indentation will prevent matching."
      },
      replace = {
        type = "string",
        description =
        "Replacement text. Can be empty to delete matched text. Literal replacement, no special characters. Must use the same indentation level as the original text to maintain code formatting."
      }
    },
    required = { "path", "find", "replace" }
  }
}

return {
  spec = spec,
  start = function(_)
    chat.paste_at_end("\n\n**Path:**\n```\n")
  end,
  delta = function(tool_call)
    local path_written = tool_call.state.path_written or 0
    local find_written = tool_call.state.find_written or 0
    local replace_written = tool_call.state.replace_written or 0

    if tool_call.input.path and path_written < #tool_call.input.path then
      chat.paste_at_end(tool_call.input.path:sub(path_written + 1))
      tool_call.state.path_written = #tool_call.input.path
    end

    if tool_call.input.find and find_written < #tool_call.input.find then
      if find_written == 0 then
        chat.paste_at_end("\n```\n**Find:**\n```\n")
      end
      chat.paste_at_end(tool_call.input.find:sub(find_written + 1))
      tool_call.state.find_written = #tool_call.input.find
    end

    if tool_call.input.replace and replace_written < #tool_call.input.replace then
      if replace_written == 0 then
        chat.paste_at_end("\n```\n**Replace:**\n```\n")
      end
      chat.paste_at_end(tool_call.input.replace:sub(replace_written + 1))
      tool_call.state.replace_written = #tool_call.input.replace
    end
  end,
  stop = function(_)
    chat.paste_at_end("\n```\n")
  end,
  callback = function(tool)
    -- tool.input
  end,
}
