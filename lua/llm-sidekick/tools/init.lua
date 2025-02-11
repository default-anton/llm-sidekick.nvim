local scratchpad = require("llm-sidekick.tools.scratchpad")
local communication = require("llm-sidekick.tools.communication")
local file_operations = require("llm-sidekick.tools.file_operations")

local tools = { scratchpad }
vim.list_extend(tools, communication)
vim.list_extend(tools, file_operations)

return tools
