local diagnostic = require("llm-sidekick.diagnostic")
local file_operations = require('llm-sidekick.tools.file_operations')

local function find_tool_for_tool_call(tool_call)
  local found_tools = vim.tbl_filter(function(tool) return tool.spec.name == tool_call.name end, file_operations)
  if #found_tools == 0 then
    return nil
  end

  return found_tools[1]
end

local function find_tool_call_by_id(tool_id, opts)
  local found_tools = vim.tbl_filter(
    function(tool) return tool.call.id == tool_id end,
    vim.b[opts.buffer].llm_sidekick_tool_calls
  )
  if #found_tools == 0 then
    return nil
  end
  return found_tools[1]
end

local function run_tool_call_at_cursor(opts)
  local buffer = opts.buffer
  local buffer_lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)

  local start_line = 1
  for i = #buffer_lines, 1, -1 do
    if buffer_lines[i]:match("^ASSISTANT:") then
      start_line = i
      break
    end
  end

  for _, tool in ipairs(file_operations) do
    local debug_error_handler = function(err)
      return debug.traceback(err, 3)
    end

    local ok, result = xpcall(
      tool.on_user_accept,
      debug_error_handler,
      { buffer = buffer, start_search_line = start_line, end_search_line = #buffer_lines }
    )

    if ok then
      if result and result.error then
        diagnostic.add_tool_call(
          buffer,
          result.start_line,
          vim.diagnostic.severity.ERROR,
          string.format("✗ %s: %s", tool.diagnostic_name, result.error)
        )
      elseif result then
        diagnostic.add_tool_call(
          buffer,
          result.start_line,
          vim.diagnostic.severity.INFO,
          string.format("✓ %s", tool.diagnostic_name)
        )
      end
    else
      vim.notify(string.format("✗ %s: %s", tool.diagnostic_name, vim.inspect(result)), vim.log.levels.ERROR)
    end
  end
end

local function add_tool_call_to_buffer(opts)
  local tool_calls = vim.b[opts.buffer].llm_sidekick_tool_calls or {}
  vim.b[opts.buffer].llm_sidekick_tool_calls = vim.list_extend(tool_calls, {
    { call = opts.tool_call, lnum = opts.lnum, result = opts.result }
  })
end

local function update_tool_call_in_buffer(opts)
  local tool_calls = vim.b[opts.buffer].llm_sidekick_tool_calls or {}
  local updated_tool_calls = {}
  for _, tool_call_data in ipairs(tool_calls) do
    if tool_call_data.call.id == opts.tool_call.id then
      table.insert(updated_tool_calls, {
        call = opts.tool_call,
        lnum = tool_call_data.lnum,
        result = opts.result
      })
    else
      table.insert(updated_tool_calls, tool_call_data)
    end
  end
  vim.b[opts.buffer].llm_sidekick_tool_calls = updated_tool_calls
end

local function run_all_tool_calls(opts)
  local buffer = opts.buffer
  local buffer_lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)

  local start_line = 1
  for i = #buffer_lines, 1, -1 do
    if buffer_lines[i]:match("^ASSISTANT:") then
      start_line = i
      break
    end
  end

  for _, tool in ipairs(file_operations) do
    local debug_error_handler = function(err)
      return debug.traceback(err, 3)
    end

    local ok, results = xpcall(
      tool.on_user_accept_all,
      debug_error_handler,
      { buffer = buffer, start_search_line = start_line, end_search_line = #buffer_lines }
    )

    if not ok then
      vim.notify(string.format("✗ %s: %s", tool.diagnostic_name, vim.inspect(results)), vim.log.levels.ERROR)
      goto continue
    end

    for _, result in ipairs(results) do
      if result.error then
        diagnostic.add_tool_call(
          buffer,
          result.start_line,
          vim.diagnostic.severity.ERROR,
          string.format("✗ %s: %s", tool.diagnostic_name, result.error)
        )
      else
        diagnostic.add_tool_call(
          buffer,
          result.start_line,
          vim.diagnostic.severity.INFO,
          string.format("✓ %s", tool.diagnostic_name)
        )
      end
    end

    ::continue::
  end
end

local function on_assistant_turn_end(opts)
  local buffer = opts.buffer
  local buffer_lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)

  local start_line = 1
  for i = #buffer_lines, 1, -1 do
    if buffer_lines[i]:match("^ASSISTANT:") then
      start_line = i
      break
    end
  end

  for _, tool in ipairs(file_operations) do
    local debug_error_handler = function(err)
      return debug.traceback(err, 3)
    end

    local ok, results = xpcall(
      tool.on_assistant_turn_end,
      debug_error_handler,
      { buffer = buffer, start_search_line = start_line, end_search_line = #buffer_lines }
    )

    if not ok then
      vim.notify(string.format("✗ %s: %s", tool.diagnostic_name, vim.inspect(results)), vim.log.levels.ERROR)
      goto continue
    end

    for _, result in ipairs(results) do
      diagnostic.add_tool_call(
        buffer,
        result.start_line,
        vim.diagnostic.severity.HINT,
        string.format("▶ %s", tool.diagnostic_name)
      )
    end

    ::continue::
  end
end

return {
  find_tool_call_by_id = find_tool_call_by_id,
  run_tool_call_at_cursor = run_tool_call_at_cursor,
  run_all_tool_calls = run_all_tool_calls,
  add_tool_call_to_buffer = add_tool_call_to_buffer,
  update_tool_call_in_buffer = update_tool_call_in_buffer,
  find_tool_for_tool_call = find_tool_for_tool_call,
  on_assistant_turn_end = on_assistant_turn_end,
}
