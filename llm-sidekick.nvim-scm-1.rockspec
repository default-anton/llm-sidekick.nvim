rockspec_format = "3.0"
package = "llm-sidekick.nvim"
version = 'scm-1'

description = {
  summary = "Fast and hackable code companion for Neovim",
  detailed = "The missing code companion for Neovim. Fast, hackable, and stays out of your way",
  labels = { "neovim", "plugin" },
  homepage = "https://github.com/default-anton/llm-sidekick.nvim",
}

dependencies = {
  "lua >= 5.1, < 5.4",
  "plenary.nvim",
}

test_dependencies = {
  'lua >= 5.1',
  'nlua',
}

source = {
  url = "git://github.com/default-anton/llm-sidekick.nvim",
}

build = {
  type = 'builtin'
}
