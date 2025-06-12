local scratchpad = require("llm-sidekick.tools.scratchpad")
local file_operations = require("llm-sidekick.tools.file_operations")
local terminal = require("llm-sidekick.tools.terminal")
local delegate_task = require("llm-sidekick.tools.delegate_task")

local tools = { scratchpad }
table.insert(tools, delegate_task) -- Add delegate_task tool
vim.list_extend(tools, file_operations)
vim.list_extend(tools, terminal)

return tools
