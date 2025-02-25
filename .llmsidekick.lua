local lsk = require("llm-sidekick")

local guidelines = [[
To run a single test file: `ntest lua/llm-sidekick/spec/sjson_spec.lua`.
To run all tests: `make test`.
Linter: `make lint`.
When working with Lua, you will:
- Use `vim.api` for Neovim API calls
- Prefer `vim.keymap.set()` for keymappings
- Use `vim.opt` for setting options
- Use appropriate vim.* namespaces for different types of Vim functionality:
  - `vim.fn` for calling most VimL functions
  - `vim.api` for Neovim API functions
  - `vim.lsp` for built-in LSP functionality
  - `vim.treesitter` for tree-sitter operations
  - `vim.cmd()` for executing VimL commands when necessary
  - `vim.*` for other built-in Vim functions
]]

local technologies = [[
- Neovim (0.11)
- Plenary.nvim
- Lua 5.1
- LuaJIT
- Luacheck (for linting)]]

return {
  guidelines = guidelines,
  technologies = technologies,
}
