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

local function apply_modification(chat_bufnr, block)
  local file_path, search, replace, chat_buf_start_line, chat_buf_end_line, type, raw_block =
      block.file_path, block.search, block.replace, block.start_line, block.end_line, block.type, block.raw_block
  vim.validate({
    chat_bufnr = { chat_bufnr, "number" },
    file_path = { file_path, "string" },
    chat_buf_start_line = { chat_buf_start_line, "number" },
    chat_buf_end_line = { chat_buf_end_line, "number" },
    type = { type, "string" },
    raw_block = { raw_block, "string" }
  })

  if type == "update" then
    vim.validate({
      search = { search, "string" },
      replace = { replace, "string" }
    })
  end

  if type == "create" then
    vim.validate({
      create = { replace, "string" }
    })
  end

  local add_diagnostic = require("llm-sidekick.diagnostic").add_diagnostic

  if type == "create" then
    -- Create new file
    local dir = vim.fn.fnamemodify(file_path, ":h")
    if vim.fn.isdirectory(dir) == 0 then
      local success = vim.fn.mkdir(dir, "p")
      if success == 0 then
        local err_msg = string.format("Failed to create directory: %s", dir)
        add_diagnostic(chat_bufnr, chat_buf_start_line, chat_buf_start_line, raw_block, vim.diagnostic.severity.ERROR,
          err_msg)
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
        add_diagnostic(chat_bufnr, chat_buf_start_line, chat_buf_start_line, raw_block, vim.diagnostic.severity.ERROR,
          err_msg)
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
    add_diagnostic(chat_bufnr, chat_buf_start_line, chat_buf_start_line, raw_block, vim.diagnostic.severity.INFO,
      success_msg)
  elseif type == "delete" then
    -- Delete file
    local ok, err = vim.fn.delete(file_path)
    if ok ~= 0 then
      local err_msg = string.format("Failed to remove file '%s': %s", file_path, err)
      add_diagnostic(chat_bufnr, chat_buf_start_line, chat_buf_start_line, raw_block, vim.diagnostic.severity.ERROR,
        err_msg)
      error(err_msg)
    end
    -- Close the buffer if it's open
    local buf = vim.fn.bufnr(file_path)
    if buf ~= -1 then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    local success_msg = string.format("Successfully deleted file '%s'", file_path)
    add_diagnostic(chat_bufnr, chat_buf_start_line, chat_buf_start_line, raw_block, vim.diagnostic.severity.INFO,
      success_msg)
  elseif type == "update" then
    local content, content_lines
    local buf = vim.fn.bufnr(file_path)
    if buf >= 0 and vim.api.nvim_buf_is_loaded(buf) then
      content_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      content = table.concat(content_lines, "\n")
    else
      buf = vim.fn.bufadd(file_path)
      if buf == 0 then
        local err_msg = string.format("Failed to open file '%s'", file_path)
        add_diagnostic(chat_bufnr, chat_buf_start_line, chat_buf_start_line, raw_block, vim.diagnostic.severity.ERROR,
          err_msg)
        error(err_msg)
      end
      vim.fn.bufload(buf)
      content_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      content = table.concat(content_lines, "\n")
      vim.api.nvim_buf_delete(buf, { force = true })
    end

    if not content then
      local err_msg = string.format("Failed to read file '%s'", file_path)
      add_diagnostic(chat_bufnr, chat_buf_start_line, chat_buf_start_line, raw_block, vim.diagnostic.severity.ERROR,
        err_msg)
      error(err_msg)
    end

    -- Find the exact string match
    local original_search = search
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
      local err_msg = string.format("Could not find search pattern in file '%s'", file_path)
      add_diagnostic(chat_bufnr, chat_buf_start_line, chat_buf_start_line, raw_block, vim.diagnostic.severity.ERROR,
        err_msg)
      return
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
        add_diagnostic(chat_bufnr, chat_buf_start_line, chat_buf_start_line, raw_block, vim.diagnostic.severity.ERROR,
          err_msg)
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
    add_diagnostic(chat_bufnr, chat_buf_start_line, chat_buf_start_line, raw_block, vim.diagnostic.severity.INFO,
      success_msg)
  end
end

local function find_and_parse_modification_blocks(bufnr, start_search_line, end_search_line)
  local model = ""
  for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, 4, false)) do
    local match = line:match("^MODEL:(.+)$")
    if match then
      model = vim.trim(match)
      break
    end
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_search_line - 1, end_search_line, false)
  for i = 1, #lines do
    lines[i] = lines[i]:gsub("^ASSISTANT:%s*", "")
  end
  local content = table.concat(lines, "\n")

  local blocks = {}
  local create_pattern = "(@([^\n]+)\n<create>\n?(.-)\n?</create>)"
  local modify_pattern = "(@([^\n]+)\n<search>\n?(.-)\n?</search>\n<replace>\n?(.-)\n?</replace>)"
  local delete_pattern = "(@([^\n]+)\n<delete />)"

  if model:lower():find("gemini") then
    -- Gemini format patterns
    create_pattern = "(%*%*File Path:%*%*\n```%w*\n([^\n]+)\n```\n%*%*Create:%*%*\n```%w*\n(.-)\n```)"
    modify_pattern = "(%*%*File Path:%*%*\n```%w*\n([^\n]+)\n```\n%*%*Find:%*%*\n```%w*\n(.-)\n```\n%*%*Replace:%*%*\n```%w*\n(.-)\n```)"
    delete_pattern = "(%*%*File Path:%*%*\n```%w*\n([^\n]+)\n```\n%*%*Delete:%*%*\n```%w*\nN/A\n```)"
  end

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

local function apply_modifications(bufnr, is_apply_all)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local assistant_start_line = find_last_assistant_start_line(lines)
  if assistant_start_line == -1 then
    vim.api.nvim_err_writeln("No assistant block found")
    return
  end
  local assistant_end_line = find_assistant_end_line(assistant_start_line, lines)
  local modification_blocks = find_and_parse_modification_blocks(bufnr, assistant_start_line, assistant_end_line)

  if is_apply_all then
    for _, block in ipairs(modification_blocks) do
      apply_modification(bufnr, block)
    end
  else
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
    for _, block in ipairs(modification_blocks) do
      if cursor_line >= block.start_line and cursor_line <= block.end_line then
        apply_modification(bufnr, block)
        break
      end
    end
  end
end

local function create_apply_modifications_command(bufnr)
  vim.api.nvim_buf_create_user_command(bufnr, "Apply", function()
    apply_modifications(bufnr, false)
  end, {
    desc = "Apply the modification block containing the cursor",
  })

  vim.api.nvim_buf_create_user_command(bufnr, "ApplyAll", function()
    apply_modifications(bufnr, true)
  end, {
    desc = "Apply all modification blocks in the last assistant message",
  })
end

return {
  create_apply_modifications_command = create_apply_modifications_command,
  apply_modifications = apply_modifications,
  find_and_parse_modification_blocks = find_and_parse_modification_blocks,
  find_last_assistant_start_line = find_last_assistant_start_line,
  find_assistant_end_line = find_assistant_end_line,
}
