local chat = require("llm-sidekick.chat")
local Job = require('plenary.job')

local spec = {
  name = "ddg_search",
  description = "Search the web using DuckDuckGo and get the top results.",
  input_schema = {
    type = "object",
    properties = {
      query = {
        type = "string",
        description = "The search query to send to DuckDuckGo"
      }
    },
    required = { "query" }
  }
}

local json_props = string.format([[{
  "query": %s
}]], vim.json.encode(spec.input_schema.properties.query))

return {
  spec = spec,
  json_props = json_props,
  is_show_diagnostics = function() return true end,
  is_auto_acceptable = function()
    return true
  end,
  -- Initialize the search display
  start = function(tool_call, opts)
    chat.paste_at_end("**Searching DuckDuckGo:** ``", opts.buffer)
    tool_call.state.query_line = vim.api.nvim_buf_line_count(opts.buffer)
  end,
  -- Handle incremental updates for streaming query
  delta = function(tool_call, opts)
    local query = vim.trim(tool_call.parameters.query or "")
    local query_written = tool_call.state.query_written or 0

    -- Update query display
    if query and query_written < #query then
      vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.query_line - 1, tool_call.state.query_line, false,
        { string.format("**Searching DuckDuckGo:** `%s`", query) })
      tool_call.state.query_written = #query
    end
  end,
  -- Execute the search asynchronously
  run = function(tool_call, opts)
    local cwd = vim.fn.getcwd()
    local shell = vim.o.shell or "bash"
    local query = vim.trim(tool_call.parameters.query or "")
    if query == "" then
      return "Error: Empty search query"
    end

    tool_call.state.result = { success = false, result = nil }

    local command = string.format(
      'ddgr --num 5 --noprompt --noua --nocolor --expand --unsafe --json "%s"',
      vim.json.encode(query)
    )

    local job = Job:new({
      cwd = cwd,
      command = shell,
      args = { "-c", command },
      interactive = false,
      on_exit = function(j, return_val)
        local exit_code = return_val
        local output = ""

        local stdout = j:result()
        if stdout and not vim.tbl_isempty(stdout) then
          -- Try to parse JSON output for better formatting
          local json_output = table.concat(stdout, "\n")

          local success, results = pcall(vim.json.decode, json_output, { luanil = { object = true, array = true } })
          if success and type(results) == "table" then
            -- Format the results in a more readable way
            output = "Search Results:\n\n"
            for i, result in ipairs(results) do
              output = output .. string.format("**%d. [%s](%s)**\n", i, result.title, result.url)
              if result.abstract then
                output = output .. result.abstract .. "\n\n"
              end
            end
          else
            -- Fallback to raw output if JSON parsing fails
            output = "Results:\n````" .. json_output .. "````"
          end
        end

        local stderr = j:stderr_result()
        if stderr and not vim.tbl_isempty(stderr) then
          output = output .. "\n\nErrors:\n````" .. table.concat(stderr, "\n") .. "````"
        end

        -- Store the output in tool_call state for access in the after_success callback
        tool_call.state.result.success = exit_code == 0
        tool_call.state.result.result = string.format("Exit code: %d\n%s", exit_code, output)

        -- Update the search text to show it's completed
        vim.schedule(function()
          local status = tool_call.state.result.success and "✓" or "✗"
          local final_lines = { string.format("%s DuckDuckGo search: `%s`", status, query) }
          vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.lnum - 1, tool_call.state.end_lnum, false, final_lines)
        end)
      end,
    })

    return job
  end
}
