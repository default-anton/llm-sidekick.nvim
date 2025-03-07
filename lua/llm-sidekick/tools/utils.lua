local diagnostic = require("llm-sidekick.diagnostic")
local built_in_tools = require("llm-sidekick.tools")
local file_editor = require("llm-sidekick.file_editor")

local M = {}

-- Queue management functions
local function initialize_tool_queue(buffer)
  if not vim.b[buffer].llm_sidekick_tool_queue then
    vim.b[buffer].llm_sidekick_tool_queue = {
      pending = {},
      running = false,
    }
  end
  return vim.b[buffer].llm_sidekick_tool_queue
end

M.add_completion_callback = function(buffer, callback)
  local queue = initialize_tool_queue(buffer)

  if not queue.completion_callbacks then
    queue.completion_callbacks = {}
  end

  table.insert(queue.completion_callbacks, callback)
  vim.b[buffer].llm_sidekick_tool_queue = queue
end

M.queue_tool_call = function(tool_call, opts)
  if tool_call.result then
    return
  end

  if not tool_call.tool then
    tool_call.tool = M.find_tool_for_tool_call(tool_call)
  end

  local buffer = opts.buffer
  local queue = initialize_tool_queue(buffer)

  table.insert(queue.pending, {
    tool_call = tool_call,
    opts = opts,
  })
  vim.b[buffer].llm_sidekick_tool_queue = queue

  return queue
end

local update_diagnostic = function(tool_call, opts)
  local buffer = opts.buffer

  if not tool_call.tool.is_show_diagnostics(tool_call) then
    return
  end

  if not tool_call.result then
    if tool_call.state and tool_call.state.is_running then
      diagnostic.add_tool_call(
        tool_call,
        buffer,
        vim.diagnostic.severity.HINT,
        string.format("⟳ %s (running...)", tool_call.name)
      )
    else
      diagnostic.add_tool_call(
        tool_call,
        buffer,
        vim.diagnostic.severity.HINT,
        string.format("▶ %s (<leader>aa)", tool_call.name)
      )
    end
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

M.process_next_in_queue = function(buffer)
  local queue = vim.b[buffer].llm_sidekick_tool_queue

  if not queue or queue.running then
    return
  end

  if #queue.pending == 0 then
    -- Check if there are any completion callbacks
    if queue.completion_callbacks and #queue.completion_callbacks > 0 then
      -- If there are no more pending tools, execute all completion callbacks
      local callbacks = queue.completion_callbacks
      queue.completion_callbacks = {}
      vim.b[buffer].llm_sidekick_tool_queue = queue
      for _, cb in ipairs(callbacks) do
        cb()
      end
    end

    return
  end

  queue.running = true
  local next_item = table.remove(queue.pending, 1)
  vim.b[buffer].llm_sidekick_tool_queue = queue

  local tool_call = refresh_tool_call_lnums(next_item.tool_call, { buffer = buffer })
  if not tool_call then
    queue.running = false
    vim.b[buffer].llm_sidekick_tool_queue = queue
    M.process_next_in_queue(buffer)
    return
  end

  -- We'll call the internal run function which doesn't interact with the queue
  M._run_tool_call_internal(tool_call, next_item.opts)
end

-- Helper function to run auto-acceptable tools after a specific tool
local function maybe_queue_next_auto_acceptable_tools(completed_tool, buffer)
  local tool_calls = M.get_tool_calls_in_last_assistant_message({ buffer = buffer })
  local found_completed_tool = false

  for _, tool_call in ipairs(tool_calls) do
    if completed_tool.id == tool_call.id then
      found_completed_tool = true
    elseif found_completed_tool then
      if tool_call.tool.is_auto_acceptable(tool_call) then
        M.queue_tool_call(tool_call, { buffer = buffer })
      else
        break
      end
    end
  end
end

-- Run tools with a callback when all tools have completed
-- This is a generic function that can be used to run any tools and execute a callback when they're all done
-- @param tool_calls: List of tool calls to run
-- @param opts: Options including buffer
-- @param callback: Function to call when all tools have completed
-- @param filter_fn: Optional function to filter which tools to run
M.run_tools_with_callback = function(tool_calls, opts, callback, filter_fn)
  local buffer = opts.buffer
  M.add_completion_callback(buffer, callback)

  -- Run tools that match the filter
  for _, tool_call in ipairs(tool_calls) do
    if not tool_call.result then
      if not filter_fn or filter_fn(tool_call) then
        M.queue_tool_call(tool_call, { buffer = buffer })
      end
    end
  end

  M.process_next_in_queue(buffer)
end

-- Run auto-acceptable tools with a callback when all tools have completed
-- This function will run tools until it finds one that's not auto-acceptable
-- and then execute the callback when all queued tools have completed
M.run_auto_acceptable_tools_with_callback = function(tool_calls, opts, callback)
  if #tool_calls == 0 then
    callback()
    return
  end

  local first_non_auto = nil

  -- Find the first non-auto-acceptable tool
  for i, tool_call in ipairs(tool_calls) do
    if not tool_call.result and not tool_call.tool.is_auto_acceptable(tool_call) then
      first_non_auto = i
      break
    end
  end

  -- Create a filter function that only accepts tools before the first non-auto-acceptable one
  local filter_fn = function(tool_call)
    if not first_non_auto then
      return tool_call.tool.is_auto_acceptable(tool_call)
    end

    -- Find the index of this tool_call
    for i, tc in ipairs(tool_calls) do
      if tc.id == tool_call.id then
        return i < first_non_auto and tool_call.tool.is_auto_acceptable(tool_call)
      end
    end

    return false
  end

  -- Run the tools with our filter
  M.run_tools_with_callback(tool_calls, opts, callback, filter_fn)
end

M.find_tool_for_tool_call = function(tool_call)
  for _, tool in ipairs(built_in_tools) do
    if tool.spec.name == tool_call.name then
      return tool
    end
  end
end

M.find_tool_call_by_id = function(tool_id, opts)
  for _, tool_call in ipairs(vim.b[opts.buffer].llm_sidekick_tool_calls or {}) do
    if tool_call.id == tool_id then
      return tool_call
    end
  end
end

M.find_tool_calls = function(opts)
  local buffer = opts.buffer
  local tool_calls = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buffer, vim.g.llm_sidekick_ns, 0, -1, { details = true })) do
    local extmark_id, row, _, details = unpack(mark)

    if details and details.invalid then
      goto continue
    end

    local tool_call = find_tool_call_by_extmark_id(extmark_id, { buffer = buffer })
    if tool_call then
      tool_call.tool = M.find_tool_for_tool_call(tool_call)
      local line_count = tool_call.state.end_lnum - tool_call.state.lnum
      tool_call.state.lnum = row + 1
      tool_call.state.end_lnum = math.max(tool_call.state.lnum + line_count, tool_call.state.lnum)
      table.insert(tool_calls, tool_call)
    end

    ::continue::
  end

  return tool_calls
end

M.update_tool_call_in_buffer = function(opts)
  local updated_tool_calls = vim.b[opts.buffer].llm_sidekick_tool_calls or {}
  for i, tc in ipairs(updated_tool_calls) do
    if tc.id == opts.tool_call.id then
      updated_tool_calls[i] = opts.tool_call
      break
    end
  end
  vim.b[opts.buffer].llm_sidekick_tool_calls = updated_tool_calls
end

M.get_tool_calls_in_last_assistant_message = function(opts)
  local buffer = opts.buffer
  local buffer_lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local last_assistant_start_line = opts.lnum or file_editor.find_last_assistant_start_line(buffer_lines)

  if last_assistant_start_line == -1 then
    error("No \"ASSISTANT:\" message found")
  end

  local tool_calls = M.find_tool_calls({ buffer = buffer })
  return vim.tbl_filter(
    function(tc) return tc.state.lnum >= last_assistant_start_line end,
    tool_calls
  )
end

-- Internal function to run a tool call without queue interaction
M._run_tool_call_internal = function(tool_call, opts)
  if tool_call.result then
    local queue = initialize_tool_queue(opts.buffer)
    if queue then
      queue.running = false
      vim.b[opts.buffer].llm_sidekick_tool_queue = queue
      M.process_next_in_queue(opts.buffer)
    end
    return
  end

  local buffer = opts.buffer
  if not tool_call.tool then
    tool_call.tool = M.find_tool_for_tool_call(tool_call)
  end

  if tool_call.tool.run == nil then
    diagnostic.add_tool_call(
      tool_call,
      buffer,
      vim.diagnostic.severity.ERROR,
      string.format("✗ %s: No run function defined", tool_call.name)
    )

    local queue = initialize_tool_queue(buffer)
    if queue then
      queue.running = false
      vim.b[buffer].llm_sidekick_tool_queue = queue
      M.process_next_in_queue(buffer)
    end
    return
  end

  local line_count_before = vim.api.nvim_buf_line_count(buffer)

  -- Mark tool as running
  tool_call.state.is_running = true
  M.update_tool_call_in_buffer({ buffer = buffer, tool_call = tool_call })

  -- Execute the tool
  local ok, result_or_job = pcall(tool_call.tool.run, tool_call, { buffer = buffer })

  -- Handle async tool execution (when a Job is returned)
  if ok and type(result_or_job) == "table" and result_or_job.start and type(result_or_job.start) == "function" then
    -- It's a Job object, set up completion callback
    result_or_job:after(vim.schedule_wrap(function(_)
      -- Update tool call with results
      tool_call.result = tool_call.state.result
      tool_call.state.result = nil
      tool_call.state.is_running = false

      -- Update line counts and extmark
      local line_count_after = vim.api.nvim_buf_line_count(buffer)
      if line_count_before ~= line_count_after then
        tool_call.state.end_lnum = math.max(
          tool_call.state.lnum + (line_count_after - line_count_before),
          tool_call.state.lnum
        )
      end

      -- Ensure line number is valid before setting extmark
      local line_num = tool_call.state.lnum - 1
      local max_lines = vim.api.nvim_buf_line_count(buffer)
      if line_num >= 0 and line_num < max_lines then
        vim.api.nvim_buf_set_extmark(
          buffer,
          vim.g.llm_sidekick_ns,
          line_num,
          0,
          { id = tool_call.state.extmark_id, invalidate = true }
        )
      end

      M.update_tool_call_in_buffer({ buffer = buffer, tool_call = tool_call })
      update_diagnostic(tool_call, { buffer = buffer })

      -- Process next tool in queue
      local queue = initialize_tool_queue(buffer)
      if queue then
        queue.running = false
        vim.b[buffer].llm_sidekick_tool_queue = queue
        M.process_next_in_queue(buffer)
      end
    end))

    -- Start the job
    result_or_job:start()

    -- Set temporary diagnostic to show it's running
    update_diagnostic(tool_call, { buffer = buffer })

    return
  end

  -- Synchronous execution or error
  tool_call.result = { success = ok, result = result_or_job }
  tool_call.state.is_running = false

  local line_count_after = vim.api.nvim_buf_line_count(buffer)
  if line_count_before ~= line_count_after then
    tool_call.state.end_lnum = math.max(
      tool_call.state.lnum + (line_count_after - line_count_before),
      tool_call.state.lnum
    )
  end

  -- Ensure line number is valid before setting extmark
  local line_num = tool_call.state.lnum - 1
  local max_lines = vim.api.nvim_buf_line_count(buffer)
  if line_num >= 0 and line_num < max_lines then
    vim.api.nvim_buf_set_extmark(
      buffer,
      vim.g.llm_sidekick_ns,
      line_num,
      0,
      { id = tool_call.state.extmark_id, invalidate = true }
    )
  end

  M.update_tool_call_in_buffer({ buffer = buffer, tool_call = tool_call })
  update_diagnostic(tool_call, { buffer = buffer })

  -- Process next tool in queue for synchronous tools
  local queue = initialize_tool_queue(buffer)
  if queue then
    queue.running = false
    vim.b[buffer].llm_sidekick_tool_queue = queue
    M.process_next_in_queue(buffer)
  end
end

M.add_tool_call_to_buffer = function(opts)
  local tool_calls = vim.b[opts.buffer].llm_sidekick_tool_calls or {}
  vim.b[opts.buffer].llm_sidekick_tool_calls = vim.list_extend(tool_calls, { opts.tool_call })
end

M.run_tool_call_at_cursor = function(opts)
  local buffer = opts.buffer
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local tool_call_at_cursor

  for _, tool_call in ipairs(M.find_tool_calls({ buffer = buffer })) do
    if cursor_line >= tool_call.state.lnum and cursor_line <= tool_call.state.end_lnum then
      tool_call_at_cursor = tool_call
      M.queue_tool_call(tool_call, { buffer = buffer })
      break
    end
  end

  if not tool_call_at_cursor then
    vim.notify("No tool call found at cursor", vim.log.levels.WARN)
    return
  end

  M.add_completion_callback(buffer, opts.callback)

  -- Check if there are auto-acceptable tools that should run after this one
  maybe_queue_next_auto_acceptable_tools(tool_call_at_cursor, buffer)

  M.process_next_in_queue(buffer)
end

M.run_tool_calls_in_last_assistant_message = function(opts)
  local buffer = opts.buffer

  local tool_calls = M.get_tool_calls_in_last_assistant_message({ buffer = buffer })
  tool_calls = vim.tbl_filter(function(tc) return tc.result == nil end, tool_calls)
  if #tool_calls == 0 then
    opts.callback()
    return
  end

  M.add_completion_callback(buffer, opts.callback)

  for _, tool_call in ipairs(tool_calls) do
    M.queue_tool_call(tool_call, { buffer = buffer })
  end

  M.process_next_in_queue(buffer)
end

return M
