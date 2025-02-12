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
  local start_line, end_line
  for i = cursor_line, 1, -1 do
    id, _ = buffer_lines[i]:match("<llm_sidekick_tool id=\"(.-)\" name=\"(.-)\">")
    if id then
      start_line = i + 1
      break
    end
  end

  if id == nil then
    vim.notify("No tool found under the cursor", vim.log.levels.ERROR)
    return
  end

  local close_tag_found = false
  for i = cursor_line, #buffer_lines do
    if buffer_lines[i]:match("^</llm_sidekick_tool>") then
      end_line = i - 1
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

    local ok, result = pcall(tool.run, tool_call.call, { buffer = buffer, start_lnum = start_line, end_lnum = end_line })

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
  local current_start_line, current_end_line

  for i = 1, #buffer_lines do
    local id, _ = buffer_lines[i]:match("<llm_sidekick_tool id=\"(.-)\" name=\"(.-)\">")

    if id then
      current_id = id
      current_start_line = i + 1
    elseif current_id and buffer_lines[i]:match("^</llm_sidekick_tool>") then
      current_end_line = i - 1

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

        local ok, result = xpcall(
          tool.run,
          debug_error_handler,
          tool_call.call,
          { buffer = buffer, start_lnum = current_start_line, end_lnum = current_end_line }
        )

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

        ::continue::
      end
      current_id = nil
      current_start_line = nil
      current_end_line = nil
    end
  end
end

local function get_tool_calls_in_last_assistant_message(opts)
  local buffer = opts.buffer
  local buffer_lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local last_assistant_start_line = require('llm-sidekick.file_editor').find_last_assistant_start_line(buffer_lines)
  if last_assistant_start_line == -1 then
    error("ASSISTANT message not found")
  end

  local tool_calls = {}
  local current_tool_call = nil

  for i = last_assistant_start_line, #buffer_lines do
    local id, _ = buffer_lines[i]:match("<llm_sidekick_tool id=\"(.-)\" name=\"(.-)\">")

    if id then
      current_tool_call = find_tool_call_by_id(id, { buffer = buffer })
      if current_tool_call then
        current_tool_call.call.tool = find_tool_for_tool_call(current_tool_call.call)
      end
    elseif current_tool_call and buffer_lines[i]:match("^</llm_sidekick_tool>") then
      table.insert(tool_calls, current_tool_call.call)
    end
  end

  return tool_calls
end

return {
  find_tool_call_by_id = find_tool_call_by_id,
  run_tool_call_at_cursor = run_tool_call_at_cursor,
  run_all_tool_calls = run_all_tool_calls,
  add_tool_call_to_buffer = add_tool_call_to_buffer,
  update_tool_call_in_buffer = update_tool_call_in_buffer,
  find_tool_for_tool_call = find_tool_for_tool_call,
  get_tool_calls_in_last_assistant_message = get_tool_calls_in_last_assistant_message,
}
