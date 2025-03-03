local scratchpad = require("llm-sidekick.tools.scratchpad")
local communication = require("llm-sidekick.tools.communication")
local file_operations = require("llm-sidekick.tools.file_operations")
local terminal = require("llm-sidekick.tools.terminal")

local tools = { scratchpad }
vim.list_extend(tools, communication)
vim.list_extend(tools, file_operations)
vim.list_extend(tools, terminal)

return tools
