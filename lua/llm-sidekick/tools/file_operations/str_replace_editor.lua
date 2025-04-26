local markdown = require("llm-sidekick.markdown")
local chat = require("llm-sidekick.chat")
local signs = require("llm-sidekick.signs")

local spec = {
  name = "str_replace_editor",
  type = "text_editor_20250124",
  description =
  "Custom editing tool for viewing, creating and editing files. State is persistent across command calls and discussions with the user. If `path` is a file, `view` displays the result of applying `cat -n`. If `path` is a directory, `view` lists non-hidden files and directories up to 2 levels deep. The `create` command cannot be used if the specified `path` already exists as a file. If a `command` generates a long output, it will be truncated and marked with `<response clipped>`. The `undo_edit` command will revert the last edit made to the file at `path`.",
  input_schema = {
    type = "object",
    properties = {
      command = {
        type = "string",
        enum = { "view", "create", "str_replace", "insert", "undo_edit" },
        description = "The commands to run. Allowed options are: `view`, `create`, `str_replace`, `insert`, `undo_edit`."
      },
      path = {
        type = "string",
        description =
        "Path to file or directory, can be absolute or relative to current working directory. Prefer relative paths when working with files in the current directory, e.g. `file.py` or `src/utils.js`."
      },
      old_str = {
        type = "string",
        description = "Required parameter of `str_replace` command containing the string in `path` to replace."
      },
      new_str = {
        type = "string",
        description =
        "Optional parameter of `str_replace` command containing the new string (if not given, no string will be added). Required parameter of `insert` command containing the string to insert."
      },
      file_text = {
        type = "string",
        description = "Required parameter of `create` command, with the content of the file to be created."
      },
      insert_line = {
        type = "integer",
        description =
        "Required parameter of `insert` command. The `new_str` will be inserted AFTER the line `insert_line` of `path`."
      },
      view_range = {
        type = "array",
        items = {
          type = "integer"
        },
        description =
        "Optional parameter of `view` command when `path` points to a file. If none is given, the full file is shown. If provided, the file will be shown in the indicated line number range, e.g. {11, 12} will show lines 11 and 12. Indexing at 1 to start. Setting `{start_line, -1}` shows all lines from `start_line` to the end of the file."
      }
    },
    required = { "command", "path" }
  }
}

local json_props = string.format([[{
  "command": %s,
  "path": %s,
  "old_str": %s,
  "new_str": %s,
  "file_text": %s,
  "insert_line": %s,
  "view_range": %s
}]],
  vim.json.encode(spec.input_schema.properties.command),
  vim.json.encode(spec.input_schema.properties.path),
  vim.json.encode(spec.input_schema.properties.old_str),
  vim.json.encode(spec.input_schema.properties.new_str),
  vim.json.encode(spec.input_schema.properties.file_text),
  vim.json.encode(spec.input_schema.properties.insert_line),
  vim.json.encode(spec.input_schema.properties.view_range)
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
  is_show_diagnostics = function(_) return true end,
  is_auto_acceptable = function(tool_call)
    if tool_call.parameters.command == "view" then
      return true
    end

    return require("llm-sidekick.settings").auto_accept_file_operations()
  end,
  stop = function(tool_call, opts)
    if tool_call.parameters.command == "view" then
      if tool_call.parameters.view_range and type(tool_call.parameters.view_range) == "table" then
        chat.paste_at_end(
          string.format(
            "**Read:** `%s:%d-%d`",
            tool_call.parameters.path,
            tool_call.parameters.view_range[1],
            tool_call.parameters.view_range[2]
          ),
          opts.buffer
        )
      else
        chat.paste_at_end(string.format("**Read:** `%s`", tool_call.parameters.path), opts.buffer)
      end
    elseif tool_call.parameters.command == "str_replace" then
      chat.paste_at_end(string.format("**Replace:** `%s`", tool_call.parameters.path), opts.buffer)

      local language = markdown.filename_to_language(tool_call.parameters.path, "txt")
      chat.paste_at_end(string.format("\n````%s\n", language), opts.buffer)
      local old_str_lnum = vim.api.nvim_buf_line_count(opts.buffer)

      chat.paste_at_end(tool_call.parameters.old_str, opts.buffer)
      local old_str_end_lnum = vim.api.nvim_buf_line_count(opts.buffer)

      chat.paste_at_end("\n\n", opts.buffer)
      local new_str_lnum = vim.api.nvim_buf_line_count(opts.buffer)

      chat.paste_at_end(tool_call.parameters.new_str, opts.buffer)
      local new_str_end_lnum = vim.api.nvim_buf_line_count(opts.buffer)

      chat.paste_at_end("\n````", opts.buffer)

      local sign_group = string.format("%s-str_replace_editor-old_str", tool_call.id)
      signs.place(opts.buffer, sign_group, old_str_lnum, old_str_end_lnum, "llm_sidekick_red")

      sign_group = string.format("%s-str_replace_editor-new_str", tool_call.id)
      signs.place(opts.buffer, sign_group, new_str_lnum, new_str_end_lnum, "llm_sidekick_green")
    elseif tool_call.parameters.command == "create" then
      chat.paste_at_end(string.format("**Create:** `%s`", tool_call.parameters.path), opts.buffer)

      local language = markdown.filename_to_language(tool_call.parameters.path, "txt")
      chat.paste_at_end(string.format("\n````%s\n", language), opts.buffer)
      local file_text_lnum = vim.api.nvim_buf_line_count(opts.buffer)

      chat.paste_at_end(tool_call.parameters.file_text, opts.buffer)
      local file_text_end_lnum = vim.api.nvim_buf_line_count(opts.buffer)

      chat.paste_at_end("\n````", opts.buffer)

      local sign_group = string.format("%s-str_replace_editor-file_text", tool_call.id)
      signs.place(opts.buffer, sign_group, file_text_lnum, file_text_end_lnum, "llm_sidekick_green")
    elseif tool_call.parameters.command == "insert" then
      chat.paste_at_end(
        string.format(
          "**Insert:** `%s:%d`",
          tool_call.parameters.path,
          tool_call.parameters.insert_line
        ),
        opts.buffer
      )

      local language = markdown.filename_to_language(tool_call.parameters.path, "txt")
      chat.paste_at_end(string.format("\n````%s\n", language), opts.buffer)
      local new_str_lnum = vim.api.nvim_buf_line_count(opts.buffer)

      chat.paste_at_end(tool_call.parameters.new_str, opts.buffer)
      local new_str_end_lnum = vim.api.nvim_buf_line_count(opts.buffer)

      chat.paste_at_end("\n````", opts.buffer)

      local sign_group = string.format("%s-str_replace_editor-new_str", tool_call.id)
      signs.place(opts.buffer, sign_group, new_str_lnum, new_str_end_lnum, "llm_sidekick_green")
    elseif tool_call.parameters.command == "undo_edit" then
      chat.paste_at_end(
        string.format(
          "**Undo:** `%s` 😭 Sorry, undo functionality is not implemented yet! 🙈 Time travel remains a mystery to us all...",
          tool_call.parameters.path
        ),
        opts.buffer
      )
    end
  end,
  run = function(tool_call, opts)
    if tool_call.parameters.command == "view" then
      local path = vim.trim(tool_call.parameters.path or "")
      local view_range = tool_call.parameters.view_range
      local start_line = 0
      local end_line = -1
      if view_range and type(view_range) == "table" then
        start_line = view_range[1] - 1
        end_line = view_range[2]
      end

      if vim.fn.isdirectory(path) == 1 then
        local ok, entries = pcall(vim.fn.readdir, path)
        if not ok then
          error(string.format("Error: Failed to list directory %s (%s)", path, vim.inspect(entries)))
        end

        -- Replace the tool call content with success message
        local success_message = string.format("✓ Viewed directory `%s` (%d files)", path, #entries)
        vim.api.nvim_buf_set_lines(
          opts.buffer,
          tool_call.state.lnum - 1,
          tool_call.state.end_lnum,
          false,
          { success_message }
        )

        return table.concat(entries, "\n")
      end

      -- Handle file viewing
      local content_lines = {}
      local buf = vim.fn.bufnr(path)
      local is_buffer_loaded = vim.api.nvim_buf_is_loaded(buf)

      -- Get content lines from buffer or file
      if is_buffer_loaded then
        content_lines = vim.api.nvim_buf_get_lines(buf, start_line, end_line, false)
      else
        if start_line == 0 and end_line == -1 then
          local ok, lines = pcall(vim.fn.readfile, path)
          if not ok then
            error(string.format("Error: Failed to read file %s (%s)", path, vim.inspect(lines)))
          end
          content_lines = lines
        elseif end_line == -1 then
          local ok, lines = pcall(vim.fn.readfile, path)
          if not ok then
            error(string.format("Error: Failed to read file %s (%s)", path, vim.inspect(lines)))
          end
          content_lines = vim.list_slice(lines, start_line + 1, #lines)
        else
          local ok, lines = pcall(vim.fn.readfile, path, '', end_line)
          if not ok then
            error(string.format("Error: Failed to read file %s (%s)", path, vim.inspect(lines)))
          end
          content_lines = vim.list_slice(lines, start_line + 1, end_line)
        end
      end

      -- Add line numbers to the content
      local i = 0
      content_lines = vim.tbl_map(function(line)
        i = i + 1
        return string.format("%d|%s", i, line)
      end, content_lines)

      -- Replace the tool call content with success message
      local line_count = #content_lines
      local success_message
      if view_range and type(view_range) == "table" then
        success_message = string.format("✓ Viewed `%s:%d-%d` (%d lines)", path, view_range[1], view_range[2], line_count)
      else
        success_message = string.format("✓ Viewed `%s` (%d lines)", path, line_count)
      end
      vim.api.nvim_buf_set_lines(
        opts.buffer,
        tool_call.state.lnum - 1,
        tool_call.state.end_lnum,
        false,
        { success_message }
      )

      return table.concat(content_lines, "\n")
    elseif tool_call.parameters.command == "str_replace" then
      local path = vim.trim(tool_call.parameters.path or "")
      local search = tool_call.parameters.old_str
      local replace = tool_call.parameters.new_str

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
          error(string.format("Error: Failed to read file %s (%s)", path, vim.inspect(lines)))
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
        error("Error: No match found for replacement. Please check your text and try again.")
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
        error(string.format("Error: Failed to write file %s (%s)", path, vim.inspect(err)))
      end

      -- Replace the tool call content with success message
      local lines_removed = #search_lines
      local lines_added = #replace_lines
      vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.lnum - 1, tool_call.state.end_lnum, false,
        { string.format("✓ Updated `%s` (-%d/+%d)", path, lines_removed, lines_added) })

      return true
    elseif tool_call.parameters.command == "create" then
      local path = vim.trim(tool_call.parameters.path or "")
      local content = tool_call.parameters.file_text
      local insert_line = tool_call.parameters.insert_line

      local dir = vim.fn.fnamemodify(path, ":h")
      if vim.fn.isdirectory(dir) == 0 then
        local ok, err = pcall(vim.fn.mkdir, dir, "p")
        if not ok then
          error(string.format("Error: Failed to create dir %s (%s)", dir, vim.inspect(err)))
        end
      end

      local ok, err
      local buf = vim.fn.bufnr(path)
      if vim.api.nvim_buf_is_loaded(buf) then
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n"))
        ok, err = pcall(vim.api.nvim_buf_call, buf, function()
          vim.cmd("write")
        end)
      else
        ok, err = pcall(vim.fn.writefile, vim.split(content, "\n"), path)
      end

      if not ok then
        error(string.format("Error: Failed to write file %s (%s)", path, vim.inspect(err)))
      end

      -- Replace the tool call content with success message
      vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.lnum - 1, tool_call.state.end_lnum, false,
        { string.format("✓ Created file `%s`", path) })

      return true
    elseif tool_call.parameters.command == "insert" then
      local path = vim.trim(tool_call.parameters.path or "")
      -- The line number after which to insert the text (0 for beginning of file)
      local insert_line = tool_call.parameters.insert_line
      local content = tool_call.parameters.new_str

      local ok, err
      local buf = vim.fn.bufnr(path)
      if vim.api.nvim_buf_is_loaded(buf) then
        vim.api.nvim_buf_set_lines(buf, insert_line, insert_line, false, vim.split(content, "\n"))
        ok, err = pcall(vim.api.nvim_buf_call, buf, function()
          vim.cmd.write()
        end)
      else
        vim.cmd.edit(path)
        local bufnr = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(bufnr, insert_line, insert_line, false, vim.split(content, "\n"))
        vim.cmd('write | bdelete')
      end

      if not ok then
        error(string.format("Error: Failed to write file %s (%s)", path, vim.inspect(err)))
      end

      -- Replace the tool call content with success message
      vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.lnum - 1, tool_call.state.end_lnum, false,
        { string.format("✓ Inserted text into `%s` at line %d", path, insert_line) })

      return true
    elseif tool_call.parameters.command == "undo_edit" then
      -- TODO: Implement undo functionality
    end
  end,
}
