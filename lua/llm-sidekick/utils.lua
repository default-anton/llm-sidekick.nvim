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

return M
