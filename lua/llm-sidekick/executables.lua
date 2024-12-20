local M = {}

function M.get_curl_executable()
  return vim.fn.executable('curl') == 1 and 'curl' or error('curl not found')
end

function M.get_jq_executable()
  return vim.fn.executable('jq') == 1 and 'jq' or error('jq executable not found')
end

function M.get_sttbuff_executable()
  if vim.fn.executable('sttbuff') == 1 then
    return 'sttbuff'
  end

  if vim.fn.has('mac') == 1 and vim.fn.executable('gstdbuf') == 1 then
    return 'gstdbuf'
  end

  error('sttbuff executable not found')
end

return M
