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

local function apply_modification(chat_bufnr, block)
  local file_path, search, replace, chat_buf_start_line, chat_buf_end_line, type, raw_block =
      block.file_path, block.search, block.replace, block.start_line, block.end_line, block.type, block.raw_block
  vim.validate('chat_bufnr', chat_bufnr, 'number')
  vim.validate('file_path', file_path, 'string')
  vim.validate('chat_buf_start_line', chat_buf_start_line, 'number')
  vim.validate('chat_buf_end_line', chat_buf_end_line, 'number')
  vim.validate('type', type, 'string')
  vim.validate('raw_block', raw_block, 'string')

  if type == "update" then
    vim.validate('search', search, 'string')
    vim.validate('replace', replace, 'string')
  end

  if type == "create" then
    vim.validate('create', replace, 'string')
  end

  local add_diagnostic = require("llm-sidekick.diagnostic").add_diagnostic

  if type == "create" then
    -- Create new file
    local dir = vim.fn.fnamemodify(file_path, ":h")
    if vim.fn.isdirectory(dir) == 0 then
      local success = vim.fn.mkdir(dir, "p")
      if success == 0 then
        local err_msg = string.format("Failed to create directory: %s", dir)
        add_diagnostic(chat_bufnr, chat_buf_start_line, chat_buf_end_line, raw_block, vim.diagnostic.severity.ERROR, err_msg)
        error(err_msg)
      end
    end
    -- Get buffer for the new file
    local buf = vim.fn.bufnr(file_path)
    if buf == -1 then
      local ok, err = pcall(function()
        vim.fn.writefile(vim.split(replace, "\n"), file_path)
      end)
      if not ok then
        local err_msg = string.format("Failed to write file %s: %s", file_path, err)
        add_diagnostic(chat_bufnr, chat_buf_start_line, chat_buf_end_line, raw_block, vim.diagnostic.severity.ERROR, err_msg)
        error(err_msg)
      end
    else
      -- File is already open in a buffer
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(replace, "\n"))
      vim.api.nvim_buf_call(buf, function()
        vim.cmd("write")
      end)
    end
    local success_msg = string.format("Successfully created file '%s'", file_path)
    add_diagnostic(chat_bufnr, chat_buf_start_line, chat_buf_end_line, raw_block, vim.diagnostic.severity.INFO, success_msg)
  elseif type == "delete" then
    -- Delete file
    local ok, err = vim.fn.delete(file_path)
    if ok ~= 0 then
      local err_msg = string.format("Failed to remove file '%s': %s", file_path, err)
      add_diagnostic(chat_bufnr, chat_buf_start_line, chat_buf_end_line, raw_block, vim.diagnostic.severity.ERROR, err_msg)
      error(err_msg)
    end
    -- Close the buffer if it's open
    local buf = vim.fn.bufnr(file_path)
    if buf ~= -1 then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    local success_msg = string.format("Successfully deleted file '%s'", file_path)
    add_diagnostic(chat_bufnr, chat_buf_start_line, chat_buf_end_line, raw_block, vim.diagnostic.severity.INFO, success_msg)
  elseif type == "update" then
    local content
    local buf = vim.fn.bufnr(file_path)
    if buf >= 0 and vim.api.nvim_buf_is_loaded(buf) then
      content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    else
      buf = vim.fn.bufadd(file_path)
      if buf == 0 then
        local err_msg = string.format("Failed to open file '%s'", file_path)
        add_diagnostic(chat_bufnr, chat_buf_start_line, chat_buf_end_line, raw_block, vim.diagnostic.severity.ERROR, err_msg)
        error(err_msg)
      end
      vim.fn.bufload(buf)
      content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      vim.api.nvim_buf_delete(buf, { force = true })
    end

    if not content then
      local err_msg = string.format("Failed to read file '%s'", file_path)
      add_diagnostic(chat_bufnr, chat_buf_start_line, chat_buf_end_line, raw_block, vim.diagnostic.severity.ERROR, err_msg)
      error(err_msg)
    end

    -- Find the exact string match
    local start_pos, end_pos = content:find(search, 1, true)
    local search_lines = vim.split(search, "\n")
    local search_min_indent = find_min_indentation(search_lines)

    if not start_pos then
      local max_iterations = 10
      while search_min_indent > 0 and start_pos == nil and max_iterations > 0 do
        search_lines = dedent_lines(search_lines, 1)
        search = table.concat(search_lines, "\n")
        search_min_indent = find_min_indentation(search_lines)
        start_pos, end_pos = content:find(search, 1, true)
        max_iterations = max_iterations - 1
      end
    end

    if not start_pos then
      local err_msg = string.format("Could not find search pattern in file '%s'", file_path)
      add_diagnostic(chat_bufnr, chat_buf_start_line, chat_buf_end_line, raw_block, vim.diagnostic.severity.ERROR, err_msg)
      return
    end

    -- match the indentation of the search pattern
    local replace_lines = vim.split(replace, "\n")
    local replace_min_indent = find_min_indentation(replace_lines)
    if replace_min_indent ~= search_min_indent then
      replace_lines = dedent_lines(replace_lines, replace_min_indent - search_min_indent)
      replace = table.concat(replace_lines, "\n")
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
        local err_msg = string.format("Failed to write to file '%s': %s", file_path, err)
        add_diagnostic(chat_bufnr, chat_buf_start_line, chat_buf_end_line, raw_block, vim.diagnostic.severity.ERROR, err_msg)
        error(err_msg)
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

    local success_msg = string.format("Successfully updated file '%s'", file_path)
    add_diagnostic(chat_bufnr, chat_buf_start_line, chat_buf_end_line, raw_block, vim.diagnostic.severity.INFO, success_msg)
  end
end

local function find_and_parse_modification_blocks(bufnr, start_search_line, end_search_line)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_search_line - 1, end_search_line, false)
  local content = table.concat(lines, "\n")

  local blocks = {}
  local create_pattern = "(@([^\n]+)\n<create>\n?(.-)\n?</create>)"
  local modify_pattern = "(@([^\n]+)\n<search>\n?(.-)\n?</search>\n<replace>\n?(.-)\n?</replace>)"
  local delete_pattern = "(@([^\n]+)\n<delete />)"

  local function find_block_start_line(block)
    local start_line = nil
    if bufnr then
      local block_lines = vim.split(block, "\n")
      for i = 1, #lines - #block_lines + 1 do
        local match = true
        for j = 1, #block_lines do
          if lines[i + j - 1] ~= block_lines[j] then
            match = false
            break
          end
        end
        if match then
          start_line = i + start_search_line - 1
          break
        end
      end
    end

    return start_line
  end

  -- First, handle create blocks
  for block, file_path, create_content in content:gmatch(create_pattern) do
    local abs_path = vim.fn.fnamemodify(file_path, ":p")
    local cwd = vim.fn.getcwd()
    if not vim.startswith(abs_path, cwd) then
      vim.api.nvim_err_writeln(string.format("The file path '%s' must be within the current working directory '%s'",
        abs_path, cwd))
    else
      local start_line = find_block_start_line(block)

      table.insert(blocks, {
        type = "create",
        file_path = file_path,
        replace = create_content,
        start_line = start_line,
        end_line = start_line + #vim.split(block, "\n"),
        raw_block = block,
      })
    end
  end

  -- Handle modify blocks
  for block, file_path, search_content, replace_content in content:gmatch(modify_pattern) do
    local abs_path = vim.fn.fnamemodify(file_path, ":p")
    local cwd = vim.fn.getcwd()
    if not vim.startswith(abs_path, cwd) then
      vim.api.nvim_err_writeln(string.format("The file path '%s' must be within the current working directory '%s'",
        abs_path, cwd))
    else
      local start_line = find_block_start_line(block)

      table.insert(blocks, {
        type = "update",
        file_path = file_path,
        search = search_content,
        replace = replace_content,
        start_line = start_line,
        end_line = start_line + #vim.split(block, "\n"),
        raw_block = block,
      })
    end
  end

  -- Then, handle delete blocks
  for block, file_path in content:gmatch(delete_pattern) do
    local abs_path = vim.fn.fnamemodify(file_path, ":p")
    local cwd = vim.fn.getcwd()
    if not vim.startswith(abs_path, cwd) then
      vim.api.nvim_err_writeln(string.format("The file path '%s' must be within the current working directory '%s'",
        abs_path, cwd))
    else
      local start_line = find_block_start_line(block)

      table.insert(blocks, {
        type = "delete",
        file_path = file_path,
        start_line = start_line,
        end_line = start_line + #vim.split(block, "\n"),
        raw_block = block,
      })
    end
  end

  return blocks
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
  while end_line <= #lines do
    if lines[end_line]:match("^USER:") then
      return end_line - 1
    end
    end_line = end_line + 1
  end

  return #lines
end

local function apply_modifications(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local assistant_start_line = find_last_assistant_start_line(lines)
  if assistant_start_line == -1 then
    vim.api.nvim_err_writeln("No assistant block found")
    return
  end
  local assistant_end_line = find_assistant_end_line(assistant_start_line, lines)
  local modification_blocks = find_and_parse_modification_blocks(bufnr, assistant_start_line, assistant_end_line)

  for _, block in ipairs(modification_blocks) do
    apply_modification(bufnr, block)
  end
end

local function create_apply_modifications_command(bufnr)
  vim.api.nvim_buf_create_user_command(bufnr, "Apply", function()
    apply_modifications(bufnr)
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
  apply_modifications = apply_modifications,
  find_and_parse_modification_blocks = find_and_parse_modification_blocks,
}
