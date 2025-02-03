local markdown = require("llm-sidekick.markdown")
local chat = require("llm-sidekick.chat")
local sjson = require("llm-sidekick.sjson")
local signs = require("llm-sidekick.signs")

local description = vim.json.encode([[
Make targeted edits to specific parts of an existing file without overwriting the entire file.

When to Use:
- Small, localized changes like updating a few lines, function implementations, changing variable names, modifying a section of text, etc.
- Targeted improvements where only specific portions of the file’s content needs to be altered.
- Especially useful for long files where much of the file will remain unchanged.

Default to **replace_in_file** for most changes. It's the safer, more precise option that minimizes potential issues.

Technical details:
- Performs literal string replacement (no regex)
- Case-sensitive, exact character-for-character matching
- Replaces only the first match
- Whitespace, newlines, indentation, and comments must match exactly
- For multiple changes to the same file, call this tool multiple times
- Prefer small, targeted replacements over large block changes
- Target the minimum unique code segment needed for each change]])

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

local function find_min_indentation(lines)
  local min_indent = math.huge
  for _, line in ipairs(lines) do
    -- Skip empty lines when calculating min indent
    if line:match("^%s*$") then
      goto continue
    end
    local indent = vim.fn.strdisplaywidth(line:match("^%s*"))
    min_indent = math.min(min_indent, indent)
    ::continue::
  end
  return min_indent
end

local function find_max_indentation(lines)
  local max_indent = 0
  for _, line in ipairs(lines) do
    -- Skip empty lines when calculating max indent
    if line:match("^%s*$") then
      goto continue
    end
    local indent = vim.fn.strdisplaywidth(line:match("^%s*"))
    max_indent = math.max(max_indent, indent)
    ::continue::
  end
  return max_indent
end

local function dedent_lines(lines, min_indent)
  local indent_pattern = "^" .. string.rep(" ", min_indent)
  local dedented_lines = {}
  -- Remove minimum indentation from all lines
  for _, line in ipairs(lines) do
    if line:match("^%s*$") then
      -- Preserve empty lines
      table.insert(dedented_lines, line)
    else
      local dedented = line:gsub(indent_pattern, "")
      table.insert(dedented_lines, dedented)
    end
  end

  return dedented_lines
end

return {
  spec_json = spec_json,
  spec = sjson.decode(spec_json),
  start = function(tool_call, opts)
    chat.paste_at_end("**Path:** `<path will be determined...>", opts.buffer)
    -- Store the starting line number for later updates
    tool_call.state.path_line = vim.api.nvim_buf_line_count(opts.buffer)

    chat.paste_at_end("\n```txt\n<find will be determined...>", opts.buffer)
    tool_call.state.find_start_line = vim.api.nvim_buf_line_count(opts.buffer)

    chat.paste_at_end("\n\n<replace will be determined...>", opts.buffer)
    tool_call.state.replace_start_line = vim.api.nvim_buf_line_count(opts.buffer)

    chat.paste_at_end("\n```", opts.buffer)
  end,
  delta = function(tool_call, opts)
    local path_written = tool_call.state.path_written or 0
    local find_written = tool_call.state.find_written or 0
    local replace_written = tool_call.state.replace_written or 0

    if tool_call.parameters.path and path_written < #tool_call.parameters.path then
      vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.path_line - 1, tool_call.state.path_line, false,
        { string.format("**Path:** `%s`", tool_call.parameters.path) })
      tool_call.state.path_written = #tool_call.parameters.path

      -- Update the language for syntax highlighting
      local language = markdown.filename_to_language(tool_call.parameters.path)
      vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.find_start_line - 2, tool_call.state.find_start_line - 1,
        false, { "```" .. language })
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

      -- Place signs for the find section
      find_start_line = tool_call.state.find_start_line
      local find_end_line = find_start_line + select(2, tool_call.parameters.find:gsub("\n", ""))
      local sign_group = string.format("%s-replace_in_file-find", tool_call.id)
      signs.clear(opts.buffer, sign_group)
      signs.place(opts.buffer, sign_group, find_start_line, find_end_line, "llm_sidekick_red")
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

      -- Place signs for both find and replace sections
      replace_start_line = tool_call.state.replace_start_line
      if find_written > 0 then
        replace_start_line = replace_start_line + select(2, tool_call.parameters.find:gsub("\n", ""))
      end
      local replace_end_line = replace_start_line + select(2, tool_call.parameters.replace:gsub("\n", ""))
      local sign_group = string.format("%s-replace_in_file-replace", tool_call.id)
      signs.clear(opts.buffer, sign_group)
      signs.place(opts.buffer, sign_group, replace_start_line, replace_end_line, "llm_sidekick_green")
    end
  end,
  run = function(tool_call, opts)
    local path = tool_call.parameters.path
    local replace = tool_call.parameters.replace
    local buf = vim.fn.bufnr(path)
    if buf == -1 then
      buf = vim.fn.bufadd(path)
      if buf == 0 then
        error(string.format("Failed to open file: %s", path))
      end
    end
    vim.fn.bufload(buf)
    local content_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local content = table.concat(content_lines, "\n")

    -- Find the exact string match
    local original_search = tool_call.parameters.find
    local original_search_lines = vim.split(original_search, "\n")
    local original_search_min_indent = find_min_indentation(original_search_lines)
    local max_indent = find_max_indentation(content_lines)

    local start_pos, end_pos = content:find(original_search, 1, true)
    local adjusted_search = original_search
    local adjusted_search_lines = original_search_lines
    local adjusted_search_min_indent = original_search_min_indent

    -- Try dedenting up to the max indent
    if not start_pos then
      local max_dedent = math.min(original_search_min_indent, max_indent)
      for dedent = 1, max_dedent do
        adjusted_search_lines = dedent_lines(original_search_lines, dedent)
        adjusted_search = table.concat(adjusted_search_lines, "\n")
        adjusted_search_min_indent = find_min_indentation(adjusted_search_lines)
        start_pos, end_pos = content:find(adjusted_search, 1, true)
        if start_pos then
          break
        end
      end
    end

    -- Try indenting up to the max indent
    if not start_pos then
      for indent = 1, max_indent do
        adjusted_search_lines = {}
        for _, line in ipairs(original_search_lines) do
          if line:match("^%s*$") then
            table.insert(adjusted_search_lines, line)
          else
            table.insert(adjusted_search_lines, string.rep(" ", indent) .. line)
          end
        end
        adjusted_search = table.concat(adjusted_search_lines, "\n")
        adjusted_search_min_indent = find_min_indentation(adjusted_search_lines)
        start_pos, end_pos = content:find(adjusted_search, 1, true)
        if start_pos then
          break
        end
      end
    end

    if not start_pos then
      error(string.format("Could not find the exact match in file: %s", path))
    end

    -- match the indentation of the search pattern
    local replace_lines = vim.split(replace, "\n")
    local replace_min_indent = find_min_indentation(replace_lines)
    local indent_diff = adjusted_search_min_indent - replace_min_indent
    if indent_diff ~= 0 then
      if indent_diff > 0 then
        -- Add indentation to match original
        for i, line in ipairs(replace_lines) do
          replace_lines[i] = string.rep(" ", indent_diff) .. line
        end
      else
        -- Remove excess indentation
        local remove_spaces = -indent_diff
        local indent_pattern = "^" .. string.rep(" ", remove_spaces)
        for i, line in ipairs(replace_lines) do
          replace_lines[i] = line:gsub(indent_pattern, "", 1)
        end
      end
      replace = table.concat(replace_lines, "\n")
    end

    -- Perform the substitution
    local modified_content = content:sub(1, start_pos - 1) .. replace .. content:sub(end_pos + 1)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(modified_content, "\n"))
    local ok, err = pcall(function()
      vim.api.nvim_buf_call(buf, function()
        vim.cmd('write')
      end)
    end)

    if not ok then
      error(string.format("Failed to write to file: %s", err))
    end

    -- Refresh any open windows displaying this file
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local win_buf = vim.api.nvim_win_get_buf(win)
      if vim.api.nvim_buf_get_name(win_buf) == path then
        vim.api.nvim_win_call(win, function()
          vim.cmd('checktime')
        end)
      end
    end

    return true
  end,
}
