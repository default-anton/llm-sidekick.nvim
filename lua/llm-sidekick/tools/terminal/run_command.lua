local chat = require("llm-sidekick.chat")
local Job = require('plenary.job')

local TIMEOUT = 5000

local spec = {
  name = "run_command",
  description = "Execute a shell command and get its exit code and output.",
  input_schema = {
    type = "object",
    properties = {
      command = {
        type = "string"
      }
    },
    required = {
      "command"
    }
  }
}

local json_props = [[{
  "command": { "type": "string" }
}]]

return {
  spec = spec,
  json_props = json_props,
  is_show_diagnostics = function(tool_call)
    local command = vim.trim(tool_call.parameters.command or "")
    if command == "" then
      return true
    end

    return not require("llm-sidekick.tools.terminal.run_command").is_auto_acceptable(tool_call)
  end,
  is_auto_acceptable = function(tool_call)
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
  end,
  -- Handle incremental updates for streaming command and output
  delta = function(tool_call, opts)
    local command = vim.trim(tool_call.parameters.command or "")
    local command_written = tool_call.state.command_written or 0

    -- Update command display
    if command and command_written < #command then
      vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.command_line - 1, tool_call.state.command_line, false,
        { string.format("**Execute:** `%s`", command) })
      tool_call.state.command_written = #command
    end
  end,
  -- Execute the command
  run = function(tool_call, opts)
    local cwd = vim.fn.getcwd()
    local shell = vim.o.shell or "bash"
    local command = vim.trim(tool_call.parameters.command or "")
    local output = ""
    local exit_code = nil

    Job:new({
      cwd = cwd,
      command = shell,
      args = { "-c", command },
      interactive = false,
      on_exit = function(j, return_val)
        exit_code = return_val

        local stdout = j:result()
        if stdout and not vim.tbl_isempty(stdout) then
          output = "Stdout: " .. table.concat(stdout, "\n")
        end

        local stderr = j:stderr_result()
        if stderr and not vim.tbl_isempty(stderr) then
          output = output .. "\nStderr: " .. table.concat(stderr, "\n")
        end
      end,
    }):sync(TIMEOUT)

    -- Update the command text from "Execute" to "Executed"
    vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.lnum - 1, tool_call.state.end_lnum, false,
      { string.format("✓ Executed: `%s`", command) })

    -- Format the final output with exit code and command output
    return string.format("Exit code: %d\n%s", exit_code, output)
  end
}
