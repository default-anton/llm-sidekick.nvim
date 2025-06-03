local M = {}

---Read the entire contents of a file
---@param path string The path to the file to read
---@return string|nil content The file contents or nil if file cannot be opened
function M.read_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil
  end
  return table.concat(lines, "\n")
end

local function expand_home(path)
  if path:sub(1, 1) == "~" then
    return vim.fn.expand("~") .. path:sub(2)
  end
  return path
end

local function normalize_path(path)
  if path == nil or path == "" then return nil end
  return vim.fn.fnamemodify(expand_home(path), ":p")
end

local function is_dir(path)
  return vim.fn.isdirectory(path) == 1
end

local function get_parent_dir(path)
  local parent = vim.fn.fnamemodify(path, ":h")
  -- Handle root directory case or invalid paths
  if parent == path or parent == "" or parent == nil then
    return nil
  end
  return parent
end

---Find CLAUDE.md files based on different strategies.
---@param opts table Options table:
---  - search_strategy (string): "system_prompt" or "tool_operation"
---  - cwd (string): Current working directory (for "system_prompt")
---  - home_claude_file (string): Path to user's global Claude file (for "system_prompt")
---  - start_dir (string): Directory to start search from (for "tool_operation")
---  - stop_at_dir (string): Directory path to stop ascending
---@return table A list of unique absolute paths to found CLAUDE.md files.
function M.find_claude_md_files(opts)
  local found_files = {}
  local found_files_set = {}

  local function add_file(path)
    local abs_path = normalize_path(path)
    if abs_path and not found_files_set[abs_path] then
      table.insert(found_files, abs_path)
      found_files_set[abs_path] = true
    end
  end

  local stop_at = normalize_path(opts.stop_at_dir)
  if not stop_at then
    -- Default stop_at to user's home directory if not provided or invalid
    stop_at = normalize_path("~")
    if not stop_at then -- Fallback if home expansion somehow fails
      return {} -- Cannot proceed without a valid stop_at
    end
  end

  local function search_upwards(start_search_dir, stop_search_dir)
    local search_results = {}
    local current_dir = normalize_path(start_search_dir)

    while current_dir do
      if not is_dir(current_dir) then
        current_dir = get_parent_dir(current_dir)
        goto continue_while -- Skip if current_dir is not a directory (e.g. start_dir was a file)
      end

      local claude_file_path = current_dir .. "/CLAUDE.md"
      -- Check if the file exists and is a file (not a directory)
      if vim.fn.filereadable(claude_file_path) == 1 and vim.fn.isdirectory(claude_file_path) == 0 then
        -- add_file handles normalization and uniqueness via found_files_set
        -- We store it in search_results to maintain the specific order for this search pass
        local abs_path = normalize_path(claude_file_path)
        if abs_path and not found_files_set[abs_path] then
            table.insert(search_results, abs_path)
            -- Mark as globally found to respect uniqueness across different search passes
            found_files_set[abs_path] = true
        end
      end

      -- Stop if current_dir is the stop_search_dir
      if current_dir == stop_search_dir then
        break
      end

      local parent_dir = get_parent_dir(current_dir)
      if not parent_dir or parent_dir == current_dir then -- Reached root or error
        break
      end
      current_dir = parent_dir

      ::continue_while::
    end
    return search_results
  end

  if opts.search_strategy == "system_prompt" then
    if not opts.cwd or not opts.home_claude_file then
      vim.notify("find_claude_md_files: 'cwd' and 'home_claude_file' are required for 'system_prompt' strategy", vim.log.levels.ERROR)
      return {}
    end

    local upward_files = search_upwards(opts.cwd, stop_at)
    -- Add files from deepest to shallowest
    for i = 1, #upward_files do
      table.insert(found_files, upward_files[i])
    end

    -- Add home_claude_file last, if it exists and is not already added
    local home_claude_path = normalize_path(opts.home_claude_file)
    if home_claude_path and vim.fn.filereadable(home_claude_path) == 1 and not found_files_set[home_claude_path] then
      add_file(home_claude_path) -- add_file itself adds to found_files
    end

  elseif opts.search_strategy == "tool_operation" then
    if not opts.start_dir then
      vim.notify("find_claude_md_files: 'start_dir' is required for 'tool_operation' strategy", vim.log.levels.ERROR)
      return {}
    end
    local upward_files = search_upwards(opts.start_dir, stop_at)
    -- Add files from deepest to shallowest
    for i = 1, #upward_files do
      table.insert(found_files, upward_files[i])
    end
  else
    vim.notify("find_claude_md_files: Invalid search_strategy: " .. tostring(opts.search_strategy), vim.log.levels.ERROR)
    return {}
  end

  return found_files
end

return M
