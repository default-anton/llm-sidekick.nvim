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
  return expand_home(path)
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

---Find project instruction files based on different strategies.
---@param opts table Options table:
---  - buf (number): Buffer number
---  - start_dir (string): Directory to start search from (for "tool_operation")
---  - stop_at_dir (string): Directory path to stop ascending
---@return table A list of unique absolute paths to found project instruction files.
function M.find_project_instruction_files(opts)
  local settings = require("llm-sidekick.settings")

  local found_files = {}
  local found_files_set = {}
  for _, file in ipairs(vim.b[opts.buf].project_instruction_files or {}) do
    found_files_set[file] = true
  end

  if not opts.start_dir then
    vim.notify("find_project_instruction_files: 'start_dir' is required", vim.log.levels.ERROR)
    return {}
  end

  local instruction_filenames = settings.get_instruction_filenames()

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
      return {}         -- Cannot proceed without a valid stop_at
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

      for _, filename in ipairs(instruction_filenames) do
        local instruction_file_path = current_dir .. "/" .. filename
        -- Check if the file exists and is a file (not a directory)
        if vim.fn.filereadable(instruction_file_path) == 1 and not is_dir(instruction_file_path) then
          add_file(instruction_file_path)
        end
      end

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

  search_upwards(opts.start_dir, stop_at)

  for _, filename in ipairs(instruction_filenames) do
    for _, home_config_dir in ipairs({ '~/.llm-sidekick/', '~/.claude/', '~/.config/llm-sidekick/' }) do
      local home_instruction_path = normalize_path(home_config_dir .. filename)
      if home_instruction_path and vim.fn.filereadable(home_instruction_path) == 1 and not is_dir(home_instruction_path) then
        add_file(home_instruction_path)
      end
    end
  end

  vim.b[opts.buf].project_instruction_files = vim.list_extend(vim.b[opts.buf].project_instruction_files or {},
    found_files)

  return found_files
end

return M
