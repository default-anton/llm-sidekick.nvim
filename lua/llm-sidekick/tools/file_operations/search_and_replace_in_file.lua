local signs = require("llm-sidekick.signs")

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
- **Search:** Include the exact text that needs to be located for modification. This must be an EXACT, CHARACTER-FOR-CHARACTER match of the original text, including all comments, spacing, indentation, and formatting.
- **Replace:** Provide the new text that will replace the found text. Ensure that the replacement maintains the original file's formatting and style.
- Only include the relevant sections of the file necessary for the modification, not the entire file content.
- Use the **Search** section to provide sufficient surrounding context to uniquely identify the location of the change.
- Use triple backticks for content sections to preserve formatting and readability.

**IMPORTANT:** You must include ALL content in the **Search** sections exactly as it appears in the original file, including comments, whitespace, and seemingly irrelevant details. Do not omit or modify any characters.

**Multiple Modifications:**
- For multiple modifications within the same file or across multiple files, repeat the **Path**, **Search**, and **Replace** sections for each change.

**Example:**

For clarity, here's an example demonstrating how to use the format:

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

local find_modifications = function(text, pattern, true_start_line)
  local found_modifications = {}
  local start = 1

  while true do
    local start_pos, end_pos, raw_body, path, search, replace = text:find(pattern, start)
    if not start_pos then
      break
    end

    local start_line = start_pos == 1 and 1 or select(2, text:sub(1, start_pos):gsub("\n", ""))
    local search_start_pos = raw_body:find(search, 1, true)
    local search_start_line = start_line + select(2, raw_body:sub(1, search_start_pos):gsub("\n", ""))
    local search_end_line = search_start_line + select(2, search:gsub("\n", ""))
    local replace_start_pos = raw_body:find(replace, 1, true)
    local replace_start_line = start_line + select(2, raw_body:sub(1, replace_start_pos):gsub("\n", ""))
    local replace_end_line = replace_start_line + select(2, replace:gsub("\n", ""))
    local end_line = start_line + select(2, raw_body:gsub("\n", ""))

    local abs_path = vim.fn.fnamemodify(path, ":p")
    local cwd = vim.fn.getcwd()
    if not vim.startswith(abs_path, cwd) then
      vim.api.nvim_err_writeln(string.format("The file path '%s' must be within the current working directory '%s'",
        abs_path, cwd))
    else
      table.insert(found_modifications, {
        type = "update",
        path = path,
        search = search,
        search_start_line = true_start_line + search_start_line,
        search_end_line = true_start_line + search_end_line,
        replace = replace,
        replace_start_line = true_start_line + replace_start_line,
        replace_end_line = true_start_line + replace_end_line,
        start_line = true_start_line + start_line,
        end_line = true_start_line + end_line,
        raw_body = raw_body,
      })
    end

    start = end_pos + 1
  end

  return found_modifications
end

local function find_tools(opts)
  local buffer = opts.buffer
  local start_search_line = opts.start_search_line
  local end_search_line = opts.end_search_line

  local buffer_lines = vim.api.nvim_buf_get_lines(buffer, start_search_line - 1, end_search_line, false)
  buffer_lines[1] = buffer_lines[1]:gsub("^ASSISTANT:%s*", "")
  local content = table.concat(buffer_lines, "\n")

  local default_modify_pattern =
  "(%*%*Path:%*%*%s*`(.-)`\n%*%*Search:%*%*\n```%w-\n(.-)\n```\n%*%*Replace:%*%*\n```%w-\n(.-)\n```)"
  local sonnet_modify_pattern = "(@([^\n]+)\n<search>\n?(.-)\n?</search>\n<replace>\n?(.-)\n?</replace>)"
  local gemini_modify_pattern =
  "(%*%*Path:%*%*\n```%w-\n([^\n]+)\n```\n%*%*Find:%*%*\n```%w-\n(.-)\n```\n%*%*Replace:%*%*\n```%w-\n(.-)\n```)"

  local modifications = find_modifications(content, default_modify_pattern, start_search_line)
  vim.list_extend(modifications, find_modifications(content, sonnet_modify_pattern, start_search_line))
  vim.list_extend(modifications, find_modifications(content, gemini_modify_pattern, start_search_line))

  return modifications
end

local function find_tool_at_cursor(opts)
  local modifications = find_tools(opts)

  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

  for _, modification in ipairs(modifications) do
    if cursor_line >= modification.start_line and cursor_line <= modification.end_line then
      return modification
    end
  end
end

local function error_handler(err)
  vim.notify("Error writing to file: " .. vim.inspect(err), vim.log.levels.ERROR)
  vim.print(debug.traceback())
  return err
end

local function apply_modification(modification)
  local path = vim.trim(modification.path or "")
  local replace = modification.replace or ""
  local original_search = modification.search

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
  local modifications = find_tools(opts)

  local sign_group = "llm_sidekick-search_and_replace_in_file"
  signs.clear(opts.buffer, sign_group)

  for _, modification in ipairs(modifications) do
    signs.place(
      opts.buffer,
      sign_group,
      modification.search_start_line,
      modification.search_end_line,
      "llm_sidekick_red"
    )
    signs.place(
      opts.buffer,
      sign_group,
      modification.replace_start_line,
      modification.replace_end_line,
      "llm_sidekick_green"
    )
  end

  return modifications
end

return {
  name = "Search and Replace in File",
  diagnostic_name = "Replace",
  description = description,
  on_assistant_turn_end = on_assistant_turn_end,
  on_user_accept = function(opts)
    local modification = find_tool_at_cursor(opts)
    if not modification then
      return
    end

    local ok, err = xpcall(apply_modification, error_handler, modification)
    if not ok then
      modification.error = string.format("Error applying modification to %s: %s", modification.path, vim.inspect(err))
    end

    return modification
  end,
  on_user_accept_all = function(opts)
    local modifications = find_tools(opts)

    for _, modification in ipairs(modifications) do
      local ok, err = xpcall(apply_modification, error_handler, modification)
      if not ok then
        modification.error = string.format("Error applying modification to %s: %s", modification.path, vim.inspect(err))
      end
    end

    return modifications
  end,
}
