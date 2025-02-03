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
  start = function(tool_call, opts)
    chat.paste_at_end("\n\n**Path:**\n```\n<path will be determined...>", opts.buffer)
    -- Store the starting line number for later updates
    tool_call.state.path_line = vim.api.nvim_buf_line_count(opts.buffer)

    chat.paste_at_end("\n```\n**Find:**\n```txt\n<find will be determined...>", opts.buffer)
    tool_call.state.find_start_line = vim.api.nvim_buf_line_count(opts.buffer)

    chat.paste_at_end("\n```\n**Replace:**\n```txt\n<replace will be determined...>", opts.buffer)
    tool_call.state.replace_start_line = vim.api.nvim_buf_line_count(opts.buffer)

    chat.paste_at_end("\n```\n", opts.buffer)
  end,
  delta = function(tool_call, opts)
    local path_written = tool_call.state.path_written or 0
    local find_written = tool_call.state.find_written or 0
    local replace_written = tool_call.state.replace_written or 0

    if tool_call.parameters.path and path_written < #tool_call.parameters.path then
      vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.path_line - 1, tool_call.state.path_line, false,
        { tool_call.parameters.path })
      tool_call.state.path_written = #tool_call.parameters.path

      -- Update the language for syntax highlighting
      local language = markdown.filename_to_language(tool_call.parameters.path)
      vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.find_start_line - 2, tool_call.state.find_start_line - 1,
        false, { "```" .. language })

      local replace_start_line = tool_call.state.replace_start_line

      if find_written > 0 then
        -- Add the number of lines from the find section
        local find_lines = select(2, tool_call.parameters.find:gsub("\n", "")) + 1
        replace_start_line = replace_start_line + find_lines
      end

      vim.api.nvim_buf_set_lines(opts.buffer, replace_start_line - 2, replace_start_line - 1, false,
        { "```" .. language })
    end

    if tool_call.parameters.find and find_written < #tool_call.parameters.find then
      local find_start_line = tool_call.state.find_start_line
      local written = tool_call.parameters.find:sub(1, find_written)

      if #written > 0 then
        -- Add the number of lines already written
        local find_lines = select(2, written:gsub("\n", ""))
        find_start_line = find_start_line + find_lines
      else
        -- Truncate the placeholder line
        vim.api.nvim_buf_set_lines(opts.buffer, find_start_line - 1, find_start_line, false, { "" })
      end

      chat.paste_at_line(tool_call.parameters.find:sub(find_written + 1), find_start_line, opts.buffer)
      tool_call.state.find_written = #tool_call.parameters.find
    end

    if tool_call.parameters.replace and replace_written < #tool_call.parameters.replace then
      local replace_start_line = tool_call.state.replace_start_line

      if find_written > 0 then
        -- Add the number of lines from the find section
        local find_lines = select(2, tool_call.parameters.find:gsub("\n", ""))
        replace_start_line = replace_start_line + find_lines
      end

      local written = tool_call.parameters.replace:sub(1, replace_written)

      if #written > 0 then
        -- Add the number of lines already written
        local find_lines = select(2, written:gsub("\n", ""))
        replace_start_line = replace_start_line + find_lines
      else
        -- Truncate the placeholder line
        vim.api.nvim_buf_set_lines(opts.buffer, replace_start_line - 1, replace_start_line, false, { "" })
      end

      chat.paste_at_line(tool_call.parameters.replace:sub(replace_written + 1), replace_start_line, opts.buffer)
      tool_call.state.replace_written = #tool_call.parameters.replace
    end
  end,
  stop = function(_, opts)
    -- Nothing additional needed for stop since format is already complete
  end,
  callback = function(tool)
    -- tool.parameters
  end,
}
