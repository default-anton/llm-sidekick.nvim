local file_operations = require("llm-sidekick.tools.file_operations")
local communication = require("llm-sidekick.tools.communication")

local tools = {}

vim.list_extend(tools, file_operations)
vim.list_extend(tools, communication)

return tools
