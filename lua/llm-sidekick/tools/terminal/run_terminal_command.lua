local chat = require("llm-sidekick.chat")
local Job = require('plenary.job')

local spec = {
  name = "run_terminal_command",
  description = "Execute a shell command and get its exit code and output.",
  input_schema = {
    type = "object",
    properties = {
      command = {
        type = "string"
      },
      explanation = {
        type = "string",
        description = "One sentence explanation of why this command needs to be run and how it contributes to the goal"
      }
    },
    required = { "command", "explanation" }
  }
}

local json_props = [[{
  "command": { "type": "string" },
  "explanation": { "type": "string" }
}]]

return {
  spec = spec,
  json_props = json_props,
  is_show_diagnostics = function(_) return true end,
  is_auto_acceptable = function(tool_call)
    if require("llm-sidekick.settings").auto_accept_terminal_commands() then
      return true
    end

    -- List of commands that are safe to auto-accept
    local safe_commands = {
      -- File viewing/searching
      "rg", "fd", "cat", "ls", "exa", "tree", "find", "head", "tail", "grep", "less",
      -- Git read operations
      "git status", "git log", "git diff", "git show", "git branch",
      -- System info
      "pwd", "whoami", "uname", "which", "type", "echo"
    }

    local command = vim.trim(tool_call.parameters.command or "")

    -- Basic safety checks
    if command:find(";") or command:find("&&") or command:find(">") then
      return false
    end

    -- Extract the base command (everything before the first space)
    local base_command = command:match("^([^%s]+)")
    if not base_command then
      return false
    end

    -- For git commands, check the full "git subcommand"
    if base_command == "git" then
      local git_command = command:match("^git%s+([^%s]+)")
      if not git_command then
        return false
      end
      command = "git " .. git_command
    end

    -- Check if the command is in our safe list
    for _, safe_cmd in ipairs(safe_commands) do
      if command:find("^" .. vim.pesc(safe_cmd)) then
        return true
      end
    end

    return false
  end,
  -- Initialize the command execution display
  start = function(tool_call, opts)
    chat.paste_at_end("**Execute:** ``", opts.buffer)
    tool_call.state.command_line = vim.api.nvim_buf_line_count(opts.buffer)

    chat.paste_at_end("\n> ", opts.buffer)
    tool_call.state.explanation_line = vim.api.nvim_buf_line_count(opts.buffer)
  end,
  -- Handle incremental updates for streaming command and output
  delta = function(tool_call, opts)
    local command = vim.trim(tool_call.parameters.command or "")
    local command_written = tool_call.state.command_written or 0
    local explanation = vim.trim(tool_call.parameters.explanation or "")
    local explanation_written = tool_call.state.explanation_written or 0

    -- Update command display
    if command and command_written < #command then
      vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.command_line - 1, tool_call.state.command_line, false,
        { string.format("**Execute:** `%s`", command) })
      tool_call.state.command_written = #command
    end

    -- Update explanation if provided and not yet written
    if explanation and explanation_written < #explanation then
      vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.explanation_line - 1, tool_call.state.explanation_line,
        false,
        { string.format("> %s", explanation:gsub("\n", " ")) })
      tool_call.state.explanation_written = #explanation
    end
  end,
  -- Execute the command asynchronously
  run = function(tool_call, opts)
    local cwd = vim.fn.getcwd()
    local shell = vim.o.shell or "bash"
    local command = vim.trim(tool_call.parameters.command or "")

    -- Store initial state
    tool_call.state.result = { success = false, result = nil }

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
        tool_call.state.result.success = exit_code == 0
        tool_call.state.result.result = string.format("Exit code: %d\n%s", exit_code, output)

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
  end
}
