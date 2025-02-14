local chat = require("llm-sidekick.chat")

local spec = {
  name = "run_command",
  description = [[
Execute a shell command and get its output.

Available tools include standard shell commands as well as:
- ripgrep (rg) for fast code searching
- fd for file finding

CRITICAL REQUIREMENTS:
- `command`: The command to execute.]],
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
  show_diagnostics = function(_) return true end,
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
    if command:find("|") or command:find(";") or command:find("&&") or command:find(">") then
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
  run = function(tool_call, _)
    local command = vim.trim(tool_call.parameters.command or "")
    local shell = vim.o.shell or "bash"
    local cwd = vim.fn.getcwd()

    -- Ensure the working directory exists
    if not vim.fn.isdirectory(cwd) then
      error(string.format("Working directory does not exist: %s", cwd))
    end

    local output_file = vim.fn.tempname()
    local full_command = string.format('%s -c "%s > %s 2>&1"', shell, command, output_file)
    local output = ""
    local exit_code = nil

    local job_id = vim.fn.jobstart(full_command, {
      cwd = cwd,
      on_exit = function(_, code)
        output = table.concat(vim.fn.readfile(output_file), "\n")
        vim.fn.delete(output_file)
        exit_code = code
      end
    })

    if job_id <= 0 then
      error(string.format("Failed to start command: %s", command))
    end

    -- Wait for the job to complete
    vim.fn.jobwait({ job_id })

    -- Format the final output with exit code and command output
    return string.format("Exit Code: %d\nOutput:\n%s", exit_code, output)
  end
}
