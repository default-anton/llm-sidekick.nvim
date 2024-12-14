local M = {}

---Read the entire contents of a file
---@param path string The path to the file to read
---@return string|nil content The file contents or nil if file cannot be opened
function M.read_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then return nil end
  return table.concat(lines, "\n")
end

return M
