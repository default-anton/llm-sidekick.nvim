local markdown = require("llm-sidekick.markdown")
local chat = require("llm-sidekick.chat")
local signs = require("llm-sidekick.signs")

local spec = {
  name = "edit_file_section",
  description = [[
Makes precise, targeted changes to specific parts of a file. Default choice for most file modifications.

CRITICAL REQUIREMENTS:
- `path`: The path to the file. This must be relative to the current working directory, or it will be rejected.
- `search`: Include the exact text that needs to be located for modification. This must be an EXACT, CHARACTER-FOR-CHARACTER match of the original text, including all comments, spacing, indentation, and seemingly irrelevant details. Do not omit or modify any characters.
- `replace`: Provide the new text that will replace the found text. Ensure that the replacement maintains the original file's formatting and style.
- Each `search` must be unique enough to match only the intended section.

Example: Requesting to make targeted edits to a file

path: src/components/App.tsx

search:
function onSubmit() {
  save();
}

replace:

---

path: src/components/App.tsx

search:
return (
  <div>

replace:
function onSubmit() {
  save();
}

return (
  <div>]],
  input_schema = {
    type = "object",
    properties = {
      path = { type = "string" },
      search = { type = "string" },
      replace = { type = "string" },
    },
    required = { "path", "search", "replace" },
  },
}

local json_props = [[{
  "path": { "type": "string" },
  "search": { "type": "string" },
  "replace": { "type": "string" }
}]]

local function find_min_indentation(lines)
  local min_indent = math.huge
  -- If lines is empty, return 0 instead of math.huge
  if #lines == 0 then
    return 0
  end

  for _, line in ipairs(lines) do
    -- Skip empty lines when calculating min indent
    if line:match("^%s*$") then
      goto continue
    end
    local indent = vim.fn.strdisplaywidth(line:match("^%s*"))
    min_indent = math.min(min_indent, indent)
    ::continue::
  end

  -- If all lines were empty or there were no lines with content, return 0
  if min_indent == math.huge then
    return 0
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

-- Helper function to adjust indentation of replace lines to match search indentation
local function adjust_replace_indentation(replace_lines, replace_min_indent, target_indent)
  local indent_diff = target_indent - replace_min_indent
  local adjusted_lines = {}

  if indent_diff ~= 0 then
    if indent_diff > 0 then
      -- Add indentation to match original
      for _, line in ipairs(replace_lines) do
        if line:match("^%s*$") then
          table.insert(adjusted_lines, line)
        else
          table.insert(adjusted_lines, string.rep(" ", indent_diff) .. line)
        end
      end
    else
      -- Remove excess indentation
      local remove_spaces = -indent_diff
      local indent_pattern = "^" .. string.rep(" ", remove_spaces)
      for _, line in ipairs(replace_lines) do
        if line:match("^%s*$") then
          table.insert(adjusted_lines, line)
        else
          -- Capture only the first return value from gsub (the modified string)
          local modified_line = line:gsub(indent_pattern, "", 1)
          table.insert(adjusted_lines, modified_line)
        end
      end
    end
  else
    -- No adjustment needed
    adjusted_lines = replace_lines
  end

  return adjusted_lines
end

-- Helper function to find match in content lines
local function find_match_in_lines(content_lines, search_lines)
  if #search_lines > #content_lines then
    return nil
  end

  for i = 1, #content_lines - #search_lines + 1 do
    local matched = true
    for j = 1, #search_lines do
      -- Handle empty lines specially - they might have different whitespace
      if search_lines[j]:match("^%s*$") and content_lines[i + j - 1]:match("^%s*$") then
        -- Both are empty lines (possibly with whitespace), consider them matching
      elseif content_lines[i + j - 1] ~= search_lines[j] then
        matched = false
        break
      end
    end
    if matched then
      return i, i + #search_lines - 1
    end
  end

  return nil
end

-- Helper function to try different indentation patterns
local function find_match_with_indentation_variations(content_lines, search_lines, max_indent)
  local original_search_min_indent = find_min_indentation(search_lines)

  -- First try exact match
  local start_line, end_line = find_match_in_lines(content_lines, search_lines)
  if start_line then
    return start_line, end_line, search_lines
  end

  -- Try all possible dedent levels at once
  -- This is important for cases where search has more indentation than file content
  local max_dedent = original_search_min_indent
  for dedent = 1, max_dedent do
    local adjusted_search_lines = dedent_lines(search_lines, dedent)
    start_line, end_line = find_match_in_lines(content_lines, adjusted_search_lines)
    if start_line then
      return start_line, end_line, adjusted_search_lines
    end
  end

  -- Try indenting
  for indent = 1, max_indent do
    local adjusted_search_lines = {}
    for _, line in ipairs(search_lines) do
      if line:match("^%s*$") then
        table.insert(adjusted_search_lines, line)
      else
        table.insert(adjusted_search_lines, string.rep(" ", indent) .. line)
      end
    end
    start_line, end_line = find_match_in_lines(content_lines, adjusted_search_lines)
    if start_line then
      return start_line, end_line, adjusted_search_lines
    end
  end

  -- If still not found, try more aggressive matching by normalizing whitespace
  for i = 1, #content_lines - #search_lines + 1 do
    local matched = true
    for j = 1, #search_lines do
      local content_line_normalized = content_lines[i + j - 1]:gsub("^%s+", "")
      local search_line_normalized = search_lines[j]:gsub("^%s+", "")

      if content_line_normalized ~= search_line_normalized then
        matched = false
        break
      end
    end
    if matched then
      -- Create a version of search_lines that matches the actual indentation
      local matched_search_lines = {}
      for j = 1, #search_lines do
        matched_search_lines[j] = content_lines[i + j - 1]
      end
      return i, i + #search_lines - 1, matched_search_lines
    end
  end

  return nil, nil, nil
end

return {
  spec = spec,
  json_props = json_props,
  is_show_diagnostics = function(_) return true end,
  is_auto_acceptable = function(_)
    return require("llm-sidekick.settings").auto_accept_file_operations()
  end,
  start = function(tool_call, opts)
    chat.paste_at_end("**Path:**", opts.buffer)
    -- Store the starting line number for later updates
    tool_call.state.path_line = vim.api.nvim_buf_line_count(opts.buffer)

    chat.paste_at_end("\n````txt\n", opts.buffer)
    tool_call.state.search_start_line = vim.api.nvim_buf_line_count(opts.buffer)

    chat.paste_at_end("\n\n", opts.buffer)
    tool_call.state.replace_start_line = vim.api.nvim_buf_line_count(opts.buffer)

    chat.paste_at_end("\n````", opts.buffer)
  end,
  delta = function(tool_call, opts)
    tool_call.parameters.path = vim.trim(tool_call.parameters.path or "")
    tool_call.parameters.search = tool_call.parameters.search or ""
    tool_call.parameters.replace = tool_call.parameters.replace or ""
    tool_call.state.path_written = tool_call.state.path_written or 0
    tool_call.state.search_written = tool_call.state.search_written or 0
    tool_call.state.replace_written = tool_call.state.replace_written or 0

    if tool_call.parameters.path and tool_call.state.path_written < #tool_call.parameters.path then
      vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.path_line - 1, tool_call.state.path_line, false,
        { string.format("**Path:** `%s`", tool_call.parameters.path) })
      tool_call.state.path_written = #tool_call.parameters.path

      -- Update the language for syntax highlighting
      local language = markdown.filename_to_language(tool_call.parameters.path, "txt")
      vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.search_start_line - 2,
        tool_call.state.search_start_line - 1,
        false, { "````" .. language })
    end

    if tool_call.parameters.search and tool_call.state.search_written < #tool_call.parameters.search then
      local search_start_line = tool_call.state.search_start_line
      local written = tool_call.parameters.search:sub(1, tool_call.state.search_written)

      if #written > 0 then
        -- Add the number of lines already written
        local search_lines = select(2, written:gsub("\n", ""))
        search_start_line = search_start_line + search_lines
      end

      chat.paste_at_line(tool_call.parameters.search:sub(tool_call.state.search_written + 1), search_start_line,
        opts.buffer)
      tool_call.state.search_written = #tool_call.parameters.search

      -- Place signs for the search section
      search_start_line = tool_call.state.search_start_line
      local search_end_line = search_start_line + select(2, tool_call.parameters.search:gsub("\n", ""))
      local sign_group = string.format("%s-edit_file_section-search", tool_call.id)
      signs.place(opts.buffer, sign_group, search_start_line, search_end_line, "llm_sidekick_red")
    end

    if tool_call.parameters.replace and tool_call.state.replace_written < #tool_call.parameters.replace then
      local replace_start_line = tool_call.state.replace_start_line

      if tool_call.state.search_written > 0 then
        -- Add the number of lines from the search section
        local search_lines = select(2, tool_call.parameters.search:gsub("\n", ""))
        replace_start_line = replace_start_line + search_lines
      end

      local written = tool_call.parameters.replace:sub(1, tool_call.state.replace_written)

      if #written > 0 then
        -- Add the number of lines already written
        local search_lines = select(2, written:gsub("\n", ""))
        replace_start_line = replace_start_line + search_lines
      end

      chat.paste_at_line(tool_call.parameters.replace:sub(tool_call.state.replace_written + 1), replace_start_line,
        opts.buffer)
      tool_call.state.replace_written = #tool_call.parameters.replace

      -- Place signs for both search and replace sections
      replace_start_line = tool_call.state.replace_start_line
      if tool_call.state.search_written > 0 then
        replace_start_line = replace_start_line + select(2, tool_call.parameters.search:gsub("\n", ""))
      end
      local replace_end_line = replace_start_line + select(2, tool_call.parameters.replace:gsub("\n", ""))
      local sign_group = string.format("%s-edit_file_section-replace", tool_call.id)
      signs.place(opts.buffer, sign_group, replace_start_line, replace_end_line, "llm_sidekick_green")
    end
  end,
  stop = function(tool_call, opts)
    -- If 'replace' is empty, it means we are deleting the code.
    if tool_call.parameters.replace == "" then
      local replace_start_line = tool_call.state.replace_start_line
      if tool_call.state.search_written > 0 then
        replace_start_line = replace_start_line + select(2, tool_call.parameters.search:gsub("\n", ""))
      end

      -- Delete the lines that were allocated for 'replace'
      vim.api.nvim_buf_set_lines(opts.buffer, replace_start_line - 2, replace_start_line, false, {})
    end
  end,
  run = function(tool_call, opts)
    local path = vim.trim(tool_call.parameters.path or "")
    local search = tool_call.parameters.search
    local replace = tool_call.parameters.replace

    -- Split search and replace into lines for line-by-line processing
    local search_lines = vim.split(search, "\n")
    local replace_lines = vim.split(replace, "\n")

    local content_lines = {}
    local buf = vim.fn.bufnr(path)
    local is_buffer_loaded = vim.api.nvim_buf_is_loaded(buf)

    -- Get content lines from buffer or file
    if is_buffer_loaded then
      content_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    else
      local ok, lines = pcall(vim.fn.readfile, path)
      if not ok then
        error(string.format("Failed to read file: %s (%s)", path, vim.inspect(lines)))
      end
      content_lines = lines
    end

    -- Find the maximum indentation in the file for search pattern adjustments
    local max_indent = find_max_indentation(content_lines)

    -- Find the match with possible indentation variations
    local start_line, end_line, matched_search_lines = find_match_with_indentation_variations(
      content_lines,
      search_lines,
      max_indent
    )

    if not start_line then
      error(string.format("Could not find the exact match in file: %s", path))
    end

    -- Handle empty replacement case specially (line removal)
    local adjusted_replace_lines = {}
    local is_empty_replacement = #replace_lines == 1 and replace_lines[1] == ""
    if #replace_lines > 0 and not is_empty_replacement then
      -- Calculate the indentation to apply to the replacement text
      local matched_search_min_indent = find_min_indentation(matched_search_lines)
      local replace_min_indent = find_min_indentation(replace_lines)

      -- Adjust the indentation of the replacement text to match the search text
      adjusted_replace_lines = adjust_replace_indentation(
        replace_lines,
        replace_min_indent,
        matched_search_min_indent
      )
    end

    -- Create the modified content by replacing the matched lines
    local modified_lines = {}

    -- Copy lines before the match
    for i = 1, start_line - 1 do
      table.insert(modified_lines, content_lines[i])
    end

    -- Insert the replacement lines (if any)
    if #adjusted_replace_lines > 0 then
      for _, line in ipairs(adjusted_replace_lines) do
        table.insert(modified_lines, line)
      end
    end
    
    -- Copy lines after the match
    for i = end_line + 1, #content_lines do
      table.insert(modified_lines, content_lines[i])
    end

    -- Write the modified content back
    local err
    local ok
    if is_buffer_loaded then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, modified_lines)
      ok, err = pcall(vim.api.nvim_buf_call, buf, function()
        vim.cmd('write')
      end)
    else
      ok, err = pcall(vim.fn.writefile, modified_lines, path)
    end

    if not ok then
      error(string.format("Failed to write file: %s (%s)", path, vim.inspect(err)))
    end

    -- Replace the tool call content with success message
    local lines_removed = #search_lines
    local lines_added = #replace_lines
    vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.lnum - 1, tool_call.state.end_lnum, false,
      { string.format("✓ Updated `%s` (-%d/+%d)", path, lines_removed, lines_added) })

    return true
  end,
}
