local chat = require("llm-sidekick.chat")
local prompts = require("llm-sidekick.prompts")
local utils = require("llm-sidekick.utils")
local file_editor = require("llm-sidekick.file_editor")

local spec = {
  name = "delegate_task_to_subagent",
  description =
  "Delegates a specific, well-defined task to a subagent. Use this when a complex problem can be broken down into smaller, independent parts that another AI agent can work on. Structure your prompt with: (1) Objective - what should be accomplished, (2) Output Format - how the final response should be structured, and (3) Task Boundaries - what's in/out of scope. Provide clear, self-contained instructions for the subagent.",
  input_schema = {
    type = "object",
    properties = {
      title = {
        type = "string",
        description =
        "A short, descriptive title for the task. This should be concise and clearly indicate the nature of the task."
      },
      prompt = {
        type = "string",
        description =
        "Detailed, self-contained instructions for the subagent. Structure with: (1) Objective - clearly state what should be accomplished and the specific deliverable expected, (2) Output Format - specify exactly how the final response should be structured since this will be returned as the result, and (3) Task Boundaries - define what is in-scope and out-of-scope. Include all necessary context, data, and small code snippets or text excerpts when needed for immediate reference. Since the subagent has access to the same tools, reference file paths that need to be read rather than copying entire file contents. The subagent will operate solely based on these instructions."
      }
    },
    required = { "title", "prompt" }
  }
}

local json_props = string.format(
  [[{ "title": %s, "prompt": %s }]],
  vim.json.encode(spec.input_schema.properties.title),
  vim.json.encode(spec.input_schema.properties.prompt)
)

function approve_tool_calls(bufnr, approve_callback, reject_callback)
  local tool_utils = require("llm-sidekick.tools.utils")

  -- Calculate window dimensions (90% of editor size)
  local function calculate_window_size()
    local width = math.floor(vim.o.columns * 0.9)
    local height = math.floor(vim.o.lines * 0.9)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)
    return width, height, row, col
  end

  local width, height, row, col = calculate_window_size()
  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded"
  }
  local winnr = vim.api.nvim_open_win(bufnr, false, win_opts)
  vim.api.nvim_set_current_win(winnr)

  -- Create autocmd to handle window resizing
  local resize_autocmd_id = vim.api.nvim_create_autocmd("VimResized", {
    callback = function()
      if vim.api.nvim_win_is_valid(winnr) then
        local new_width, new_height, new_row, new_col = calculate_window_size()
        vim.api.nvim_win_set_config(winnr, {
          width = new_width,
          height = new_height,
          row = new_row,
          col = new_col
        })
      end
    end,
  })

  -- Create autocmd to handle window close
  local win_close_autocmd_id = vim.api.nvim_create_autocmd("WinClosed", {
    buffer = bufnr,
    callback = function()
      pcall(vim.api.nvim_del_autocmd, resize_autocmd_id)
      reject_callback()
    end,
    once = true,
  })

  local reject = function()
    if vim.api.nvim_win_is_valid(winnr) then
      pcall(vim.api.nvim_del_autocmd, win_close_autocmd_id)
      pcall(vim.api.nvim_del_autocmd, resize_autocmd_id)
      vim.api.nvim_win_close(winnr, true)
    end
    reject_callback()
  end

  local accept = function()
    tool_utils.run_tool_calls_in_last_assistant_message({
      buffer = bufnr,
      callback = vim.schedule_wrap(function()
        if vim.api.nvim_win_is_valid(winnr) then
          pcall(vim.api.nvim_del_autocmd, win_close_autocmd_id)
          pcall(vim.api.nvim_del_autocmd, resize_autocmd_id)
          vim.api.nvim_win_close(winnr, true)
        end
        approve_callback()
      end)
    })
  end

  vim.keymap.set('n', '<leader>A', accept,
    { noremap = true, silent = true, buffer = bufnr, desc = "Accept and continue" })
  vim.keymap.set('n', '<CR>', accept, { noremap = true, silent = true, buffer = bufnr, desc = "Accept and continue" })
  vim.keymap.set('n', '<C-c>', reject, { noremap = true, silent = true, buffer = bufnr, desc = "Reject and close" })
  vim.keymap.set('n', 'q', reject, { noremap = true, silent = true, buffer = bufnr, desc = "Reject and close" })
end

return {
  spec = spec,
  json_props = json_props,
  is_show_diagnostics = function() return true end,
  is_auto_acceptable = function() return true end,
  start = function(_, opts)
    chat.paste_at_end("**Subagent Task**\n", opts.buffer)
  end,
  stop = function(tool_call, opts)
    chat.paste_at_end(
      string.format(
        "**Title:** %s\n**Task Instructions:**\n````markdown\n%s\n````",
        tool_call.parameters.title,
        tool_call.parameters.prompt
      ),
      opts.buffer
    )
  end,
  -- Execute the subagent asynchronously
  run = function(tool_call, opts)
    local model_settings = vim.b[opts.buffer].llm_sidekick_model_settings
    local system_prompt = prompts.system_prompt({
      buf = opts.buffer,
      os_name = utils.get_os_name(),
      shell = vim.o.shell or "bash",
      cwd = vim.fn.getcwd(),
      just_chatting = false,
      model = model_settings.model,
      guidelines = vim.g.llm_sidekick_current_project_guidelines,
      technologies = vim.g.llm_sidekick_current_project_technologies,
    })

    -- Store initial state
    tool_call.state.result = { success = false, result = nil }

    -- Create a buffer for subagent tools to write to
    local subagent_buffer = vim.api.nvim_create_buf(false, true)

    -- Handle buffer close/delete - set result and call callbacks
    local buffer_close_autocmd_id = vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
      buffer = subagent_buffer,
      callback = function()
        if tool_call.state.result.success == false and tool_call.state.result.result == nil then
          tool_call.state.result = { success = false, result = "User interrupted the subagent by closing the buffer." }
          chat.paste_at_end("Subagent interrupted by user\n", opts.buffer)
          for _, callback in ipairs(callbacks) do
            pcall(callback)
          end
        end
      end,
      once = true,
    })
    -- NOTE: Opens a window for debugging. Don't delete this commented code.
    -- local width = 50
    -- local height = 30
    -- local win_opts = {
    --   relative = "editor",
    --   width = width,
    --   height = height,
    --   row = (vim.o.lines - height) / 2,
    --   col = (vim.o.columns - width) / 2,
    --   style = "minimal",
    --   border = "rounded"
    -- }
    -- local winnr = vim.api.nvim_open_win(subagent_buffer, false, win_opts)
    -- vim.api.nvim_set_current_win(winnr)

    -- Get all tools except delegate_task_to_subagent to prevent recursion
    local all_tools = require("llm-sidekick.tools")
    local subagent_tools = vim.tbl_filter(function(tool)
      return tool.spec.name ~= "delegate_task_to_subagent"
    end, all_tools)

    -- Create subagent prompt
    local subagent_prompt = string.format(
      "USER: %s",
      tool_call.parameters.prompt
    )

    -- Set up the subagent buffer with the prompt
    local prompt_lines = vim.split(subagent_prompt, "\n")
    vim.api.nvim_buf_set_lines(subagent_buffer, 0, -1, false, prompt_lines)

    -- Report subagent start to main buffer
    chat.paste_at_end(string.format("Starting subagent for task: %s\n", tool_call.parameters.title), opts.buffer)

    local callbacks = {}
    local fake_job = {}
    function fake_job:after(callback)
      table.insert(callbacks, callback)
    end

    -- Start the subagent loop
    local function run_subagent_loop()
      local tool_utils = require("llm-sidekick.tools.utils")
      local main_agent = require("llm-sidekick.init")
      local buf_lines = vim.api.nvim_buf_get_lines(subagent_buffer, 0, -1, false)
      local full_prompt = table.concat(buf_lines, "\n")
      local prompt = main_agent.parse_prompt(full_prompt, subagent_buffer)
      local last_assistant_lnum = file_editor.find_last_assistant_start_line(buf_lines)
      local last_user_lnum = file_editor.find_last_user_start_line(buf_lines)
      if last_assistant_lnum < last_user_lnum then
        vim.api.nvim_buf_set_lines(subagent_buffer, -1, -1, false, { "", "ASSISTANT: " })
      end

      -- Override tools with filtered set
      prompt.tools = subagent_tools
      prompt.settings = model_settings

      if model_settings.no_system_prompt then
        prompt.messages[1].content = system_prompt .. "\n\n" .. prompt.messages[1].content
      else
        table.insert(prompt.messages, 1, { role = "system", content = system_prompt })
      end

      local client = require "llm-sidekick.openai".new({ url = "http://localhost:1993/v1/chat/completions" })
      local message_types = require "llm-sidekick.message_types"

      local tool_calls = {}
      local in_reasoning_tag = false

      local job
      job = client:chat(prompt, function(state, chars)
        if not vim.api.nvim_buf_is_loaded(subagent_buffer) then
          return
        end

        local success, err = pcall(function()
          if state == message_types.ERROR then
            error(string.format("Subagent Error: %s", vim.inspect(chars)))
          end

          if state == message_types.ERROR_MAX_TOKENS then
            error("Subagent: Max tokens exceeded")
          end

          if state == message_types.TOOL_START or state == message_types.TOOL_DELTA or state == message_types.TOOL_STOP then
            local tool_call_data = chars
            local tc = tool_utils.find_tool_call_by_id(tool_call_data.id, { buffer = subagent_buffer })
            if tc then
              tool_call_data.state.lnum = tc.state.lnum
              tool_call_data.state.end_lnum = tc.state.end_lnum
              tool_call_data.state.extmark_id = tc.state.extmark_id
            end

            local tool = tool_utils.find_tool_for_tool_call(tool_call_data)
            if not tool then
              error("Subagent: Tool not found: " .. tool_call_data.name)
            end

            if state == message_types.TOOL_START then
              -- Report tool start to main buffer (just the name)
              chat.paste_at_end(string.format("  → %s\n", tool_call_data.name), opts.buffer)

              local last_two_lines = vim.api.nvim_buf_get_lines(subagent_buffer, -3, -1, false)
              if last_two_lines[#last_two_lines] == "" then
                if last_two_lines[1] ~= "" then
                  chat.paste_at_end("\n", subagent_buffer)
                end
              else
                chat.paste_at_end("\n\n", subagent_buffer)
              end

              tool_call_data.state.lnum = vim.api.nvim_buf_line_count(subagent_buffer)
              tool_utils.add_tool_call_to_buffer({ buffer = subagent_buffer, tool_call = tool_call_data })

              if tool.start then
                tool.start(tool_call_data, { buffer = subagent_buffer })
              end
            elseif state == message_types.TOOL_DELTA then
              if tool.delta then
                tool.delta(tool_call_data, { buffer = subagent_buffer })
              end
            elseif state == message_types.TOOL_STOP then
              if tool.stop then
                tool.stop(tool_call_data, { buffer = subagent_buffer })
              end

              tool_call_data.state.end_lnum = math.max(vim.api.nvim_buf_line_count(subagent_buffer),
                tool_call_data.state.lnum)

              chat.paste_at_end("\n\n", subagent_buffer)

              tool_call_data.state.extmark_id = vim.api.nvim_buf_set_extmark(
                subagent_buffer,
                vim.g.llm_sidekick_ns,
                tool_call_data.state.lnum - 1,
                0,
                { invalidate = true }
              )
              table.insert(tool_calls, tool_call_data)
              tool_utils.update_tool_call_in_buffer({ buffer = subagent_buffer, tool_call = tool_call_data })
              tool_call_data.tool = tool
            end

            return
          end

          if state == message_types.REASONING and not in_reasoning_tag then
            chat.paste_at_end("\n\n<llm_sidekick_thinking>\n", subagent_buffer)
            in_reasoning_tag = true
          end

          if state == message_types.DATA and in_reasoning_tag then
            chat.paste_at_end("\n</llm_sidekick_thinking>\n\n", subagent_buffer)
            in_reasoning_tag = false
          end

          chat.paste_at_end(chars, subagent_buffer)
        end)

        if not success then
          tool_call.state.result = { success = false, result = "Subagent error: " .. tostring(err) }
          chat.paste_at_end("Subagent completed with error\n", opts.buffer)
          if job and not job.is_shutdown then
            vim.loop.kill(job.pid, vim.loop.constants.SIGKILL)
          end
          -- Clean up buffer and autocmd on error
          if vim.api.nvim_buf_is_loaded(subagent_buffer) then
            pcall(vim.api.nvim_del_autocmd, buffer_close_autocmd_id)
            vim.api.nvim_buf_delete(subagent_buffer, { force = true })
          end
          for _, callback in ipairs(callbacks) do
            pcall(callback)
          end
          return
        end

        if message_types.DONE == state then
          if not vim.api.nvim_buf_is_loaded(subagent_buffer) then
            return
          end

          -- Run auto-acceptable tools and continue loop or finish
          tool_utils.run_auto_acceptable_tools_with_callback(tool_calls, { buffer = subagent_buffer },
            function()
              if not vim.api.nvim_buf_is_loaded(subagent_buffer) then
                return
              end

              local tool_call_ids = vim.tbl_values(vim.tbl_map(function(tc) return tc.id end, tool_calls))
              local last_assistant_tool_calls = tool_utils.get_tool_calls_in_last_assistant_message({
                buffer =
                    subagent_buffer
              })
              last_assistant_tool_calls = vim.tbl_filter(
                function(tc) return vim.tbl_contains(tool_call_ids, tc.id) end,
                last_assistant_tool_calls
              )
              local has_pending_tools = vim.tbl_contains(
                last_assistant_tool_calls,
                function(tc) return tc.result == nil end,
                { predicate = true }
              )
              local no_tool_calls = vim.tbl_isempty(last_assistant_tool_calls)

              if no_tool_calls then
                -- Subagent is done, return the last assistant message as the result
                local prompt = main_agent.parse_prompt(
                  table.concat(vim.api.nvim_buf_get_lines(subagent_buffer, 0, -1, false), "\n"), subagent_buffer)
                tool_call.state.result = { success = true, result = prompt.messages[#prompt.messages].content }
                -- Clean up subagent buffer
                if vim.api.nvim_buf_is_loaded(subagent_buffer) then
                  -- Clean up the buffer close autocmd before deleting buffer
                  pcall(vim.api.nvim_del_autocmd, buffer_close_autocmd_id)
                  vim.api.nvim_buf_delete(subagent_buffer, { force = true })
                end
                for _, callback in ipairs(callbacks) do
                  pcall(callback)
                end
              elseif has_pending_tools then
                -- prompt the user to approve tool calls
                approve_tool_calls(subagent_buffer, run_subagent_loop, function()
                  tool_call.state.result = {
                    success = false,
                    result = "User rejected tool calls suggested by subagent.",
                  }
                  if vim.api.nvim_buf_is_loaded(subagent_buffer) then
                    -- Clean up the buffer close autocmd before deleting buffer
                    pcall(vim.api.nvim_del_autocmd, buffer_close_autocmd_id)
                    vim.api.nvim_buf_delete(subagent_buffer, { force = true })
                  end
                  for _, callback in ipairs(callbacks) do
                    pcall(callback)
                  end
                end)
              else
                -- Continue the loop
                vim.schedule(run_subagent_loop)
              end
            end)
        end
      end)

      job:start()
    end

    function fake_job:start()
      run_subagent_loop()
    end

    -- Start the subagent loop and return the job
    return fake_job
  end
}
