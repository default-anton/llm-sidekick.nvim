local chat                   = require "llm-sidekick.chat"
local message_types          = require "llm-sidekick.message_types"
local fs                     = require "llm-sidekick.fs"
local settings               = require "llm-sidekick.settings"
local diagnostic             = require("llm-sidekick.diagnostic")
local tool_utils             = require("llm-sidekick.tools.utils")
local utils                  = require("llm-sidekick.utils")
local spinner                = require("llm-sidekick.spinner")

MAX_TURNS_WITHOUT_USER_INPUT = 25

local M                      = {}

function M.setup(opts)
  settings.setup(opts or {})
end

local DEFAULT_SETTTINGS = {
  stream = true,
}

function M.get_prompt(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local full_prompt = table.concat(lines, "\n")
  return full_prompt
end

function M.parse_prompt(prompt, buffer)
  local options = {
    messages = {},
    settings = vim.deepcopy(DEFAULT_SETTTINGS),
  }
  local processed_keys = {}
  local lines = vim.split(prompt, "\n")

  local all_tool_calls = tool_utils.find_tool_calls({ buffer = buffer })
  local tool_call_index = 1

  for lnum, line in ipairs(lines) do
    if line:sub(1, 7) == "SYSTEM:" and not processed_keys.system then
      table.insert(options.messages, { role = "system", content = line:sub(8) })
      processed_keys.system = true
      goto continue
    end
    if line:sub(1, 5) == "USER:" then
      table.insert(options.messages, { role = "user", content = line:sub(6) })
      goto continue
    end
    if line:sub(1, 10) == "ASSISTANT:" then
      table.insert(options.messages, { role = "assistant", content = line:sub(11) })
      goto continue
    end
    if line:sub(1, 6) == "MODEL:" and not processed_keys.model then
      options.settings.model = vim.trim(line:sub(7))
      processed_keys.model = true
      goto continue
    end
    if line:sub(1, 11) == "MAX_TOKENS:" and not processed_keys.max_tokens then
      options.settings.max_tokens = tonumber(vim.trim(line:sub(12)))
      processed_keys.max_tokens = true
      goto continue
    end
    if line:sub(1, 7) == "STREAM:" and not processed_keys.stream then
      options.settings.stream = vim.trim(line:sub(8)) == "true"
      processed_keys.stream = true
      goto continue
    end
    if line:sub(1, 12) == "TEMPERATURE:" and not processed_keys.temperature then
      options.settings.temperature = tonumber(vim.trim(line:sub(13)))
      processed_keys.temperature = true
      goto continue
    end

    if #options.messages == 0 then
      goto continue
    end

    local message = options.messages[#options.messages]

    if message.role ~= "assistant" or #all_tool_calls == 0 then
      message.content = message.content .. "\n" .. line
      goto continue
    end

    while tool_call_index <= #all_tool_calls and all_tool_calls[tool_call_index].state.end_lnum < lnum do
      tool_call_index = tool_call_index + 1
    end

    local tool_call = all_tool_calls[tool_call_index]

    if tool_call_index > #all_tool_calls or tool_call.state.lnum > lnum then
      message.content = message.content .. "\n" .. line
      goto continue
    end

    if tool_call.state.lnum ~= lnum then
      goto continue
    end

    message.tool_calls = message.tool_calls or {}

    if #message.tool_calls > 0 then
      message = { role = "assistant", tool_calls = {}, content = "" }
      table.insert(options.messages, message)
    end

    table.insert(
      message.tool_calls,
      {
        id = tool_call.id,
        type = "function",
        ["function"] = {
          name = tool_call.name,
          arguments = vim.json.encode(tool_call.parameters),
        },
      }
    )

    local result = tool_call.result
    if type(result) == "boolean" then
      result = { success = result }
    end
    if not result then
      result = { result = "User hasn't accepted the tool" }
    end

    message.tool_call_results = message.tool_call_results or {}
    table.insert(
      message.tool_call_results,
      {
        role = "tool",
        tool_call_id = tool_call.id,
        content = vim.json.encode(result),
      }
    )

    ::continue::
  end

  for message_index, message in ipairs(options.messages) do
    if message.role == "assistant" then
      -- NOTE: delete all thinking tags
      message.content = message.content:gsub("<llm_sidekick_thinking>.-</llm_sidekick_thinking>", "")
      message.content = message.content:gsub("<think>.-</think>", "") -- for deepseek-r1-distill-llama-70b

      if message.tool_call_results and #message.tool_call_results > 0 then
        for j, tool_call_result in ipairs(message.tool_call_results) do
          table.insert(options.messages, message_index + j, tool_call_result)
        end
      end

      message.tool_call_results = nil
    end

    message.content = vim.trim(message.content)
  end

  -- Remove last empty user message if the last message is a tool result
  if #options.messages > 1 then
    local last_msg = options.messages[#options.messages]
    local prev_msg = options.messages[#options.messages - 1]
    if last_msg.role == "user" and vim.trim(last_msg.content) == "" and prev_msg.role == "tool" then
      table.remove(options.messages)
    end
  end

  local editor_context = {}
  local last_user_message_index = nil
  for i, message in ipairs(options.messages) do
    if message.role == "user" or message.role == "system" then
      if message.role == "user" then
        last_user_message_index = i
      end

      message.content = vim.trim(message.content)
    end
  end

  if last_user_message_index then
    if not vim.tbl_isempty(editor_context) then
      options.messages[last_user_message_index].content = "<editor_context>\n"
          .. table.concat(vim.tbl_values(editor_context), "\n")
          .. "\n</editor_context>\n" .. options.messages[last_user_message_index].content
    end
  end

  if #options.messages > 0 and options.messages[#options.messages].role == "user" then
    local text = options.messages[#options.messages].content
    -- Check for llm_sidekick_image tags
    for image_path in text:gmatch("<llm_sidekick_image>(.-)</llm_sidekick_image>") do
      if not vim.fn.filereadable(image_path) == 1 then
        goto continue
      end

      local function get_base64_command()
        if vim.fn.has("mac") == 1 then
          return { "base64", "-i", image_path }
        else
          return { "base64", "-w0", image_path }
        end
      end

      local base64_image = vim.fn.system(get_base64_command())
      if vim.v.shell_error ~= 0 then
        vim.api.nvim_err_writeln("Failed to read image: " .. image_path)
        goto continue
      end

      -- Remove any newlines that might be present in the base64 output
      base64_image = base64_image:gsub("[\n\r]", "")
      text = text:gsub("<llm_sidekick_image>" .. vim.pesc(image_path) .. "</llm_sidekick_image>", "")
      local mime_type = vim.fn.systemlist({ "file", "--mime-type", "--brief", image_path })[1]

      local image = {
        type = "image_url",
        image_url = { url = string.format("data:%s;base64,%s", mime_type, base64_image) },
      }

      options.messages[#options.messages] = {
        role = "user",
        content = {
          image,
          { type = "text", text = text },
        },
      }

      ::continue::
    end
  end

  return options
end

function M.ask(prompt_buffer)
  local max_turns_without_user_input = vim.b[prompt_buffer].llm_sidekick_max_turns_without_user_input or
      MAX_TURNS_WITHOUT_USER_INPUT
  vim.b[prompt_buffer].llm_sidekick_max_turns_without_user_input = max_turns_without_user_input

  local buf_lines = vim.api.nvim_buf_get_lines(prompt_buffer, 0, -1, false)

  local file_editor = require("llm-sidekick.file_editor")
  local last_assistant_lnum = file_editor.find_last_assistant_start_line(buf_lines)
  local last_user_lnum = file_editor.find_last_user_start_line(buf_lines)

  local full_prompt = table.concat(buf_lines, "\n")
  local prompt = M.parse_prompt(full_prompt, prompt_buffer)

  local model_settings = settings.get_model_settings(prompt.settings.model)

  if not model_settings.just_chatting then
    prompt.tools = require("llm-sidekick.tools")
  end

  prompt.settings.model = model_settings.name

  if model_settings.reasoning_effort then
    prompt.settings.reasoning_effort = model_settings.reasoning_effort
  end

  if model_settings.use_max_completion_tokens then
    prompt.settings.max_completion_tokens = prompt.settings.max_tokens
    prompt.settings.max_tokens = nil
  end

  if model_settings.no_system_prompt then
    -- prepend the system prompt to the first message
    local system_prompt = vim.tbl_filter(function(m) return m.role == "system" end, prompt.messages)[1]
    prompt.messages = vim.tbl_filter(function(m) return m.role ~= "system" end, prompt.messages)
    if system_prompt then
      prompt.messages[1].content = system_prompt.content .. "\n\n" .. prompt.messages[1].content
    end
  end

  if last_assistant_lnum < last_user_lnum then
    vim.api.nvim_buf_set_lines(prompt_buffer, -1, -1, false, { "", "ASSISTANT: " })
  end

  local client = require "llm-sidekick.openai".new({ url = "http://localhost:1993/v1/chat/completions" })

  local in_reasoning_tag = false
  local debug_error_handler = function(err)
    return debug.traceback(err, 3)
  end

  local tool_calls = {}

  -- Start the spinner to indicate we're waiting for the first token
  spinner.start(prompt_buffer)

  local job = client:chat(prompt, function(state, chars)
    if not vim.api.nvim_buf_is_loaded(prompt_buffer) then
      utils.stop(prompt_buffer)
      return
    end

    local success, err = xpcall(function()
      if state == message_types.ERROR then
        error(string.format("Error: %s", vim.inspect(chars)))
      end

      if state == message_types.ERROR_MAX_TOKENS then
        error("Max tokens exceeded")
      end

      if state == message_types.TOOL_START or state == message_types.TOOL_DELTA or state == message_types.TOOL_STOP then
        local tool_call = chars
        local tc = tool_utils.find_tool_call_by_id(tool_call.id, { buffer = prompt_buffer })
        if tc then
          tool_call.state.lnum = tc.state.lnum
          tool_call.state.end_lnum = tc.state.end_lnum
          tool_call.state.extmark_id = tc.state.extmark_id
        end

        local tool = tool_utils.find_tool_for_tool_call(tool_call)

        if not tool then
          error("Tool not found: " .. tool_call.name)
        end

        if state == message_types.TOOL_START then
          local last_two_lines = vim.api.nvim_buf_get_lines(prompt_buffer, -3, -1, false)
          if last_two_lines[#last_two_lines] == "" then
            if last_two_lines[1] ~= "" then
              chat.paste_at_end("\n", prompt_buffer)
            end
          else
            chat.paste_at_end("\n\n", prompt_buffer)
          end

          tool_call.state.lnum = vim.api.nvim_buf_line_count(prompt_buffer)
          tool_utils.add_tool_call_to_buffer({ buffer = prompt_buffer, tool_call = tool_call })

          if tool.start then
            tool.start(tool_call, { buffer = prompt_buffer })
          end
        elseif state == message_types.TOOL_DELTA then
          if tool.delta then
            tool.delta(tool_call, { buffer = prompt_buffer })
          end
        elseif state == message_types.TOOL_STOP then
          if tool.stop then
            tool.stop(tool_call, { buffer = prompt_buffer })
          end

          tool_call.state.end_lnum = math.max(vim.api.nvim_buf_line_count(prompt_buffer), tool_call.state.lnum)

          chat.paste_at_end("\n\n", prompt_buffer)

          tool_call.state.extmark_id = vim.api.nvim_buf_set_extmark(
            prompt_buffer,
            vim.g.llm_sidekick_ns,
            tool_call.state.lnum - 1,
            0,
            { invalidate = true }
          )
          table.insert(tool_calls, tool_call)
          tool_utils.update_tool_call_in_buffer({ buffer = prompt_buffer, tool_call = tool_call })
          tool_call.tool = tool

          if tool_call.result == nil and tool.is_show_diagnostics(tool_call) then
            diagnostic.add_tool_call(
              tool_call,
              prompt_buffer,
              vim.diagnostic.severity.HINT,
              string.format("▶ %s (<leader>aa)", tool.spec.name)
            )
          end
        end

        return
      end

      if state == message_types.REASONING and not in_reasoning_tag then
        chat.paste_at_end("\n\n<llm_sidekick_thinking>\n", prompt_buffer)
        in_reasoning_tag = true
      end

      if state == message_types.DATA and in_reasoning_tag then
        chat.paste_at_end("\n</llm_sidekick_thinking>\n\n", prompt_buffer)
        in_reasoning_tag = false
      end

      chat.paste_at_end(chars, prompt_buffer)
    end, debug_error_handler)

    if not success then
      vim.notify(vim.inspect(err), vim.log.levels.ERROR)
      utils.stop(prompt_buffer)
      return
    end

    if message_types.DONE == state then
      if vim.api.nvim_buf_is_loaded(prompt_buffer) then
        spinner.stop(prompt_buffer)
      else
        utils.stop(prompt_buffer)
        return
      end

      -- Run auto-acceptable tools until we find one that's not auto-acceptable
      -- and execute the callback when all tools have completed
      tool_utils.run_auto_acceptable_tools_with_callback(tool_calls, { buffer = prompt_buffer },
        function()
          if not vim.api.nvim_buf_is_loaded(prompt_buffer) then
            utils.stop(prompt_buffer)
            return
          end

          local tool_call_ids = vim.tbl_values(vim.tbl_map(function(tc) return tc.id end, tool_calls))
          local last_assistant_tool_calls = tool_utils.get_tool_calls_in_last_assistant_message({ buffer = prompt_buffer })
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

          max_turns_without_user_input = vim.b[prompt_buffer].llm_sidekick_max_turns_without_user_input

          if no_tool_calls or has_pending_tools or max_turns_without_user_input <= 0 or model_settings.just_chatting then
            local last_two_lines = vim.api.nvim_buf_get_lines(prompt_buffer, -3, -1, false)
            if last_two_lines[#last_two_lines] == "" then
              if last_two_lines[1] == "" then
                chat.paste_at_end("USER: ", prompt_buffer)
              else
                chat.paste_at_end("\nUSER: ", prompt_buffer)
              end
            else
              chat.paste_at_end("\n\nUSER: ", prompt_buffer)
            end
          else
            vim.b[prompt_buffer].llm_sidekick_max_turns_without_user_input = max_turns_without_user_input - 1
            M.ask(prompt_buffer)
          end
        end)
    end
  end)

  vim.b[prompt_buffer].llm_sidekick_job_pid = job.pid
end

---Read the entire contents of a file
---@param path string The path to the file to read
---@return string content The file contents or an empty string if file cannot be opened
function M.read_file(path)
  return fs.read_file(path) or ""
end

return M
