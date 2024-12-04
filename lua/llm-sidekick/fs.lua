local M = {}

---Read the entire contents of a file
---@param path string The path to the file to read
---@return string|nil content The file contents or nil if file cannot be opened
function M.read_file(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local content = file:read("*all")
  file:close()
  return content
end

return M
