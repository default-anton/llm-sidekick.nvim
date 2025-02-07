---Add a diagnostic entry for a modification block
---@param buffer integer Buffer number
---@param lnum integer Starting line number (1-based)
---@param severity integer Diagnostic severity (vim.diagnostic.severity)
---@param message string Diagnostic message
---@return nil
local function add_tool_call(buffer, lnum, severity, message)
  local diagnostics = vim.diagnostic.get(buffer, { namespace = vim.g.llm_sidekick_ns })
  local new_diagnostic = {
    lnum = lnum - 1,
    col = 0,
    severity = severity,
    message = message,
  }
  diagnostics = vim.tbl_filter(function(d) return d.lnum ~= lnum end, diagnostics)
  table.insert(diagnostics, new_diagnostic)
  vim.diagnostic.set(vim.g.llm_sidekick_ns, buffer, diagnostics)
end

---Add a diagnostic entry for a modification block
---@param buf integer Buffer number
---@param lnum integer Starting line number (1-based)
---@param end_lnum integer Ending line number (1-based)
---@param raw_mod_block string Raw text of the modification block
---@param severity integer Diagnostic severity (vim.diagnostic.severity)
---@param message string Diagnostic message
---@return nil
local function add_diagnostic(buf, lnum, end_lnum, raw_mod_block, severity, message)
  -- local diagnostics = vim.diagnostic.get(buf, {
  --   namespace = vim.g.llm_sidekick_ns
  -- })
  -- local new_line = lnum - 1
  -- local new_diagnostic = {
  --   lnum = new_line,
  --   end_lnum = end_lnum - 1,
  --   col = 0,
  --   end_col = 0,
  --   severity = severity,
  --   message = message,
  --   user_data = { mod_block_sha256 = vim.fn.sha256(raw_mod_block) },
  -- }
  -- diagnostics = vim.tbl_filter(function(d) return d.lnum ~= new_line end, diagnostics)
  -- table.insert(diagnostics, new_diagnostic)
  -- vim.diagnostic.set(vim.g.llm_sidekick_ns, buf, diagnostics)
end

return {
  add_tool_call = add_tool_call,
  add_diagnostic = add_diagnostic,
}
