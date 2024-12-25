local M = {}

function M.get_curl_executable()
  return vim.fn.executable('curl') == 1 and 'curl' or error('curl not found')
end

return M
