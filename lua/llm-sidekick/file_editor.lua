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

local function apply_modification(chat_bufnr, file_path, search, replace, block_lines)
  vim.validate({
    chat_bufnr = { chat_bufnr, "number" },
    file_path = { file_path, "string" },
    search = { search, "string" },
    replace = { replace, "string" },
    block_lines = { block_lines, "table" },
  })
  local trimmed_search = vim.trim(search)
  local trimmed_replace = vim.trim(replace)

  if trimmed_search == "" and trimmed_replace == "" then
    -- Delete file
    local ok, err = vim.fn.delete(file_path)
    if ok ~= 0 then
      error(string.format("Failed to remove file '%s': %s", file_path, err))
    end
    -- Close the buffer if it's open
    local buf = vim.fn.bufnr(file_path)
    if buf ~= -1 then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  elseif trimmed_search == "" then
    -- Create new file
    local dir = vim.fn.fnamemodify(file_path, ":h")
    if vim.fn.isdirectory(dir) == 0 then
      local success = vim.fn.mkdir(dir, "p")
      if success == 0 then
        error(string.format("Failed to create directory: %s", dir))
      end
    end
    -- Get buffer for the new file
    local buf = vim.fn.bufnr(file_path)
    if buf == -1 then
      local ok, err = pcall(function()
        vim.fn.writefile(vim.split(replace, "\n"), file_path)
      end)
      if not ok then
        error(string.format("Failed to write file %s: %s", file_path, err))
      end
    else
      -- File is already open in a buffer
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(replace, "\n"))
      vim.api.nvim_buf_call(buf, function()
        vim.cmd("write")
      end)
    end
  else
    -- Modify existing file
    local content
    local buf = vim.fn.bufnr(file_path)
    if buf >= 0 and vim.api.nvim_buf_is_loaded(buf) then
      content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    else
      buf = vim.fn.bufadd(file_path)
      if buf == 0 then
        error(string.format("Failed to open file '%s'", file_path))
      end
      vim.fn.bufload(buf)
      content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      vim.api.nvim_buf_delete(buf, { force = true })
    end

    if not content then
      error(string.format("Failed to read file '%s'", file_path))
    end

    -- Find the exact string match
    local start_pos, end_pos = content:find(search, 1, true)

    if not start_pos then
      local search_lines = vim.split(search, "\n")
      local search_min_indent = find_min_indentation(search_lines)
      local dedented_search_lines = dedent_lines(search_lines, search_min_indent)
      local dedented_search = table.concat(dedented_search_lines, "\n")

      start_pos, end_pos = content:find(dedented_search, 1, true)

      if not start_pos then
        vim.api.nvim_err_writeln(string.format("Could not find search pattern '%s' in file '%s'", search, file_path))
        return
      end

      -- Extract and analyze the original matched text
      local original_text = content:sub(start_pos, end_pos)
      local original_lines = vim.split(original_text, "\n")
      local original_indent = find_min_indentation(original_lines)

      -- Process replacement text
      local replace_lines = vim.split(replace, "\n")
      local replace_min_indent = find_min_indentation(replace_lines)

      if replace_min_indent ~= original_indent then
        -- Adjust indentation of replacement text to match original
        local indented_replace_lines = {}
        for _, line in ipairs(replace_lines) do
          if line:match("^%s*$") then
            -- Preserve empty lines
            table.insert(indented_replace_lines, line)
          else
            -- Remove existing minimum indentation
            local dedented = line:gsub("^" .. string.rep(" ", replace_min_indent), "")
            -- Add original indentation
            table.insert(indented_replace_lines, string.rep(" ", original_indent) .. dedented)
          end
        end
        replace = table.concat(indented_replace_lines, "\n")
      end
    end
    -- Perform the substitution
    local modified_content = content:sub(1, start_pos - 1) .. replace .. content:sub(end_pos + 1)
    -- Determine if the file is open in a buffer
    local bufnr = vim.fn.bufnr(file_path)
    if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
      -- File is open in a buffer
      local new_lines = vim.split(modified_content, "\n")
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
      vim.api.nvim_buf_call(bufnr, function()
        vim.cmd('write')
      end)
    else
      -- File is not open; write directly to disk
      local ok, err = pcall(vim.fn.writefile, vim.split(modified_content, "\n"), file_path)
      if not ok then
        error(string.format("Failed to write to file '%s': %s", file_path, err))
      end
    end

    -- Refresh any open windows displaying this file
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local win_buf = vim.api.nvim_win_get_buf(win)
      if vim.api.nvim_buf_get_name(win_buf) == file_path then
        vim.api.nvim_win_call(win, function()
          vim.cmd('checktime')
        end)
      end
    end
  end

  -- Find the block position in the buffer
  local buf_lines = vim.api.nvim_buf_get_lines(chat_bufnr, 0, -1, false)
  local block_start = nil
  local block_end = nil

  -- First line of block_lines should match exactly with a line in the buffer
  local first_block_line = block_lines[1]
  for i, line in ipairs(buf_lines) do
    if line == first_block_line then
      -- Found the start of our block
      block_start = i
      -- Check if subsequent lines match
      local found_block = true
      for j = 2, #block_lines do
        if buf_lines[i + j - 1] ~= block_lines[j] then
          found_block = false
          break
        end
      end
      if found_block then
        block_end = i + #block_lines - 1
        break
      end
    end
  end

  if not block_start or not block_end then
    error("Could not find the modification block in the buffer")
  end

  -- Replace the modification block with changes_applied block
  local changes_applied_lines = {
    "@" .. file_path,
    "<changes_applied>",
  }
  local replace_lines = vim.split(replace, "\n")
  vim.list_extend(changes_applied_lines, replace_lines)
  table.insert(changes_applied_lines, "</changes_applied>")

  vim.api.nvim_buf_set_lines(chat_bufnr, block_start - 1, block_end, false, changes_applied_lines)
end

local function find_modification_block(cursor_line, lines)
  local start_line = cursor_line
  local end_line = cursor_line
  local state = "searching" -- States: searching, in_search, in_replace
  local has_search = false
  local has_replace = false

  -- Find the start of the block
  while start_line > 0 and state == "searching" do
    local current_line = lines[start_line]
    if current_line and current_line:match("^@") then
      state = "found_start"
      break
    end
    start_line = start_line - 1
  end

  if state ~= "found_start" then
    return {}
  end

  -- Validate the block structure
  for i = start_line + 1, #lines do
    local line = lines[i]
    if state == "found_start" and line:match("^<search>$") then
      state = "in_search"
    elseif state == "in_search" and (line:match("^</search>$") or line:match("</search>$")) then
      has_search = true
      state = "after_search"
    elseif state == "after_search" and line:match("^<replace>$") then
      state = "in_replace"
    elseif state == "in_replace" and (line:match("^</replace>$") or line:match("</replace>$")) then
      has_replace = true
      end_line = i
      break
    elseif line:match("^@") then
      -- Found start of next block before completing current one
      return {}
    end
  end

  if not (has_search and has_replace) then
    return {}
  end

  -- if cursor_line is outside the block, return an empty list
  if cursor_line < start_line or cursor_line > end_line then
    return {}
  end

  return vim.list_slice(lines, start_line, end_line)
end

local function parse_modification_block(lines)
  local file_path = lines[1]:match("^@(.+)")
  local abs_path = vim.fn.fnamemodify(file_path, ":p")
  local cwd = vim.fn.getcwd()
  if not vim.startswith(abs_path, cwd) then
    error(string.format("The file path '%s' must be within the current working directory '%s'", abs_path, cwd))
  end

  local search = {}
  local replace = {}
  local in_search = false
  local in_replace = false

  for i = 2, #lines do
    local line = lines[i]
    if line:match("^<search>$") then
      in_search = true
    elseif line:match("^</search>$") or line:match("</search>$") then
      if not line:match("^</search>$") then
        -- If the closing tag is at the end of a content line, add the content
        local content = line:gsub("</search>$", "")
        table.insert(search, content)
      end
      in_search = false
    elseif line:match("^<replace>$") then
      in_replace = true
    elseif line:match("^</replace>$") or line:match("</replace>$") then
      if not line:match("^</replace>$") then
        -- If the closing tag is at the end of a content line, add the content
        local content = line:gsub("</replace>$", "")
        table.insert(replace, content)
      end
      in_replace = false
    elseif in_search then
      table.insert(search, line)
    elseif in_replace then
      table.insert(replace, line)
    end
  end

  return file_path, table.concat(search, "\n"), table.concat(replace, "\n")
end

local function find_last_assistant_start_line(lines)
  for i = #lines, 1, -1 do
    if lines[i]:match("^ASSISTANT:") then
      return i
    end
  end
  return -1
end

local function find_assistant_end_line(start_line, lines)
  local end_line = start_line
  while end_line < #lines do
    if lines[end_line]:match("^USER:") then
      return end_line - 1
    end
    end_line = end_line + 1
  end

  return #lines
end

local function find_candidate_modification_blocks(start_line, end_line, lines)
  local block_start_candidates = {}
  for i = start_line, end_line do
    if lines[i]:match("^@") then
      table.insert(block_start_candidates, i)
    end
  end
  return block_start_candidates
end

local function apply_modifications(bufnr, is_all)
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local block_start_candidates = {}
  if is_all then
    local assistant_start_line = find_last_assistant_start_line(lines)
    if assistant_start_line == -1 then
      vim.api.nvim_err_writeln("No assistant block found")
      return
    end
    local assistant_end_line = find_assistant_end_line(cursor_line, lines)
    block_start_candidates = find_candidate_modification_blocks(assistant_start_line, assistant_end_line, lines)
  end

  if vim.tbl_isempty(block_start_candidates) then
    block_start_candidates = { cursor_line }
  end

  for _, block_start_candidate in ipairs(block_start_candidates) do
    local block_lines = find_modification_block(block_start_candidate, lines)
    if vim.tbl_isempty(block_lines) then
      goto continue
    end
    local file_path, search, replace = parse_modification_block(block_lines)
    if not file_path then
      vim.api.nvim_err_writeln("Skipping invalid modification block at line " .. block_start_candidate)
      goto continue
    end
    apply_modification(bufnr, file_path, search, replace, block_lines)
    ::continue::
  end
end

local function create_apply_modifications_command(bufnr)
  vim.api.nvim_buf_create_user_command(bufnr, "Apply", function(opts)
    apply_modifications(bufnr, opts.args == "all")
  end, {
    desc = "Apply the changes to the file(s) based on modification block(s)",
    nargs = "?",
    complete = function()
      return { "all" }
    end,
  })
end

return {
  create_apply_modifications_command = create_apply_modifications_command,
  find_modification_block = find_modification_block,
  parse_modification_block = parse_modification_block,
  apply_modifications = apply_modifications,
}
