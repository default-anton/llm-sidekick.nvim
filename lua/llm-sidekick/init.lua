local chat          = require "llm-sidekick.chat"
local message_types = require "llm-sidekick.message_types"
local fs            = require "llm-sidekick.fs"
local settings      = require "llm-sidekick.settings"
local diagnostic    = require("llm-sidekick.diagnostic")
local tool_utils    = require("llm-sidekick.tools.utils")


MAX_TURNS_WITHOUT_USER_INPUT = 5

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
  local lines = vim.split(prompt, "\n", { plain = true })
  for _, line in ipairs(lines) do
    if line:sub(1, 7) == "SYSTEM:" and not processed_keys.system then
      options.messages[#options.messages + 1] = { role = "system", content = line:sub(8) }
      processed_keys.system = true
      goto continue
    end
    if line:sub(1, 5) == "USER:" then
      options.messages[#options.messages + 1] = { role = "user", content = line:sub(6) }
      goto continue
    end
    if line:sub(1, 10) == "ASSISTANT:" then
      options.messages[#options.messages + 1] = { role = "assistant", content = line:sub(11) }
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

    if #options.messages > 0 then
      options.messages[#options.messages].content = options.messages[#options.messages].content .. "\n" .. line
    end

    ::continue::
  end

  for message_index, message in ipairs(options.messages) do
    message.content = vim.trim(message.content or "")

    if message.role == "assistant" then
      -- NOTE: delete all thinking tags
      message.content = message.content:gsub("<llm_sidekick_thinking>.-</llm_sidekick_thinking>", "")
      message.content = message.content:gsub("<think>.-</think>", "") -- for deepseek-r1-distill-llama-70b
      -- Extract tool calls from the content
      local tool_calls = {}
      local tool_call_results = {}
      for id in message.content:gmatch('<llm_sidekick_tool id="(.-)" name=".-">') do
        local tool_call = tool_utils.find_tool_call_by_id(id, { buffer = buffer })
        if not tool_call then
          goto next_tool_call
        end

        table.insert(tool_calls, {
          id = tool_call.call.id,
          type = "function",
          ["function"] = {
            name = tool_call.call.name,
            arguments = vim.json.encode(tool_call.call.parameters),
          }
        })

        local result = tool_call.call.result
        if type(result) == "boolean" then
          result = { success = result }
        end
        if not result then
          result = { result = "User hasn't accepted the tool yet" }
        end

        result = vim.json.encode(result)

        table.insert(tool_call_results, {
          role = "tool",
          tool_call_id = tool_call.call.id,
          content = result,
        })

        ::next_tool_call::
      end

      message.content = message.content:gsub("<llm_sidekick_tool id=\".-\" name=\".-\">.-</llm_sidekick_tool>", "")
      message.content = vim.trim(message.content)

      if #tool_calls > 0 then
        message.tool_calls = tool_calls
      end

      if #tool_call_results > 0 then
        for j, tool_call_result in ipairs(tool_call_results) do
          table.insert(options.messages, message_index + j, tool_call_result)
        end
      end
    end
  end

  -- Remove last empty user message if the last message is a tool result
  if #options.messages > 1 then
    local last_msg = options.messages[#options.messages]
    local prev_msg = options.messages[#options.messages - 1]
    if last_msg.role == "user" and vim.trim(last_msg.content) == "" and prev_msg.role == "tool" then
      table.remove(options.messages)
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

function M.ask(prompt_buffer, max_turns_without_user_input)
  max_turns_without_user_input = max_turns_without_user_input or MAX_TURNS_WITHOUT_USER_INPUT

  -- Set up a buffer-local autocmd to block manual typing during LLM response.
  -- Create an augroup for the prompt buffer autocmds
  local augroup = vim.api.nvim_create_augroup("LLMSidekickPrompt", { clear = true })

  -- Create the autocmd to block input
  vim.api.nvim_create_autocmd("InsertCharPre", {
    group = augroup,
    buffer = prompt_buffer,
    callback = function()
      -- Set v:char to an empty string to prevent the character from being inserted
      vim.v.char = ""
    end,
  })

  -- Add an autocmd to clean up when the buffer is deleted
  vim.api.nvim_create_autocmd("BufDelete", {
    group = augroup,
    buffer = prompt_buffer,
    callback = function()
      vim.api.nvim_del_augroup_by_name("LLMSidekickPrompt")
    end,
    once = true,
  })

  local function cleanup()
    -- Remove the augroup which will clean up all associated autocmds
    vim.api.nvim_del_augroup_by_name("LLMSidekickPrompt")
  end

  local buf_lines = vim.api.nvim_buf_get_lines(prompt_buffer, 0, -1, false)
  local full_prompt = table.concat(buf_lines, "\n")
  local prompt = M.parse_prompt(full_prompt, prompt_buffer)

  prompt.tools = require("llm-sidekick.tools")

  local model_settings = settings.get_model_settings(prompt.settings.model)
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

  -- first assistant message
  if max_turns_without_user_input == MAX_TURNS_WITHOUT_USER_INPUT then
    vim.api.nvim_buf_set_lines(prompt_buffer, -1, -1, false, { "", "ASSISTANT: " })
  end

  local client
  if prompt.settings.model:find("gemini") then
    client = require "llm-sidekick.gemini".new()
  else
    client = require "llm-sidekick.openai".new({ url = "http://localhost:1993/v1/chat/completions" })
  end

  local in_reasoning_tag = false
  local debug_error_handler = function(err)
    return debug.traceback(err, 3)
  end

  local tool_calls = {}

  client:chat(prompt, function(state, chars)
    if not vim.api.nvim_buf_is_valid(prompt_buffer) then
      cleanup()
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
        local tool = tool_utils.find_tool_for_tool_call(tool_call)

        if not tool then
          error("Tool not found: " .. tool_call.name)
        end

        if state == message_types.TOOL_START then
          local last_line = vim.api.nvim_buf_get_lines(prompt_buffer, -2, -1, false)[1]
          local needs_newlines = last_line and vim.trim(last_line) ~= ""
          if tool.run then
            chat.paste_at_end(
              string.format("%s<llm_sidekick_tool id=\"%s\" name=\"%s\">\n",
                needs_newlines and "\n\n" or "",
                tool_call.id,
                tool_call.name
              ),
              prompt_buffer
            )
          else
            chat.paste_at_end(needs_newlines and "\n\n" or "", prompt_buffer)
          end

          local line_num = vim.api.nvim_buf_line_count(prompt_buffer)

          tool_utils.add_tool_call_to_buffer({
            buffer = prompt_buffer,
            tool_call = tool_call,
            lnum = line_num,
          })

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

          tool_call.tool = tool
          table.insert(tool_calls, tool_call)

          local last_line = vim.api.nvim_buf_get_lines(prompt_buffer, -2, -1, false)[1]
          local needs_newline = last_line and vim.trim(last_line) ~= ""
          if needs_newline then
            chat.paste_at_end("\n", prompt_buffer)
          end

          local lnum = vim.tbl_filter(function(tc) return tc.call.id == tool_call.id end,
            vim.b[prompt_buffer].llm_sidekick_tool_calls)[1].lnum

          tool_utils.update_tool_call_in_buffer({
            buffer = prompt_buffer,
            tool_call = tool_call,
          })

          if tool.run then
            diagnostic.add_tool_call(
              tool_call,
              prompt_buffer,
              lnum,
              vim.diagnostic.severity.HINT,
              string.format("▶ %s (<leader>aa)", tool.spec.name)
            )
            chat.paste_at_end("</llm_sidekick_tool>\n\n", prompt_buffer)
          else
            chat.paste_at_end("\n\n", prompt_buffer)
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
      cleanup()
      vim.notify(vim.insect(err), vim.log.levels.ERROR)
      return
    end

    if message_types.DONE == state and vim.api.nvim_buf_is_valid(prompt_buffer) then
      cleanup()

      for _, tool_call in ipairs(tool_calls) do
        if tool_call.tool.run and tool_call.result == nil and tool_call.tool.is_auto_acceptable(tool_call) then
          tool_call.tool.run(tool_call, { buffer = prompt_buffer })
        end
      end

      local requires_user_input = vim.tbl_contains(
        tool_calls,
        function(tc)
          return tc.result == nil and not tc.tool.is_auto_acceptable(tc)
        end,
        { predicate = true }
      )

      if not requires_user_input and max_turns_without_user_input > 0 then
        M.ask(prompt_buffer, max_turns_without_user_input - 1)
        return
      end

      success, err = xpcall(function()
        chat.paste_at_end("\n\nUSER: ", prompt_buffer)
      end, debug_error_handler)

      if not success then
        vim.notify(vim.insect(err), vim.log.levels.ERROR)
        return
      end

      local lines = vim.api.nvim_buf_get_lines(prompt_buffer, 0, -1, false)
      local file_editor = require("llm-sidekick.file_editor")
      local assistant_start_line = file_editor.find_last_assistant_start_line(lines)
      if assistant_start_line ~= -1 then
        local assistant_end_line = file_editor.find_assistant_end_line(
          assistant_start_line,
          lines
        )
        local modification_blocks = file_editor.find_and_parse_modification_blocks(
          prompt_buffer,
          assistant_start_line,
          assistant_end_line
        )
        for _, block in ipairs(modification_blocks) do
          diagnostic.add_diagnostic(
            prompt_buffer,
            block.start_line,
            block.start_line,
            block.raw_block,
            vim.diagnostic.severity.HINT,
            "Suggested Change"
          )
        end
      end
    end
  end)
end

---Read the entire contents of a file
---@param path string The path to the file to read
---@return string content The file contents or an empty string if file cannot be opened
function M.read_file(path)
  return fs.read_file(path) or ""
end

return M
