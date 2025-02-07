local signs = require("llm-sidekick.signs")
local tc = require("llm-sidekick.tools.tool_calls")

local description = [[
Replace sections of content in an existing file. Use this tool to make targeted changes to specific parts of a file.

**FORMAT:**

**Path:** `<path/to/file>`
**Search:**
```<filetype>
<text to search>
```
**Replace:**
```<filetype>
<replacement text>
```

**Critical Requirements**:
- **Path:** The path to the file.  This must be relative to the project root, or it will be rejected.
- **Search:** Include the exact text that needs to be located for modification. This must be an EXACT, CHARACTER-FOR-CHARACTER match of the original text, including all comments, spacing, indentation, and formatting.
- **Replace:** Provide the new text that will replace the found text. Ensure that the replacement maintains the original file's formatting and style.
- Only include the relevant sections of the file necessary for the modification, not the entire file content.
- Use the **Search** section to provide sufficient surrounding context to uniquely identify the location of the change.
- Use triple backticks for enclose the search and replace, and include the filetype.
- The provided `filetype` will be used for syntax highlighting.

**IMPORTANT:** You must include ALL content in the **Search** sections exactly as it appears in the original file, including comments, whitespace, and seemingly irrelevant details. Do not omit or modify any characters.

**Multiple Modifications:**
- For multiple modifications within the same file or across multiple files, repeat the **Path**, **Search**, and **Replace** sections for each change.

**Example:**

**Path:**: `config.yaml`
**Search:**
```yaml
  app_name: My App
```
**Replace:**
```yaml
  app_name: My App
special:
  app_name: My Special App
  enable_new_feature: true
```]]

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

local function find_tool_calls(opts)
  local pattern = "%*%*Path:%*%*%s*`(.-)`\n%*%*Search:%*%*\n```%w-\n(.-)\n```\n%*%*Replace:%*%*\n```%w-\n(.-)\n```"
  local attribute_names = {
    "path",
    "search",
    "replace",
  }
  local tool_calls = tc.find_tool_calls(
    opts.buffer,
    opts.start_search_line,
    opts.end_search_line,
    pattern,
    attribute_names
  )

  return vim.tbl_filter(function(tool_call)
    local abs_path = vim.fn.fnamemodify(tool_call.path, ":p")
    local cwd = vim.fn.getcwd()
    if not vim.startswith(abs_path, cwd) then
      vim.api.nvim_err_writeln(string.format("The file path '%s' must be within the current working directory '%s'",
        abs_path, cwd))

      return false
    end

    return true
  end, tool_calls)
end

local function find_tool_at_cursor(opts)
  local tool_calls = find_tool_calls(opts)

  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

  for _, tool_call in ipairs(tool_calls) do
    if cursor_line >= tool_call.start_line and cursor_line <= tool_call.end_line then
      return tool_call
    end
  end
end

local function error_handler(err)
  return debug.traceback(err, 3)
end

local function apply_tool_call(tool_call)
  local path = vim.trim(tool_call.path or "")
  local replace = tool_call.replace or ""
  local original_search = tool_call.search

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
    -- Unload the buffer if it wasn't open before
    if vim.fn.bufloaded(buf) == 1 and vim.fn.bufwinnr(buf) == -1 then
      vim.cmd('bdelete ' .. buf)
    end
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

  local ok, err = xpcall(function()
    vim.api.nvim_buf_call(buf, function()
      vim.cmd('write')
    end)
  end, error_handler)

  if not ok then
    -- Unload the buffer if it wasn't open before
    if vim.fn.bufloaded(buf) == 1 and vim.fn.bufwinnr(buf) == -1 then
      vim.cmd('bdelete ' .. buf)
    end
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

  -- Unload the buffer if it wasn't open before
  if vim.fn.bufloaded(buf) == 1 and vim.fn.bufwinnr(buf) == -1 then
    vim.cmd('bdelete ' .. buf)
  end
end

local function on_assistant_turn_end(opts)
  local tool_calls = find_tool_calls(opts)

  local sign_group = "llm_sidekick-search_and_replace_in_file"
  signs.clear(opts.buffer, sign_group)

  for _, tool_call in ipairs(tool_calls) do
    signs.place(
      opts.buffer,
      sign_group,
      tool_call.search_start_line,
      tool_call.search_end_line,
      "llm_sidekick_red"
    )
    signs.place(
      opts.buffer,
      sign_group,
      tool_call.replace_start_line,
      tool_call.replace_end_line,
      "llm_sidekick_green"
    )
  end

  return tool_calls
end

return {
  name = "Search and Replace in File",
  diagnostic_name = "Replace",
  description = description,
  on_assistant_turn_end = on_assistant_turn_end,
  on_user_accept = function(opts)
    local tool_call = find_tool_at_cursor(opts)
    if not tool_call then
      return
    end

    local ok, err = xpcall(apply_tool_call, error_handler, tool_call)
    if not ok then
      tool_call.error = string.format("Error applying search_and_replace_in_file to %s: %s", tool_call.path,
        vim.inspect(err))
    end

    return tool_call
  end,
  on_user_accept_all = function(opts)
    local tool_calls = find_tool_calls(opts)

    for _, tool_call in ipairs(tool_calls) do
      local ok, err = xpcall(apply_tool_call, error_handler, tool_call)
      if not ok then
        tool_call.error = string.format("Error applying search_and_replace_in_file to %s: %s", tool_call.path,
          vim.inspect(err))
      end
    end

    return tool_calls
  end,
}
