local function paste_at_end(text, bufnr)
  if text == "" then return end

  local last_line = vim.api.nvim_buf_get_lines(bufnr, -2, -1, false)[1] or ""
  local lines = vim.split(text, "\n", { plain = true })
  local new_last_line = last_line .. lines[1]
  vim.api.nvim_buf_set_lines(bufnr, -2, -1, false, { new_last_line })

  -- If there are more lines, append them
  if #lines > 1 then
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, vim.list_slice(lines, 2))
  end
end

return {
  paste_at_end = paste_at_end,
}
