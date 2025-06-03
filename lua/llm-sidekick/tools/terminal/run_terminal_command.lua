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

local json_props = string.format([[{
  "command": %s,
  "explanation": %s
}]], vim.json.encode(spec.input_schema.properties.command), vim.json.encode(spec.input_schema.properties.explanation))

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
      -- File/Directory Operations
      "rg", "fd", "cat", "ls", "exa", "tree", "find", "head", "tail", "grep", "less",
      "stat", "diff", "sort", "uniq", "cut", "dirname", "basename",

      -- Git Operations
      "gh", "git status", "git log", "git diff", "git show", "git branch", "git fetch", "git pull",
      "git remote", "git tag", "git rev-parse", "git ls-files", "git blame",

      -- System Information
      "pwd", "whoami", "uname", "which", "type", "echo", "ps", "df", "du", "uptime", "date", "cal",

      -- Network Tools
      "curl", "ping", "traceroute", "nslookup", "dig", "host", "netstat",

      -- Data Processing
      "jq", "wc", "tr", "column",

      -- Package Managers
      "npm list", "yarn list", "pip list", "brew list", "cargo list",

      -- Development Tools
      "docker ps", "docker images",

      -- Testing and Linting
      -- General
      "make test", "make lint", "luacheck",

      -- Ruby/Rails
      "rspec", "minitest", "cucumber", "rubocop", "standardrb", "bundle exec rspec", "bundle exec rubocop",
      "bin/rspec", "bin/rubocop", "bin/rails test", "bin/rake test", "bin/cucumber", "bin/minitest",
      "rails test", "rake test",

      -- JavaScript/TypeScript
      "jest", "mocha", "jasmine", "vitest", "cypress", "eslint", "prettier", "tslint", "npm test", "npm run test",
      "yarn test", "yarn lint", "npx eslint", "npx prettier", "npx jest",

      -- Python
      "pytest", "unittest", "nose", "behave", "flake8", "pylint", "black", "mypy", "isort",

      -- Go
      "go test", "golint", "golangci-lint", "staticcheck", "go vet",

      -- PHP
      "phpunit", "pest", "codeception", "php-cs-fixer", "phpcs", "phpstan", "psalm", "composer test", "composer lint",
    }

    vim.list_extend(safe_commands, require("llm-sidekick.settings").safe_terminal_commands())

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
    chat.paste_at_end(string.format("**%s**\n", vim.fn.fnamemodify(vim.o.shell or "bash", ":t")), opts.buffer)
    tool_call.state.command_closed = false
  end,
  -- Handle incremental updates for streaming command and output
  delta = function(tool_call, opts)
    local command = vim.trim(tool_call.parameters.command or "")
    local command_written = tool_call.state.command_written or 0
    local explanation = vim.trim(tool_call.parameters.explanation or "")
    local explanation_written = tool_call.state.explanation_written or 0

    if command and command_written < #command then
      if command_written == 0 and explanation_written > 0 then
        chat.paste_at_end("\n", opts.buffer)
      end
      if command_written == 0 then
        chat.paste_at_end("````sh\n", opts.buffer)
      end
      chat.paste_at_end(command:sub(command_written + 1), opts.buffer)
      tool_call.state.command_written = #command
    end

    if explanation and explanation_written < #explanation then
      if command_written > 0 and explanation_written == 0 then
        chat.paste_at_end("\n````\n", opts.buffer)
        tool_call.state.command_closed = true
      end

      if explanation_written == 0 then
        chat.paste_at_end("> ", opts.buffer)
      end

      chat.paste_at_end(explanation:sub(explanation_written + 1), opts.buffer)
      tool_call.state.explanation_written = #explanation
    end
  end,
  stop = function(tool_call, opts)
    if not tool_call.state.command_closed then
      chat.paste_at_end("\n````", opts.buffer)
      tool_call.state.command_closed = true
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
          output = "Stdout:\n````" .. table.concat(stdout, "\n") .. "````"
        end

        local stderr = j:stderr_result()
        if stderr and not vim.tbl_isempty(stderr) then
          output = output .. "\n\nStderr:\n````" .. table.concat(stderr, "\n") .. "````"
        end

        -- Store the output in tool_call state for access in the after_success callback
        tool_call.state.result.success = exit_code == 0
        tool_call.state.result.result = string.format("Exit code: %d\n%s", exit_code, output)

        -- Update the command text from "Execute" to "Executed"
        vim.schedule(function()
          -- Handle multi-line commands by showing only the first line with "..." if needed
          local display_command = command
          if command:find("\n") then
            display_command = command:match("^([^\n]+)") .. "..."
          end

          local final_lines = { string.format("✓ Executed: `%s`", display_command) }

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
