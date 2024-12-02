local default_language = {
  code = "",
  technologies = "",
  guidelines = "",
  code_block_tags = {}
}

local ruby = "Ruby, Ruby on Rails, RSpec, Capybara"
local web = "HTML5, CSS3, JavaScript, Tailwind CSS"

local filetypes = {
  ruby = { code = "ruby", technologies = ruby, code_block_tags = { "ruby" } },
  eruby = { code = "erb", technologies = ruby .. ", " .. web, code_block_tags = { "erb" } },
  lua = { code = "lua", technologies = "Neovim, Lua 5.1, Busted", code_block_tags = { "lua" } },
  html = { code = "html", technologies = web, code_block_tags = { "html" } },
  javascript = { code = "js", technologies = web, code_block_tags = { "js", "javascript", "jsx", "ts", "typescript", "tsx" } },
  javascriptreact = { code = "jsx", technologies = "React, " .. web, code_block_tags = { "jsx", "js", "javascript" } },
  typescript = { code = "ts", technologies = "TypeScript, " .. web, code_block_tags = { "ts", "typescript", "js", "javascript", "jsx", "tsx" } },
  typescriptreact = { code = "tsx", technologies = "React, TypeScript, " .. web, code_block_tags = { "tsx", "ts", "typescript", "jsx", "js", "javascript" } },
  python = { code = "python", technologies = "Python, Pandas, NumPy, Scikit-learn", code_block_tags = { "python" } },
  go = { code = "go", technologies = "Go", code_block_tags = { "go" } },
  sh = { code = "bash", technologies = "Bash, GNU Core Utilities, fd, rg, jq", code_block_tags = { "sh", "bash" } },
  dart = { code = "dart", technologies = "Dart, Flutter, creating application for macOS and Windows", code_block_tags = { "dart" } },
}

local filetypes_mt = {
  __index = function(_, _)
    return default_language
  end
}

setmetatable(filetypes, filetypes_mt)

return filetypes
