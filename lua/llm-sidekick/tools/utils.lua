local diagnostic = require("llm-sidekick.diagnostic")
local built_in_tools = require("llm-sidekick.tools")
local file_editor = require("llm-sidekick.file_editor")

local function find_tool_for_tool_call(tool_call)
  for _, tool in ipairs(built_in_tools) do
    if tool.spec.name == tool_call.name then
      return tool
    end
  end
end

local function find_tool_call_by_id(tool_id, opts)
  for _, tool_call in ipairs(vim.b[opts.buffer].llm_sidekick_tool_calls or {}) do
    if tool_call.id == tool_id then
      return tool_call
    end
  end
end

local function find_tool_call_by_extmark_id(extmark_id, opts)
  for _, tool_call in ipairs(vim.b[opts.buffer].llm_sidekick_tool_calls or {}) do
    if tool_call.state.extmark_id == extmark_id then
      return tool_call
    end
  end
end

local function refresh_tool_call_lnums(tool_call, opts)
  local buffer = opts.buffer
  local row, _, details = unpack(vim.api.nvim_buf_get_extmark_by_id(
    buffer,
    vim.g.llm_sidekick_ns,
    tool_call.state.extmark_id,
    { details = true }
  ))

  if not details or details.invalid then
    return
  end

  local line_count = tool_call.state.end_lnum - tool_call.state.lnum
  tool_call.state.lnum = row + 1
  tool_call.state.end_lnum = math.max(tool_call.state.lnum + line_count, tool_call.state.lnum)

  return tool_call
end

local function update_tool_call_in_buffer(opts)
  local updated_tool_calls = vim.b[opts.buffer].llm_sidekick_tool_calls or {}
  for i, tc in ipairs(updated_tool_calls) do
    if tc.id == opts.tool_call.id then
      updated_tool_calls[i] = opts.tool_call
      break
    end
  end
  vim.b[opts.buffer].llm_sidekick_tool_calls = updated_tool_calls
end

local update_diagnostic = function(tool_call, opts)
  local buffer = opts.buffer

  if not tool_call.tool.is_show_diagnostics(tool_call) then
    return
  end

  if not tool_call.result then
    diagnostic.add_tool_call(
      tool_call,
      buffer,
      vim.diagnostic.severity.HINT,
      string.format("▶ %s (<leader>aa)", tool_call.name)
    )
  elseif tool_call.result.success then
    diagnostic.add_tool_call(
      tool_call,
      buffer,
      vim.diagnostic.severity.INFO,
      string.format("✓ %s", tool_call.name)
    )
  else
    diagnostic.add_tool_call(
      tool_call,
      buffer,
      vim.diagnostic.severity.ERROR,
      string.format("✗ %s: %s", tool_call.name, vim.inspect(tool_call.result.result))
    )
  end
end

local function run_tool_call(tool_call, opts)
  if tool_call.result then
    return
  end

  local buffer = opts.buffer
  if not tool_call.tool then
    tool_call.tool = find_tool_for_tool_call(tool_call)
  end

  if tool_call.tool.run == nil then
    diagnostic.add_tool_call(
      tool_call,
      buffer,
      vim.diagnostic.severity.ERROR,
      string.format("✗ %s: No run function defined", tool_call.name)
    )
    return
  end

  local line_count_before = vim.api.nvim_buf_line_count(buffer)

  local ok, result = pcall(tool_call.tool.run, tool_call, { buffer = buffer })
  tool_call.result = { success = ok, result = result }

  local line_count_after = vim.api.nvim_buf_line_count(buffer)
  if line_count_before ~= line_count_after then
    tool_call.state.end_lnum = math.max(
      tool_call.state.lnum + (line_count_after - line_count_before),
      tool_call.state.lnum
    )
  end

  vim.api.nvim_buf_set_extmark(
    buffer,
    vim.g.llm_sidekick_ns,
    tool_call.state.lnum - 1,
    0,
    { id = tool_call.state.extmark_id, invalidate = true }
  )

  update_tool_call_in_buffer({ buffer = buffer, tool_call = tool_call })
  update_diagnostic(tool_call, { buffer = buffer })
end

local function add_tool_call_to_buffer(opts)
  local tool_calls = vim.b[opts.buffer].llm_sidekick_tool_calls or {}
  vim.b[opts.buffer].llm_sidekick_tool_calls = vim.list_extend(tool_calls, { opts.tool_call })
end

local function find_tool_calls(opts)
  local buffer = opts.buffer
  local tool_calls = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buffer, vim.g.llm_sidekick_ns, 0, -1, { details = true })) do
    local extmark_id, row, _, details = unpack(mark)

    if details and details.invalid then
      goto continue
    end

    local tool_call = find_tool_call_by_extmark_id(extmark_id, { buffer = buffer })
    if tool_call then
      tool_call.tool = find_tool_for_tool_call(tool_call)
      local line_count = tool_call.state.end_lnum - tool_call.state.lnum
      tool_call.state.lnum = row + 1
      tool_call.state.end_lnum = math.max(tool_call.state.lnum + line_count, tool_call.state.lnum)
      table.insert(tool_calls, tool_call)
    end

    ::continue::
  end

  return tool_calls
end

local function get_tool_calls_in_last_assistant_message(opts)
  local buffer = opts.buffer
  local buffer_lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local last_assistant_start_line = opts.lnum or file_editor.find_last_assistant_start_line(buffer_lines)

  if last_assistant_start_line == -1 then
    error("No \"ASSISTANT:\" message found")
  end

  local tool_calls = find_tool_calls({ buffer = buffer })
  return vim.tbl_filter(
    function(tc) return tc.state.lnum >= last_assistant_start_line end,
    tool_calls
  )
end

local function run_tool_call_at_cursor(opts)
  local buffer = opts.buffer
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local tool_call_at_cursor

  for _, tool_call in ipairs(find_tool_calls({ buffer = buffer })) do
    if cursor_line >= tool_call.state.lnum and cursor_line <= tool_call.state.end_lnum then
      tool_call_at_cursor = tool_call
      run_tool_call(tool_call, { buffer = buffer })
      break
    end
  end

  if not tool_call_at_cursor then
    error("No tool found under the cursor")
  end

  local tool_calls = get_tool_calls_in_last_assistant_message({ buffer = buffer })
  -- Run auto-acceptable tool calls after the tool call at the cursor
  local found_tool_call_at_cursor = false
  for _, tool_call in ipairs(tool_calls) do
    if tool_call_at_cursor.id == tool_call.id then
      found_tool_call_at_cursor = true
    elseif found_tool_call_at_cursor then
      if tool_call.tool.is_auto_acceptable(tool_call) then
        run_tool_call(tool_call, { buffer = buffer })
      else
        update_diagnostic(tool_call, { buffer = buffer })
        found_tool_call_at_cursor = false
      end
    else
      update_diagnostic(tool_call, { buffer = buffer })
    end
  end
end

local function run_tool_calls_in_last_assistant_message(opts)
  for _, tool_call in ipairs(get_tool_calls_in_last_assistant_message({ buffer = opts.buffer })) do
    tool_call = refresh_tool_call_lnums(tool_call, { buffer = opts.buffer })
    if tool_call then
      run_tool_call(tool_call, { buffer = opts.buffer })
    end
  end
end

return {
  run_tool_call = run_tool_call,
  find_tool_calls = find_tool_calls,
  find_tool_call_by_id = find_tool_call_by_id,
  run_tool_call_at_cursor = run_tool_call_at_cursor,
  run_tool_calls_in_last_assistant_message = run_tool_calls_in_last_assistant_message,
  add_tool_call_to_buffer = add_tool_call_to_buffer,
  update_tool_call_in_buffer = update_tool_call_in_buffer,
  find_tool_for_tool_call = find_tool_for_tool_call,
  get_tool_calls_in_last_assistant_message = get_tool_calls_in_last_assistant_message,
}
