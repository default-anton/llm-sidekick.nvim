-- lua/llm-sidekick/tools/delegate_task.lua
local chat = require("llm-sidekick.chat")
local Job = require("plenary.job")
local settings = require("llm-sidekick.settings")
local prompts = require("llm-sidekick.prompts")
local all_tools_module = require("llm-sidekick.tools") -- Renamed to avoid conflict
local openai_client = require("llm-sidekick.openai")
local utils = require("llm-sidekick.utils") -- For logging if needed
local tool_utils = require("llm-sidekick.tools.utils")
local sjson = require("llm-sidekick.sjson") -- For safe JSON decoding of tool params

-- Define message types based on expected streaming states from openai_client.lua
-- These might need to be imported or aligned with actual openai_client.lua values.
local message_types = {
  DATA = "data", -- content delta
  TOOL_DELTA = "tool_delta", -- tool parameter delta
  TOOL_START = "tool_start", -- tool call started (name, id)
  TOOL_STOP = "tool_stop",   -- tool call finished
  REASONING = "reasoning", -- reasoning/thought delta (if supported)
  DONE = "done",     -- stream finished for this turn
  ERROR = "error",   -- error from the LLM stream
}

local tool_spec = {
  name = "delegate_task_to_subagent",
  description = "Delegates a specific, well-defined task to a subagent. Use this when a complex problem can be broken down into smaller, independent parts that another AI agent can work on. Provide clear, self-contained instructions for the subagent.",
  input_schema = {
    type = "object",
    properties = {
      task_instructions = {
        type = "string",
        description = "Detailed, self-contained instructions for the subagent. This should include all necessary context the subagent needs to perform the task."
      },
      input_data = {
        type = "string",
        description = "Any specific data the subagent might need, such as code snippets, text excerpts, or names of files the main agent has already read and can provide content from. The subagent will operate based *only* on the `task_instructions` and this `input_data`."
      }
    },
    required = { "task_instructions" }
  }
}

local M = {
  spec = tool_spec,
  json_props = vim.json.encode(tool_spec.input_schema.properties), -- Correctly encode the properties
  is_show_diagnostics = function()
    return true
  end,
  is_auto_acceptable = function()
    -- Per plan, this is true as the main agent decides to delegate
    -- and subagent actions are considered approved.
    return true
  end,
  start = function(tool_call, opts)
    -- opts.buffer is the main chat buffer
    local instruction_preview = tool_call.parameters.task_instructions or ""
    if #instruction_preview > 50 then
      instruction_preview = string.sub(instruction_preview, 1, 50) .. "..."
    end
    chat.paste_at_end(string.format("Subagent: Initializing for task: '%s'\n", instruction_preview), opts.buffer)
  end,
  stop = function(tool_call, opts)
    -- This is called when the tool call rendering is complete in the main buffer.
    -- The actual delegation (run function) hasn't happened yet.
    chat.paste_at_end("Subagent: Delegation initiated.\n", opts.buffer)
  end,
  run = function(original_tool_call, main_opts) -- Renamed params for clarity
    local task_instructions = original_tool_call.parameters.task_instructions
    local input_data = original_tool_call.parameters.input_data

    local base_system_prompt_opts = {
      buffer = main_opts.buffer,
      cwd = vim.fn.getcwd(),
    }
    local base_system_prompt = prompts.system_prompt(base_system_prompt_opts)
    local subagent_system_prompt_string = base_system_prompt ..
      "\n\nYou are a specialized subagent. Your task is: " .. task_instructions ..
      "\nYou must complete this task to the best of your ability." ..
      "\nIMPORTANT: You do NOT have the ability to delegate tasks further. Do not attempt to use any tool named 'delegate_task_to_subagent' or similar."

    local all_tools_list = all_tools_module.get_tools()
    local subagent_tool_definitions = {} -- For client:chat
    local subagent_tool_runners = {}   -- For executing: name -> tool_module
    for _, tool_module in ipairs(all_tools_list) do
      if tool_module.spec.name ~= "delegate_task_to_subagent" then
        table.insert(subagent_tool_definitions, tool_module.spec) -- Pass only spec to LLM
        subagent_tool_runners[tool_module.spec.name] = tool_module
      end
    end

    local model_settings = settings.get_model_settings()
    local client = openai_client.new({
      url = model_settings.url,
      api_key = model_settings.api_key,
      message_types = message_types, -- Pass our defined message types to the client
                                     -- This assumes client is adapted to use them or this field is informational
    })

    local subagent_session = {
      messages = {
        { role = "system", content = subagent_system_prompt_string },
        { role = "user", content = input_data or task_instructions },
      },
      current_assistant_message = "",
      pending_tool_calls = {}, -- key: tool_call_id, value: {name, accumulated_params_str}
      completed_tool_calls_for_turn = {}, -- list of {id, name, parameters_obj}
    }

    -- Forward declare functions for the loop
    local subagent_callback_function
    local execute_subagent_tools

    execute_subagent_tools = function()
      chat.paste_at_end("Subagent: Executing " .. #subagent_session.completed_tool_calls_for_turn .. " tool(s).\n", main_opts.buffer)

      for _, tool_to_exec in ipairs(subagent_session.completed_tool_calls_for_turn) do
        local tool_runner = subagent_tool_runners[tool_to_exec.name]
        if tool_runner then
          chat.paste_at_end(string.format("Subagent: Attempting to use tool: %s with params: %s\n", tool_to_exec.name, vim.json.encode(tool_to_exec.parameters)), main_opts.buffer)

          -- IMPORTANT: tool.run might be sync or async (return a job)
          -- For this subtask, we focus on synchronous. Async needs more complex job management.
          local success, result_or_error = pcall(tool_runner.run, tool_to_exec.parameters, main_opts)
          local tool_output_content
          if success then
            -- Assuming tools return {success=true, result=data} or {success=false, error=msg} or just raw data for success
            if type(result_or_error) == "table" and result_or_error.success ~= nil then
              tool_output_content = result_or_error
            else -- Simple synchronous result, wrap it
              tool_output_content = { success = true, result = result_or_error }
            end
            if tool_output_content.success then
              chat.paste_at_end(string.format("Subagent: Tool %s finished.\n", tool_to_exec.name), main_opts.buffer)
            else
              local err_msg = result_or_error.error or vim.inspect(result_or_error.result) or "Unknown tool error"
              chat.paste_at_end(string.format("Subagent Error: Tool '%s' executed but reported failure: %s\n", tool_to_exec.name, err_msg), main_opts.buffer)
              utils.log_error(string.format("Subagent tool %s execution reported failure: %s", tool_to_exec.name, err_msg))
            end
          else
            -- pcall failed, result_or_error is the error message string
            local tool_error_message = tostring(result_or_error)
            tool_output_content = { success = false, error = "Tool execution failed: " .. tool_error_message }
            chat.paste_at_end(string.format("Subagent Error: Tool '%s' failed: %s\n", tool_to_exec.name, tool_error_message), main_opts.buffer)
            utils.log_error(string.format("Subagent tool %s pcall error: %s", tool_to_exec.name, tool_error_message))
          end

          table.insert(subagent_session.messages, {
            role = "tool",
            tool_call_id = tool_to_exec.id,
            content = vim.json.encode(tool_output_content) -- Send back the structured success/error and result/error message
          })
        else
          local unknown_tool_msg = string.format("Subagent Error: Unknown tool '%s' requested.\n", tool_to_exec.name)
          chat.paste_at_end(unknown_tool_msg, main_opts.buffer)
          utils.log_error(unknown_tool_msg)
          table.insert(subagent_session.messages, {
            role = "tool",
            tool_call_id = tool_to_exec.id,
            content = vim.json.encode({ success = false, error = "Unknown tool: " .. tool_to_exec.name })
          })
        end
      end
      subagent_session.completed_tool_calls_for_turn = {} -- Clear for next turn

      -- After executing tools, call LLM again with tool results
      local current_chat_opts = {
        messages = subagent_session.messages,
        tools = subagent_tool_definitions,
        settings = { model = model_settings.name, stream = true, temperature = model_settings.temperature, max_tokens = model_settings.max_tokens }
      }
      client:chat(current_chat_opts, subagent_callback_function)
    end

    subagent_callback_function = function(type, data, client_job_id)
      local pcall_ok, pcall_err = pcall(function()
        if type == message_types.DATA then
          subagent_session.current_assistant_message = subagent_session.current_assistant_message .. (data or "")
          chat.paste_at_end("Subagent: " .. (data or ""), main_opts.buffer, true) -- true for no newline, stream style
        elseif type == message_types.TOOL_START then
          subagent_session.pending_tool_calls[data.id] = { name = data.name, params_str = "", id = data.id }
          chat.paste_at_end(string.format("\nSubagent: Starting tool %s (id: %s)\n", data.name, data.id), main_opts.buffer)
        elseif type == message_types.TOOL_DELTA then
          if subagent_session.pending_tool_calls[data.id] then
            subagent_session.pending_tool_calls[data.id].params_str = subagent_session.pending_tool_calls[data.id].params_str .. (data.parameters or "")
          end
        elseif type == message_types.TOOL_STOP then
          local pending_call = subagent_session.pending_tool_calls[data.id]
          if pending_call then
            local sjson_ok, params_obj_or_err = sjson.decode(pending_call.params_str)
            if not sjson_ok then
              local err_detail = "Failed to parse JSON parameters for tool " .. pending_call.name .. ": " .. params_obj_or_err .. ". Input: " .. pending_call.params_str
              utils.log_error("Subagent: " .. err_detail)
              chat.paste_at_end(string.format("Subagent Error: %s\n", err_detail), main_opts.buffer)
              table.insert(subagent_session.completed_tool_calls_for_turn, {
                id = pending_call.id,
                name = pending_call.name,
                parameters = { error = "Malformed JSON parameters", details = err_detail }
              })
            else
              table.insert(subagent_session.completed_tool_calls_for_turn, {
                id = pending_call.id,
                name = pending_call.name,
                parameters = params_obj_or_err
              })
            end
            chat.paste_at_end(string.format("Subagent: Tool %s (id: %s) call prepared.\n", pending_call.name, data.id), main_opts.buffer)
            subagent_session.pending_tool_calls[data.id] = nil -- Clear from pending
          end
        elseif type == message_types.DONE then
          chat.paste_at_end("\nSubagent: LLM turn finished.\n", main_opts.buffer) -- Add final newline after streaming
          if subagent_session.current_assistant_message and #subagent_session.current_assistant_message > 0 then
            table.insert(subagent_session.messages, { role = "assistant", content = subagent_session.current_assistant_message })
            subagent_session.current_assistant_message = "" -- Reset for next turn
          end

          if #subagent_session.completed_tool_calls_for_turn > 0 then
            execute_subagent_tools()
          else
            -- No tools to call, this is the final answer from subagent
            if #subagent_session.messages > 0 and subagent_session.messages[#subagent_session.messages].role == "assistant" then
              local final_answer = subagent_session.messages[#subagent_session.messages].content
              chat.paste_at_end("Subagent: Task completed. Final answer: " .. final_answer .. "\n", main_opts.buffer)
              if original_tool_call and original_tool_call.set_result then
                 original_tool_call:set_result({ success = true, result = { content = final_answer } })
              end
            else
                -- This case should ideally not be reached if LLM behaves, but as a fallback:
                local err_msg = "Subagent: Task ended without a final assistant message."
                chat.paste_at_end(err_msg .. "\n", main_opts.buffer)
                if original_tool_call and original_tool_call.set_result then
                    original_tool_call:set_result({ success = false, result = { error = err_msg } })
                end
            end
            -- The main plenary job's on_exit will handle tool_queue.tool_finished
          end
        elseif type == message_types.ERROR then
          local err_msg_detail = data or "Unknown LLM stream error"
          local err_msg_display = "Subagent Error: LLM communication failed: " .. err_msg_detail .. "\n"
          chat.paste_at_end(err_msg_display, main_opts.buffer)
          utils.log_error(err_msg_display)
          if original_tool_call and original_tool_call.set_result then
            original_tool_call:set_result({ success = false, result = { error = "Subagent LLM communication failed", details = err_msg_detail } })
          end
          -- Main plenary job's on_exit will handle queue notification. No further calls to client:chat.
        end
      end)

      if not pcall_ok then
        local error_message = string.format("Subagent Error: Internal error in callback: %s\n", tostring(pcall_err))
        chat.paste_at_end(error_message, main_opts.buffer)
        utils.log_error(error_message)
        if original_tool_call and original_tool_call.set_result and (not original_tool_call.state or not original_tool_call.state.result) then
          original_tool_call:set_result({ success = false, result = { error = "Subagent internal callback error", details = tostring(pcall_err) } })
        end
        -- If client_job_id is a Plenary job object with a stop method, could call it.
        -- However, client:chat might manage its own job lifecycle.
        -- The primary goal is to set original_tool_call result and log.
      end
    end

    -- Initial call to the LLM
    local initial_chat_opts = {
      messages = subagent_session.messages,
      tools = subagent_tool_definitions,
      settings = { model = model_settings.name, stream = true, temperature = model_settings.temperature, max_tokens = model_settings.max_tokens }
    }
    client:chat(initial_chat_opts, subagent_callback_function)
    chat.paste_at_end("Subagent: Initial LLM call made.\n", main_opts.buffer)

    -- The plenary job returned by `run` now primarily serves to manage the overall lifecycle
    -- of the delegation, especially its final success/failure reporting to the main tool queue.
    -- The actual async work (LLM calls, tool exec) happens via callbacks.
    local overall_job = Job:new({
      command = "sleep", -- Minimal command, job is for state and on_exit
      args = {"0.1"}, -- Short sleep, essentially a yielding mechanism if needed
      on_exit = vim.schedule_wrap(function(j, return_val) -- `j` here is overall_job
        -- This on_exit is critical. It's called when original_tool_call:set_result() has been invoked
        -- (either with success or error by the subagent logic) OR if this placeholder job itself fails.
        -- We rely on the subagent logic to call original_tool_call:set_result() before it finishes.
        -- If original_tool_call.state.result is not set, it means something went wrong before subagent completion.
        -- Ensure result is set if something unexpected happened, and callback didn't set it.
        if original_tool_call and original_tool_call.get_state and (not original_tool_call:get_state().result) then
            local err_msg = "Subagent task concluded without explicit result."
            utils.log_error("DelegateTaskTool: " .. err_msg .. " for tool_call_id: " .. original_tool_call.id)
            if original_tool_call.set_result then
                original_tool_call:set_result({ success = false, result = { error = err_msg } })
            end
        end

        if original_tool_call and original_tool_call.get_state and original_tool_call.get_state().result then
          utils.log("DelegateTaskTool: Overall subagent job finished for tool_call_id: " .. original_tool_call.id .. " with state: " .. vim.inspect(original_tool_call:get_state().result))
        else
          utils.log_error("DelegateTaskTool: Overall subagent job finished for tool_call_id: " .. original_tool_call.id .. " but state was not available.")
        end

        local queue = tool_utils.get_tool_queue(main_opts.buffer)
        if queue then
          queue:tool_finished(original_tool_call.id)
        else
          utils.log_error("DelegateTaskTool: Could not retrieve tool queue for buffer " .. main_opts.buffer .. " on job exit.")
        end
      end),
    })
    overall_job:start()
    utils.log("DelegateTaskTool: Overall monitoring job started for tool_call_id: " .. original_tool_call.id)
    return overall_job
  end
}

return M
