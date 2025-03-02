# Implementation Plan: Async Tool Execution

This document outlines the plan for making tool `run` methods asynchronous in the llm-sidekick.nvim plugin.

## Status Update

**Phase 1 (Core Implementation) - COMPLETED ✓**
- Updated `run_tool_call` function to handle async tools
- Added helper functions for managing tool state
- Converted `run_terminal_command.lua` to be async

## Goals

1. Allow tools to execute asynchronously ✓
2. Maintain backward compatibility with existing synchronous tools ✓
3. Minimize changes to the existing codebase ✓
4. Ensure proper UI updates during async execution ✓
5. Handle tool chaining correctly (auto-acceptable tools) ✓

## Implementation Strategy

We'll use Plenary's Job API for async execution, which is already used throughout the codebase. Tools will return a Job object instead of direct results, and the `run_tool_call` function will handle both synchronous and asynchronous execution patterns.

## Required Changes

### 1. Update `lua/llm-sidekick/tools/utils.lua`

#### Modify `run_tool_call` function to handle async tools

```lua
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

  -- Mark tool as running
  tool_call.state.is_running = true
  
  -- Execute the tool
  local ok, result_or_job = pcall(tool_call.tool.run, tool_call, { buffer = buffer })
  
  -- Handle async tool execution (when a Job is returned)
  if ok and type(result_or_job) == "table" and result_or_job.start and type(result_or_job.start) == "function" then
    -- It's a Job object, set up completion callback
    result_or_job:after_success(function(j)
      vim.schedule(function()
        -- Update tool call with results
        tool_call.result = { success = true, result = tool_call.state.output or "Success" }
        tool_call.state.is_running = false
        
        -- Update line counts and extmark
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
        
        -- Check if there are auto-acceptable tools that should run after this one
        maybe_run_next_auto_acceptable_tools(tool_call, buffer)
      end)
    end)
    
    result_or_job:after_failure(function(j, code, signal)
      vim.schedule(function()
        local error_msg = table.concat(j:stderr_result(), "\n")
        tool_call.result = { success = false, result = error_msg or "Failed with code: " .. code }
        tool_call.state.is_running = false
        
        update_tool_call_in_buffer({ buffer = buffer, tool_call = tool_call })
        update_diagnostic(tool_call, { buffer = buffer })

        -- Check if there are auto-acceptable tools that should run after this one
        maybe_run_next_auto_acceptable_tools(tool_call, buffer)
      end)
    end)
    
    -- Start the job
    result_or_job:start()
    
    -- Set temporary diagnostic to show it's running
    diagnostic.add_tool_call(
      tool_call,
      buffer,
      vim.diagnostic.severity.HINT,
      string.format("⟳ %s (running...)", tool_call.name)
    )
    
    return
  else
    -- Synchronous execution or error
    tool_call.result = { success = ok, result = result_or_job }
    tool_call.state.is_running = false
  end

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
}
```

#### Add helper function for running auto-acceptable tools

```lua
-- Helper function to run auto-acceptable tools after a specific tool
local function maybe_run_next_auto_acceptable_tools(completed_tool, buffer)
  local tool_calls = get_tool_calls_in_last_assistant_message({ buffer = buffer })
  local found_completed_tool = false
  
  for _, tool_call in ipairs(tool_calls) do
    if completed_tool.id == tool_call.id then
      found_completed_tool = true
    elseif found_completed_tool then
      if tool_call.tool.is_auto_acceptable(tool_call) then
        run_tool_call(tool_call, { buffer = buffer })
      else
        update_diagnostic(tool_call, { buffer = buffer })
        found_completed_tool = false
      end
    else
      update_diagnostic(tool_call, { buffer = buffer })
    end
  end
end
```

#### Update `run_tool_call_at_cursor` to handle async tools

```lua
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

  -- For sync tools, auto-acceptable tools are handled in maybe_run_next_auto_acceptable_tools
  -- For async tools, they'll be handled in the completion callback
  if not tool_call_at_cursor.state.is_running then
    -- Update diagnostics for other tools
    local tool_calls = get_tool_calls_in_last_assistant_message({ buffer = buffer })
    for _, tool_call in ipairs(tool_calls) do
      if tool_call_at_cursor.id ~= tool_call.id then
        update_diagnostic(tool_call, { buffer = buffer })
      end
    end
  end
}
```

#### Update `run_tool_calls_in_last_assistant_message` to handle async tools

```lua
local function run_tool_calls_in_last_assistant_message(opts)
  local tool_calls = get_tool_calls_in_last_assistant_message({ buffer = opts.buffer })
  local pending_async_tools = 0
  
  for _, tool_call in ipairs(tool_calls) do
    tool_call = refresh_tool_call_lnums(tool_call, { buffer = opts.buffer })
    if tool_call then
      run_tool_call(tool_call, { buffer = opts.buffer })
      if tool_call.state.is_running then
        pending_async_tools = pending_async_tools + 1
      end
    end
  end
  
  if pending_async_tools > 0 then
    vim.notify(string.format("Running %d async tool(s)...", pending_async_tools), vim.log.levels.INFO)
  end
}
```

### 2. Update `lua/llm-sidekick/tools/terminal/run_terminal_command.lua`

Convert the `run` method to be async:

```lua
-- Execute the command
run = function(tool_call, opts)
  local cwd = vim.fn.getcwd()
  local shell = vim.o.shell or "bash"
  local command = vim.trim(tool_call.parameters.command or "")
  
  -- Store initial state
  tool_call.state.output = ""
  
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
        output = "Stdout:\n```" .. table.concat(stdout, "\n") .. "```"
      end

      local stderr = j:stderr_result()
      if stderr and not vim.tbl_isempty(stderr) then
        output = output .. "\n\nStderr:\n```" .. table.concat(stderr, "\n") .. "```"
      end
      
      -- Store the output in tool_call state for access in the after_success callback
      tool_call.state.output = string.format("Exit code: %d\n%s", exit_code, output)
      
      -- Update the command text from "Execute" to "Executed"
      vim.schedule(function()
        local final_lines = { string.format("✓ Executed: `%s`", command) }

        -- Include explanation in final display if provided
        if tool_call.parameters.explanation then
          table.insert(final_lines, string.format("> %s", tool_call.parameters.explanation))
        end

        vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.lnum - 1, tool_call.state.end_lnum, false, final_lines)
      end)
    end,
  })
  
  -- Return the job object for async execution
  return job
}
```

## Testing Strategy

1. **Manual Testing**:
   - Test with real-world examples
   - Verify UI updates during long-running operations
   - Test edge cases like buffer changes during async execution

## Migration Path

1. **Initial Implementation**:
   - Update the core functions in `utils.lua` to handle both sync and async tools
   - Convert `run_terminal_command.lua` to be async as a reference implementation
   - Add documentation for the async tool pattern

2. **Future Work**:
   - Gradually convert other tools to be async as needed
   - Consider adding a timeout mechanism for async tools
   - Add progress indicators for long-running operations

## Timeline

1. **Phase 1** - Core Implementation: ✓ COMPLETED
   - Updated `run_tool_call` function to handle async tools
   - Added helper functions for managing tool state
   - Converted `run_terminal_command.lua` to be async

2. **Phase 2** - Refinement: IN PROGRESS
   - Fix any issues identified during testing
   - Update documentation for async tool development
   - Add tests for async tools
   - Optimize performance

3. **Phase 3** - Expansion:
   - Convert other tools to be async as needed
   - Add advanced features like progress indicators
   - Improve error handling and recovery
