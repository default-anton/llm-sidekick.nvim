---Add a diagnostic entry for a modification block
---@param tool_call table Tool call object
---@param buf integer Buffer number
---@param lnum integer Starting line number (1-based)
---@param severity integer Diagnostic severity (vim.diagnostic.severity)
---@param message string Diagnostic message
---@return nil
local function add_tool_call(tool_call, buf, lnum, severity, message)
  local diagnostics = vim.diagnostic.get(buf, { namespace = vim.g.llm_sidekick_ns })
  local new_diagnostic = {
    lnum = lnum - 1,
    col = 0,
    severity = severity,
    message = message,
    user_data = { too_call_id = tool_call.id },
  }
  diagnostics = vim.tbl_filter(function(d) return d.user_data.tool_call_id ~= tool_call.id end, diagnostics)
  table.insert(diagnostics, new_diagnostic)
  vim.diagnostic.set(vim.g.llm_sidekick_ns, buf, diagnostics)
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

---Remove stale diagnostics that no longer correspond to existing modification blocks
---@param bufnr integer Buffer number
---@return nil
local function prune_stale(bufnr)
  local mod_blocks = require "llm-sidekick.file_editor".find_and_parse_modification_blocks(bufnr, 1, -1)
  local mod_block_hashes = {}
  for _, e in ipairs(mod_blocks) do
    mod_block_hashes[vim.fn.sha256(e.raw_block)] = e
  end

  local diagnostics = vim.diagnostic.get(bufnr, { namespace = vim.g.llm_sidekick_ns })
  diagnostics = vim.tbl_filter(function(d)
    local mod_block = mod_block_hashes[d.user_data.mod_block_sha256]
    if mod_block ~= nil then
      d.lnum = mod_block.start_line - 1
      d.end_lnum = mod_block.start_line - 1

      return true
    end

    return false
  end, diagnostics)
  vim.diagnostic.set(vim.g.llm_sidekick_ns, bufnr, diagnostics)
end

return {
  add_tool_call = add_tool_call,
  add_diagnostic = add_diagnostic,
  prune_stale = prune_stale,
}
