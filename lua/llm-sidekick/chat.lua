local function paste_at_end(text)
  local line_count = vim.api.nvim_buf_line_count(0)
  local last_line = vim.api.nvim_buf_get_lines(0, -2, -1, false)[1] or ""
  vim.api.nvim_win_set_cursor(0, { line_count, #last_line })
  vim.api.nvim_paste(text, false, 2)
end

return {
  paste_at_end = paste_at_end,
}
