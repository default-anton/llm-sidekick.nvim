local function clear(bufnr, group)
  vim.fn.sign_unplace(group, { buffer = bufnr })
end

local function place(bufnr, group, start_line, end_line, sign_name)
  for lnum = start_line, end_line do
    vim.fn.sign_place(0, group, sign_name, bufnr, { lnum = lnum })
  end
end

return {
  clear = clear,
  place = place,
}
