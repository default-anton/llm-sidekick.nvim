local diagnostic = require("llm-sidekick.diagnostic")
local built_in_tools = require("llm-sidekick.tools")

local function find_tool_for_tool_call(tool_call)
  local found_tools = vim.tbl_filter(function(tool) return tool.spec.name == tool_call.name end, built_in_tools)
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

local debug_error_handler = function(err)
  return debug.traceback(err, 3)
end

local function run_tool_call_at_cursor(opts)
  local buffer = opts.buffer
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local buffer_lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local id
  for i = cursor_line, 1, -1 do
    id, _ = buffer_lines[i]:match("^<llm_sidekick_tool id=\"(.-)\" name=\"(.-)\">")
    if id then break end
  end

  if id == nil then
    vim.notify("No tool found under the cursor", vim.log.levels.ERROR)
    return
  end

  local close_tag_found = false
  for i = cursor_line, #buffer_lines do
    if buffer_lines[i]:match("^</llm_sidekick_tool>") then
      close_tag_found = true
      break
    end
  end

  if not close_tag_found then
    vim.notify("No tool found under the cursor", vim.log.levels.ERROR)
    return
  end

  local tool_call_found = false
  for _, tool_call in ipairs(vim.b[opts.buffer].llm_sidekick_tool_calls) do
    if tool_call.call.id ~= id then
      goto continue
    end

    tool_call_found = true

    if tool_call.call.result then
      goto continue
    end

    local tool = find_tool_for_tool_call(tool_call.call)
    if not tool then
      diagnostic.add_tool_call(
        tool_call.call,
        buffer,
        tool_call.lnum,
        vim.diagnostic.severity.ERROR,
        string.format("✗ %s: not found", tool_call.call.name)
      )
      return
    end

    if tool.run == nil then
      diagnostic.add_tool_call(
        tool_call.call,
        buffer,
        tool_call.lnum,
        vim.diagnostic.severity.ERROR,
        string.format("✗ %s: No run function defined", tool_call.call.name)
      )
      return
    end

    local ok, result = pcall(tool.run, tool_call.call, { buffer = buffer })

    local new_tool_calls = vim.b[opts.buffer].llm_sidekick_tool_calls
    for _, tc in ipairs(new_tool_calls) do
      if tc.call.id == tool_call.call.id then
        tc.call.result = {
          success = ok,
          result = result,
        }
      end
    end
    vim.b[opts.buffer].llm_sidekick_tool_calls = new_tool_calls

    if ok then
      diagnostic.add_tool_call(
        tool_call.call,
        buffer,
        tool_call.lnum,
        vim.diagnostic.severity.INFO,
        string.format("✓ %s", tool_call.call.name)
      )
    else
      diagnostic.add_tool_call(
        tool_call.call,
        buffer,
        tool_call.lnum,
        vim.diagnostic.severity.ERROR,
        string.format("✗ %s: %s", tool_call.call.name, vim.inspect(result))
      )
    end

    ::continue::
  end

  if not tool_call_found then
    vim.notify("No tool call found under the cursor", vim.log.levels.ERROR)
  end
end

local function add_tool_call_to_buffer(opts)
  local tool_calls = vim.b[opts.buffer].llm_sidekick_tool_calls or {}
  vim.b[opts.buffer].llm_sidekick_tool_calls = vim.list_extend(tool_calls, {
    { call = opts.tool_call, lnum = opts.lnum }
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
  local current_id = nil
  local tool_calls_processed = 0

  for i = 1, #buffer_lines do
    local id, _ = buffer_lines[i]:match("^<llm_sidekick_tool id=\"(.-)\" name=\"(.-)\">")

    if id then
      current_id = id
    elseif current_id and buffer_lines[i]:match("^</llm_sidekick_tool>") then
      for _, tool_call in ipairs(vim.b[buffer].llm_sidekick_tool_calls) do
        if tool_call.call.id ~= current_id then
          goto continue
        end

        if tool_call.call.result then
          goto continue
        end

        local tool = find_tool_for_tool_call(tool_call.call)
        if not tool then
          diagnostic.add_tool_call(
            tool_call.call,
            buffer,
            tool_call.lnum,
            vim.diagnostic.severity.ERROR,
            string.format("✗ %s: not found", tool_call.call.name)
          )
          goto continue
        end

        if tool.run == nil then
          diagnostic.add_tool_call(
            tool_call.call,
            buffer,
            tool_call.lnum,
            vim.diagnostic.severity.ERROR,
            string.format("✗ %s: No run function defined", tool_call.call.name)
          )
          goto continue
        end

        local ok, result = xpcall(tool.run, debug_error_handler, tool_call.call, { buffer = buffer })

        if ok then
          local new_tool_calls = vim.b[buffer].llm_sidekick_tool_calls
          for _, tc in ipairs(new_tool_calls) do
            if tc.call.id == tool_call.call.id then
              tc.call.result = result
            end
          end
          vim.b[buffer].llm_sidekick_tool_calls = new_tool_calls

          diagnostic.add_tool_call(
            tool_call.call,
            buffer,
            tool_call.lnum,
            vim.diagnostic.severity.INFO,
            string.format("✓ %s", tool_call.call.name)
          )
        else
          diagnostic.add_tool_call(
            tool_call.call,
            buffer,
            tool_call.lnum,
            vim.diagnostic.severity.ERROR,
            string.format("✗ %s: %s", tool_call.call.name, vim.inspect(result))
          )
        end

        tool_calls_processed = tool_calls_processed + 1
        ::continue::
      end
      current_id = nil
    end
  end
end

return {
  find_tool_call_by_id = find_tool_call_by_id,
  run_tool_call_at_cursor = run_tool_call_at_cursor,
  run_all_tool_calls = run_all_tool_calls,
  add_tool_call_to_buffer = add_tool_call_to_buffer,
  update_tool_call_in_buffer = update_tool_call_in_buffer,
  find_tool_for_tool_call = find_tool_for_tool_call,
}
