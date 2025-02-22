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

    chat.paste_at_end("\n```txt\n", opts.buffer)
    tool_call.state.search_start_line = vim.api.nvim_buf_line_count(opts.buffer)

    chat.paste_at_end("\n\n", opts.buffer)
    tool_call.state.replace_start_line = vim.api.nvim_buf_line_count(opts.buffer)

    chat.paste_at_end("\n```", opts.buffer)
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
        false, { "```" .. language })
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
    local replace = tool_call.parameters.replace
    local ok, content, content_lines
    local buf = vim.fn.bufnr(path)
    if vim.api.nvim_buf_is_loaded(buf) then
      content_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      content = table.concat(content_lines, "\n")
    else
      ok, content_lines = pcall(vim.fn.readfile, path)
      if ok then
        content = table.concat(content_lines, "\n")
      else
        error(string.format("Failed to read file: %s (%s)", path, vim.inspect(content_lines)))
      end
    end

    -- Find the exact string match
    local original_search = tool_call.parameters.search
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
    local err
    local modified_content = content:sub(1, start_pos - 1) .. replace .. content:sub(end_pos + 1)
    if vim.api.nvim_buf_is_loaded(buf) then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(modified_content, "\n"))
      ok, err = pcall(vim.api.nvim_buf_call, buf, function()
        vim.cmd('write')
      end)
    else
      ok, err = pcall(vim.fn.writefile, vim.split(modified_content, "\n"), path)
    end

    if not ok then
      error(string.format("Failed to write file: %s (%s)", path, vim.inspect(err)))
    end

    -- Replace the tool call content with success message
    local lines_removed = select(2, tool_call.parameters.search:gsub("\n", ""))
    local lines_added = select(2, tool_call.parameters.replace:gsub("\n", ""))
    vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.lnum - 1, tool_call.state.end_lnum, false,
      { string.format("✓ Updated `%s` (-%d/+%d)", path, lines_removed, lines_added) })

    return true
  end,
}
