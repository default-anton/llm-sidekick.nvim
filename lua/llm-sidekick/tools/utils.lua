local diagnostic = require("llm-sidekick.diagnostic")
local file_operations = require('llm-sidekick.tools.file_operations')

local function find_tool_for_tool_call(tool_call)
  local found_tools = vim.tbl_filter(function(tool) return tool.spec.name == tool_call.name end, file_operations)
  if #found_tools == 0 then
    return nil
  end

  return found_tools[1]
end

local function run_tool_at_cursor(opts)
  local prompt_buffer = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local buffer_lines = vim.api.nvim_buf_get_lines(prompt_buffer, 0, -1, false)
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

    if tool_call.result then
      goto continue
    end

    local tool = find_tool_for_tool_call(tool_call.call)
    if not tool then
      diagnostic.add_tool_call(
        tool_call.call,
        prompt_buffer,
        tool_call.lnum,
        vim.diagnostic.severity.ERROR,
        string.format("✗ %s: Tool not found", tool_call.call.name)
      )
      return
    end

    if tool.run == nil then
      diagnostic.add_tool_call(
        tool_call.call,
        prompt_buffer,
        tool_call.lnum,
        vim.diagnostic.severity.ERROR,
        string.format("✗ %s: No run function defined", tool_call.call.name)
      )
      return
    end

    local debug_mode = os.getenv("LLM_SIDEKICK_DEBUG") == "true"
    local ok, result
    if debug_mode then
      local debug_error_handler = function(err)
        return debug.traceback(err, 2)
      end
      ok, result = xpcall(tool.run, debug_error_handler, tool_call.call, { buffer = prompt_buffer })
    else
      ok, result = pcall(tool.run, tool_call.call, { buffer = prompt_buffer })
    end
    if ok then
      local new_tool_calls = vim.b[opts.buffer].llm_sidekick_tool_calls
      for _, tc in ipairs(new_tool_calls) do
        if tc.call.id == tool_call.call.id then
          tc.result = result
        end
      end
      vim.b[opts.buffer].llm_sidekick_tool_calls = new_tool_calls

      diagnostic.add_tool_call(
        tool_call.call,
        prompt_buffer,
        tool_call.lnum,
        vim.diagnostic.severity.INFO,
        string.format("✓ %s", tool_call.call.name)
      )
    else
      diagnostic.add_tool_call(
        tool_call.call,
        prompt_buffer,
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

local function run_all_tools(opts)
  local prompt_buffer = opts.buffer or vim.api.nvim_get_current_buf()
  local buffer_lines = vim.api.nvim_buf_get_lines(prompt_buffer, 0, -1, false)
  local current_id = nil
  local tool_calls_processed = 0

  for i = 1, #buffer_lines do
    local id, _ = buffer_lines[i]:match("^<llm_sidekick_tool id=\"(.-)\" name=\"(.-)\">")

    if id then
      current_id = id
    elseif current_id and buffer_lines[i]:match("^</llm_sidekick_tool>") then
      for _, tool_call in ipairs(vim.b[prompt_buffer].llm_sidekick_tool_calls) do
        if tool_call.call.id ~= current_id then
          goto continue
        end

        if tool_call.result then
          goto continue
        end

        local tool = find_tool_for_tool_call(tool_call.call)
        if not tool then
          diagnostic.add_tool_call(
            tool_call.call,
            prompt_buffer,
            tool_call.lnum,
            vim.diagnostic.severity.ERROR,
            string.format("✗ %s: Tool not found", tool_call.call.name)
          )
          goto continue
        end

        if tool.run == nil then
          diagnostic.add_tool_call(
            tool_call.call,
            prompt_buffer,
            tool_call.lnum,
            vim.diagnostic.severity.ERROR,
            string.format("✗ %s: No run function defined", tool_call.call.name)
          )
          goto continue
        end

        local debug_mode = os.getenv("DEBUG") == "true"
        local ok, result
        if debug_mode then
          local debug_error_handler = function(err)
            return debug.traceback(err, 2)
          end
          ok, result = xpcall(tool.run, debug_error_handler, tool_call.call, { buffer = prompt_buffer })
        else
          ok, result = pcall(tool.run, tool_call.call, { buffer = prompt_buffer })
        end

        if ok then
          local new_tool_calls = vim.b[prompt_buffer].llm_sidekick_tool_calls
          for _, tc in ipairs(new_tool_calls) do
            if tc.call.id == tool_call.call.id then
              tc.result = result
            end
          end
          vim.b[prompt_buffer].llm_sidekick_tool_calls = new_tool_calls

          diagnostic.add_tool_call(
            tool_call.call,
            prompt_buffer,
            tool_call.lnum,
            vim.diagnostic.severity.INFO,
            string.format("✓ %s", tool_call.call.name)
          )
        else
          diagnostic.add_tool_call(
            tool_call.call,
            prompt_buffer,
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
  run_tool_at_cursor = run_tool_at_cursor,
  run_all_tools = run_all_tools,
  add_tool_call_to_buffer = add_tool_call_to_buffer,
  update_tool_call_in_buffer = update_tool_call_in_buffer,
  find_tool_for_tool_call = find_tool_for_tool_call,
}
