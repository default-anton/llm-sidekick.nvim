local markdown = require("llm-sidekick.markdown")
local chat = require("llm-sidekick.chat")
local signs = require("llm-sidekick.signs")

local spec = {
  name = "replace_in_file",
  description =
  "Finds and replaces a block of one or more full, consecutive lines with a new block of lines. This function operates on whole lines, including all indentation, comments, and characters. It will search for an exact, case-sensitive match of the 'old_block' of lines. All occurrences will be replaced",
  input_schema = {
    type = "object",
    properties = {
      file_path = {
        type = "string",
        description = "The absolute or relative path to the file to be modified"
      },
      replacements = {
        type = "array",
        description = "An array of replacement objects. Each object defines an old_block to find and a new_block to replace it with.",
        items = {
          type = "object",
          properties = {
            old_block = {
              type = "string",
              description = "A multi-line string representing the exact block of lines to be replaced. Do not include a trailing newline unless it is part of the final line to match"
            },
            new_block = {
              type = "string",
              description = "The multi-line string that will replace every occurrence of 'old_block'. To delete the 'old_block', provide an empty string for 'new_block'"
            }
          },
          required = { "old_block", "new_block" }
        }
      }
    },
    required = { "file_path", "replacements" },
  }
}

local json_props = string.format([[{
  "file_path": %s,
  "replacements": %s
}]],
  vim.json.encode(spec.input_schema.properties.file_path),
  vim.json.encode(spec.input_schema.properties.replacements)
)

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
  is_show_diagnostics = function() return true end,
  is_auto_acceptable = function(_, buffer)
    return require("llm-sidekick.tools.utils").is_auto_accept_edits(buffer) or
        require("llm-sidekick.settings").auto_accept_file_operations()
  end,
  stop = function(tool_call, opts)
    chat.paste_at_end(string.format("**Replace:** `%s`", tool_call.parameters.file_path), opts.buffer)
    local language = markdown.filename_to_language(tool_call.parameters.file_path, "txt")

    if not tool_call.parameters.replacements or #tool_call.parameters.replacements == 0 then
      chat.paste_at_end("\nNo replacements specified.", opts.buffer)
      return
    end

    if type(tool_call.parameters.replacements) ~= "table" then
      return
    end

    for i, replacement in ipairs(tool_call.parameters.replacements) do
      chat.paste_at_end(string.format("\n\n**Replacement %d:**\n", i), opts.buffer)
      chat.paste_at_end(string.format("````%s\n", language), opts.buffer)
      local old_block_lnum = vim.api.nvim_buf_line_count(opts.buffer)

      if replacement.old_block then
        chat.paste_at_end(replacement.old_block, opts.buffer)
      end
      local old_block_end_lnum = vim.api.nvim_buf_line_count(opts.buffer)

      chat.paste_at_end("\n\n", opts.buffer) -- End old_block code block
      local new_block_lnum = vim.api.nvim_buf_line_count(opts.buffer)

      if replacement.new_block then
        chat.paste_at_end(replacement.new_block, opts.buffer)
      end
      local new_block_end_lnum = vim.api.nvim_buf_line_count(opts.buffer)
      chat.paste_at_end("\n````", opts.buffer) -- End new_block code block

      local old_sign_group = string.format("%s-replace_in_file-old_block-%d", tool_call.id, i)
      signs.place(opts.buffer, old_sign_group, old_block_lnum, old_block_end_lnum, "llm_sidekick_red")

      local new_sign_group = string.format("%s-replace_in_file-new_block-%d", tool_call.id, i)
      signs.place(opts.buffer, new_sign_group, new_block_lnum, new_block_end_lnum, "llm_sidekick_green")
    end
  end,
  run = function(tool_call, opts)
    local path = vim.trim(tool_call.parameters.file_path or "")
    local replacements = tool_call.parameters.replacements

    if not replacements or #replacements == 0 then
      error("Error: No replacements provided.")
    end

    local content_lines = {}
    local buf = vim.fn.bufnr(path)
    local is_buffer_loaded = vim.api.nvim_buf_is_loaded(buf)

    -- Get content lines from buffer or file
    if is_buffer_loaded then
      content_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    else
      local ok_read, lines_or_err = pcall(vim.fn.readfile, path)
      if not ok_read then
        vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.lnum - 1, tool_call.state.lnum, false,
          { string.format("✗ **Replace:** `%s`", path) })
        error(string.format("Error: Failed to read file %s (%s)", path, vim.inspect(lines_or_err)))
      end
      content_lines = lines_or_err
    end

    local total_lines_removed = 0
    local total_lines_added = 0

    for _, replacement_obj in ipairs(replacements) do
      local search = replacement_obj.old_block
      local replace = replacement_obj.new_block

      -- Split search and replace into lines for line-by-line processing
      local search_lines = vim.split(search, "\n")
      local replace_lines = vim.split(replace, "\n")

      -- Find the maximum indentation in the file for search pattern adjustments
      local max_indent = find_max_indentation(content_lines)

      -- Find the match with possible indentation variations
      local start_line, end_line, matched_search_lines = find_match_with_indentation_variations(
        content_lines,
        search_lines,
        max_indent
      )

      if not start_line then
        vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.lnum - 1, tool_call.state.lnum, false,
          { string.format("✗ **Replace:** `%s`", path) })
        error("Error: No match found for replacement: " .. search .. ". Please check your text and try again.")
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
      local modified_lines_for_current_replacement = {}

      -- Copy lines before the match
      for i = 1, start_line - 1 do
        table.insert(modified_lines_for_current_replacement, content_lines[i])
      end

      -- Insert the replacement lines (if any)
      if #adjusted_replace_lines > 0 then
        for _, line in ipairs(adjusted_replace_lines) do
          table.insert(modified_lines_for_current_replacement, line)
        end
      end

      -- Copy lines after the match
      for i = end_line + 1, #content_lines do
        table.insert(modified_lines_for_current_replacement, content_lines[i])
      end

      content_lines = modified_lines_for_current_replacement -- Update content_lines for the next iteration
      total_lines_removed = total_lines_removed + #search_lines
      total_lines_added = total_lines_added + #replace_lines
    end

    -- Write the modified content back
    local err_write
    local ok_write
    if is_buffer_loaded then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, content_lines)
      ok_write, err_write = pcall(vim.api.nvim_buf_call, buf, function()
        vim.cmd('write')
      end)
    else
      ok_write, err_write = pcall(vim.fn.writefile, content_lines, path)
    end

    if not ok_write then
      vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.lnum - 1, tool_call.state.lnum, false,
        { string.format("✗ **Replace:** `%s`", path) })
      error(string.format("Error: Failed to write file %s (%s)", path, vim.inspect(err_write)))
    end

    -- Replace the tool call content with success message
    vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.lnum - 1, tool_call.state.end_lnum, false,
      { string.format("✓ **Replace:** `%s` (%d replacements, -%d/+%d lines)", path, #replacements, total_lines_removed, total_lines_added) })

    return true
  end,
}
