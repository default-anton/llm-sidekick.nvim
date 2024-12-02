local function apply_file_operation(file_path, search, replace)
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
    local content = table.concat(vim.fn.readfile(file_path), "\n")
    -- Find the exact string match
    local start_pos, end_pos = content:find(search, 1, true)
    if not start_pos then
      vim.api.nvim_err_writeln(string.format("No exact matches found in '%s'.", file_path))
      return
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
end

local function find_modification_block(cursor_line, lines)
  local start_line = cursor_line
  local end_line = cursor_line
  local state = "searching" -- States: searching, in_search, in_replace
  local has_search = false
  local has_replace = false

  -- Find the start of the block
  while start_line > 0 and state == "searching" do
    if lines[start_line]:match("^@") then
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

local function find_closest_assistant_start_line(cursor_line, lines)
  local start_line = cursor_line
  while start_line > 0 do
    if lines[start_line]:match("^ASSISTANT:") then
      return start_line
    end
    start_line = start_line - 1
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

local function create_apply_modifications_command(bufnr)
  vim.api.nvim_buf_create_user_command(bufnr, "Apply", function(opts)
    local is_all = opts.args == "all"
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    local block_start_candidates = { cursor_line }
    if is_all then
      local assistant_start_line = find_closest_assistant_start_line(cursor_line, lines)
      if assistant_start_line == -1 then
        vim.api.nvim_err_writeln("No assistant block found")
        return
      end
      local assistant_end_line = find_assistant_end_line(assistant_start_line, lines)
      block_start_candidates = find_candidate_modification_blocks(assistant_start_line, assistant_end_line, lines)
    end

    if vim.tbl_isempty(block_start_candidates) then
      vim.api.nvim_err_writeln("No modification block found")
      return
    end

    for _, block_start_candidate in ipairs(block_start_candidates) do
      local block_lines = find_modification_block(block_start_candidate, lines)
      if vim.tbl_isempty(block_lines) then
        vim.api.nvim_err_writeln("No modification block found at cursor position")
        return
      end
      local file_path, search, replace = parse_modification_block(block_lines)
      if not file_path then
        vim.api.nvim_err_writeln("Invalid modification block format")
        return
      end
      apply_file_operation(file_path, search, replace)
    end
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
}
