local markdown = require("llm-sidekick.markdown")
local chat = require("llm-sidekick.chat")
local sjson = require("llm-sidekick.sjson")

local description = vim.json.encode([[
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
- Won't work on binary files]])

local spec_json = [[{
  "name": "replace_in_file",
  "description": ]] .. description .. [[,
  "input_schema": {
    "type": "object",
    "properties": {
      "path": {
        "type": "string",
        "description": "Path to target file. Accepts relative (from CWD) or absolute paths. Use forward slashes even on Windows. Examples: 'docs/report.txt', '/home/user/docs/report.txt', 'C:/Users/name/file.txt'"
      },
      "find": {
        "type": "string",
        "description": "Text to find. Must match exactly, including indentation, whitespace, newlines and comments. Case-sensitive, no regex. Even a single space difference in indentation will prevent matching."
      },
      "replace": {
        "type": "string",
        "description": "Replacement text. Can be empty to delete matched text. Literal replacement, no special characters. Must use the same indentation level as the original text to maintain code formatting."
      }
    },
    "required": [
      "path",
      "find",
      "replace"
    ]
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
    local find_written = tool_call.state.find_written or 0
    local replace_written = tool_call.state.replace_written or 0

    if opts.parameters.path and path_written < #opts.parameters.path then
      chat.paste_at_end(opts.parameters.path:sub(path_written + 1), opts.buffer)
      tool_call.state.path_written = #opts.parameters.path
    end

    if opts.parameters.find and find_written < #opts.parameters.find then
      if find_written == 0 then
        local language = markdown.filename_to_language(opts.parameters.path)
        chat.paste_at_end(string.format("\n```\n**Find:**\n```%s\n", language), opts.buffer)
      end
      chat.paste_at_end(opts.parameters.find:sub(find_written + 1), opts.buffer)
      tool_call.state.find_written = #opts.parameters.find
    end

    if opts.parameters.replace and replace_written < #opts.parameters.replace then
      if replace_written == 0 then
        local language = markdown.filename_to_language(opts.parameters.path)
        chat.paste_at_end(string.format("\n```\n**Replace:**\n```%s\n", language), opts.buffer)
      end
      chat.paste_at_end(opts.parameters.replace:sub(replace_written + 1), opts.buffer)
      tool_call.state.replace_written = #opts.parameters.replace
    end
  end,
  stop = function(_, opts)
    chat.paste_at_end("\n```\n", opts.buffer)
  end,
  callback = function(tool)
    -- tool.parameters
  end,
}
