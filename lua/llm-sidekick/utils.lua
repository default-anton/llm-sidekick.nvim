local M = {}

local function complete_command(ArgLead, CmdLine, CursorPos)
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

M.complete_command = complete_command

return M
