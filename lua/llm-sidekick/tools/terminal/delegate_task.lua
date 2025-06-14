local chat = require("llm-sidekick.chat")
local prompts = require("llm-sidekick.prompts")
local utils = require("llm-sidekick.utils")

local spec = {
  name = "delegate_task_to_subagent",
  description =
  "Delegates a specific, well-defined task to a subagent. Use this when a complex problem can be broken down into smaller, independent parts that another AI agent can work on. Provide clear, self-contained instructions for the subagent.",
  input_schema = {
    type = "object",
    properties = {
      title = {
        type = "string",
        description =
        "A short, descriptive title for the task. This should be concise and clearly indicate the nature of the task."
      },
      task_instructions = {
        type = "string",
        description =
        "Detailed, self-contained instructions for the subagent. This should include all necessary context, data, and small code snippets or text excerpts when needed for immediate reference. Since the subagent has access to the same tools, reference file paths that need to be read rather than copying entire file contents. The subagent will operate solely based on these instructions."
      }
    },
    required = { "title", "task_instructions" }
  }
}

local json_props = string.format(
  [[{ "title": %s, "task_instructions": %s }]],
  vim.json.encode(spec.input_schema.properties.title),
  vim.json.encode(spec.input_schema.properties.task_instructions)
)

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
        tool_call.parameters.task_instructions
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

    -- Create hidden buffer for subagent tools to write to
    local hidden_buffer = vim.api.nvim_create_buf(false, true)
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
    -- local winnr = vim.api.nvim_open_win(hidden_buffer, false, win_opts)
    -- vim.api.nvim_set_current_win(winnr)

    -- Get all tools except delegate_task_to_subagent to prevent recursion
    local all_tools = require("llm-sidekick.tools")
    local subagent_tools = vim.tbl_filter(function(tool)
      return tool.spec.name ~= "delegate_task_to_subagent"
    end, all_tools)

    -- Create subagent prompt
    local subagent_prompt = string.format(
      "USER: %s",
      tool_call.parameters.task_instructions
    )

    -- Set up the hidden buffer with the prompt
    local prompt_lines = vim.split(subagent_prompt, "\n")
    vim.api.nvim_buf_set_lines(hidden_buffer, 0, -1, false, prompt_lines)

    -- Report subagent start to main buffer
    chat.paste_at_end(string.format("Starting subagent for task: %s\n", tool_call.parameters.title), opts.buffer)

    local callbacks = {}
    local fake_job = {}
    function fake_job:after(callback)
      table.insert(callbacks, callback)
    end

    -- Start the subagent loop
    local function run_subagent_loop()
      local main_agent = require("llm-sidekick.init")
      local file_editor = require("llm-sidekick.file_editor")
      local buf_lines = vim.api.nvim_buf_get_lines(hidden_buffer, 0, -1, false)
      local full_prompt = table.concat(buf_lines, "\n")
      local prompt = main_agent.parse_prompt(full_prompt, hidden_buffer)
      local last_assistant_lnum = file_editor.find_last_assistant_start_line(buf_lines)
      local last_user_lnum = file_editor.find_last_user_start_line(buf_lines)
      if last_assistant_lnum < last_user_lnum then
        vim.api.nvim_buf_set_lines(hidden_buffer, -1, -1, false, { "", "ASSISTANT: " })
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
      local tool_utils = require("llm-sidekick.tools.utils")
      local message_types = require "llm-sidekick.message_types"

      local tool_calls = {}
      local in_reasoning_tag = false

      local job = client:chat(prompt, function(state, chars)
        if not vim.api.nvim_buf_is_loaded(hidden_buffer) then
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
            local tc = tool_utils.find_tool_call_by_id(tool_call_data.id, { buffer = hidden_buffer })
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

              local last_two_lines = vim.api.nvim_buf_get_lines(hidden_buffer, -3, -1, false)
              if last_two_lines[#last_two_lines] == "" then
                if last_two_lines[1] ~= "" then
                  chat.paste_at_end("\n", hidden_buffer)
                end
              else
                chat.paste_at_end("\n\n", hidden_buffer)
              end

              tool_call_data.state.lnum = vim.api.nvim_buf_line_count(hidden_buffer)
              tool_utils.add_tool_call_to_buffer({ buffer = hidden_buffer, tool_call = tool_call_data })

              if tool.start then
                tool.start(tool_call_data, { buffer = hidden_buffer })
              end
            elseif state == message_types.TOOL_DELTA then
              if tool.delta then
                tool.delta(tool_call_data, { buffer = hidden_buffer })
              end
            elseif state == message_types.TOOL_STOP then
              if tool.stop then
                tool.stop(tool_call_data, { buffer = hidden_buffer })
              end

              tool_call_data.state.end_lnum = math.max(vim.api.nvim_buf_line_count(hidden_buffer),
                tool_call_data.state.lnum)

              chat.paste_at_end("\n\n", hidden_buffer)

              tool_call_data.state.extmark_id = vim.api.nvim_buf_set_extmark(
                hidden_buffer,
                vim.g.llm_sidekick_ns,
                tool_call_data.state.lnum - 1,
                0,
                { invalidate = true }
              )
              table.insert(tool_calls, tool_call_data)
              tool_utils.update_tool_call_in_buffer({ buffer = hidden_buffer, tool_call = tool_call_data })
              tool_call_data.tool = tool
            end

            return
          end

          if state == message_types.REASONING and not in_reasoning_tag then
            chat.paste_at_end("\n\n<llm_sidekick_thinking>\n", hidden_buffer)
            in_reasoning_tag = true
          end

          if state == message_types.DATA and in_reasoning_tag then
            chat.paste_at_end("\n</llm_sidekick_thinking>\n\n", hidden_buffer)
            in_reasoning_tag = false
          end

          chat.paste_at_end(chars, hidden_buffer)
        end)

        if not success then
          tool_call.state.result = { success = false, result = "Subagent error: " .. tostring(err) }
          chat.paste_at_end("Subagent completed with error\n", opts.buffer)
          return
        end

        if message_types.DONE == state then
          if not vim.api.nvim_buf_is_loaded(hidden_buffer) then
            return
          end

          -- Run auto-acceptable tools and continue loop or finish
          tool_utils.run_auto_acceptable_tools_with_callback(tool_calls, { buffer = hidden_buffer },
            function()
              if not vim.api.nvim_buf_is_loaded(hidden_buffer) then
                return
              end

              local tool_call_ids = vim.tbl_values(vim.tbl_map(function(tc) return tc.id end, tool_calls))
              local last_assistant_tool_calls = tool_utils.get_tool_calls_in_last_assistant_message({
                buffer =
                    hidden_buffer
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

              if no_tool_calls or has_pending_tools then
                -- Subagent is done, collect results
                local buffer_content = table.concat(vim.api.nvim_buf_get_lines(hidden_buffer, 0, -1, false), "\n")
                -- TODO: The result of the tool call should be the text of the last assistant message in the hidden buffer
                tool_call.state.result = { success = true, result = buffer_content }

                -- Clean up hidden buffer
                vim.api.nvim_buf_delete(hidden_buffer, { force = true })
                -- Call all callbacks
                for _, callback in ipairs(callbacks) do
                  pcall(callback)
                end
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
