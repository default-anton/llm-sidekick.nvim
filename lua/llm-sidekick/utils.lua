local M = {}

M.complete_command = function(ArgLead, CmdLine, CursorPos)
  local args = vim.split(CmdLine, "%s+")
  local file_completions = vim.fn.getcompletion(ArgLead, 'file')
  local options = {}
  if vim.trim(ArgLead) ~= "" and #file_completions > 0 then
    options = file_completions
  end
  vim.list_extend(options, require("llm-sidekick.settings").get_aliases())
  vim.list_extend(options, { "tab", "vsplit", "split" })
  return vim.tbl_filter(function(item)
    return vim.startswith(item:lower(), ArgLead:lower()) and not vim.tbl_contains(args, item)
  end, options)
end

M.get_os_name = function()
  local os_name = vim.loop.os_uname().sysname
  if os_name == "Darwin" then
    return "macOS"
  elseif os_name == "Linux" then
    return "Linux"
  elseif os_name == "Windows_NT" then
    return "Windows"
  else
    return os_name
  end
end

---Convert a URL to a safe filename
---@param url string The URL to convert
---@return string The converted filename
function M.url_to_filename(url)
  -- Remove protocol (http:// or https://)
  local filename = url:gsub("^https?://", "")

  -- Replace common URL special characters with underscores
  filename = filename:gsub("[/?#&]", "_")

  -- Replace other unsafe filename characters
  filename = filename:gsub("[\\:%*\"<>|]", "_")

  -- Remove any consecutive underscores
  filename = filename:gsub("_+", "_")

  -- Remove trailing underscores
  filename = filename:gsub("_$", "")

  -- Remove leading underscores
  filename = filename:gsub("^_", "")

  return filename
end

---Get the temporary directory path
---@return string The path to the temporary directory with trailing separator
function M.get_temp_dir()
  -- Try system /tmp directory first
  local tmp_path = "/tmp"
  local stat = vim.loop.fs_stat(tmp_path)

  if stat and stat.type == "directory" then
    tmp_path = tmp_path .. "/llm-sidekick"
    vim.fn.mkdir(tmp_path, "p")
    return tmp_path
  end

  -- Fall back to the TMPDIR environment variable
  tmp_path = os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP")
  if tmp_path then
    stat = vim.loop.fs_stat(tmp_path)

    if stat and stat.type == "directory" then
      if vim.endswith(tmp_path, "/") then
        tmp_path = tmp_path .. "llm-sidekick"
      else
        tmp_path = tmp_path .. "/llm-sidekick"
      end

      vim.fn.mkdir(tmp_path, "p")
      return tmp_path
    end
  end

  tmp_path = vim.fn.tempname() .. "/llm-sidekick"
  vim.fn.mkdir(tmp_path, "p")

  return tmp_path
end

function M.log(msg, level)
  if type(msg) ~= "string" then
    msg = vim.inspect(msg)
  end

  local log_file = io.open(vim.g.llm_sidekick_log_path, "a")

  if not log_file then
    vim.notify(msg, level)
    return
  end

  -- Convert log level to string representation
  local level_str = "INFO"
  if level then
    if level == vim.log.levels.DEBUG then
      level_str = "DEBUG"
    elseif level == vim.log.levels.INFO then
      level_str = "INFO"
    elseif level == vim.log.levels.WARN then
      level_str = "WARN"
    elseif level == vim.log.levels.ERROR then
      level_str = "ERROR"
    end
  end

  log_file:write(string.format("%s [%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), level_str, msg))
  log_file:close()
end

function M.stop(buffer)
  pcall(vim.loop.kill, vim.b[buffer].llm_sidekick_job_pid, vim.loop.constants.SIGINT)
end

return M
