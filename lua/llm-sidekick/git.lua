local utils = require("llm-sidekick.utils")
local settings = require("llm-sidekick.settings")
local openai = require("llm-sidekick.openai")

local M = {}

-- Asynchronously commits files that are already staged.
-- @param files table List of file paths that were modified (for logging purposes).
-- @param commit_message string The commit message.
-- @param callback function Optional callback function to execute after successful commit.
function M.commit_staged_files(files, commit_message, callback)
  if not files or #files == 0 then
    utils.log("No files provided for committing.", vim.log.levels.WARN)
    return
  end

  -- Ensure commit message is a single line and not empty
  commit_message = vim.split(commit_message or "", "\n")[1]
  if not commit_message or vim.trim(commit_message) == "" then
    commit_message = string.format("chore: Auto-commit changes to %d files", #files)
    utils.log("Commit message was empty, using fallback: " .. commit_message, vim.log.levels.WARN)
  end

  local cmd_commit = { "commit", "-m", commit_message }
  vim.loop.spawn("git", { args = cmd_commit, stdio = { nil, nil, nil } }, function(commit_code, commit_signal)
    if commit_code ~= 0 then
      local err_msg = string.format("Failed to commit files: exit code %d, signal %d", commit_code, commit_signal)
      vim.schedule(function()
        utils.log(err_msg, vim.log.levels.ERROR)
        vim.notify(err_msg, vim.log.levels.ERROR)
      end)
      return
    end

    utils.log(string.format("Successfully committed files: %s with message: '%s'", table.concat(files, ", "),
      commit_message), vim.log.levels.INFO)

    if callback then
      callback(commit_message)
    end
  end)
end

-- Asynchronously stages files.
-- @param files table List of file paths to stage.
-- @param callback function Optional callback function to execute after successful staging.
function M.stage_files(files, callback)
  if not files or #files == 0 then
    utils.log("No files provided for staging.", vim.log.levels.WARN)
    return
  end

  local files_to_add = vim.deepcopy(files) -- Clone the table as 'add' is variadic
  local git_add_args = vim.list_extend({ "add" }, files_to_add)

  vim.loop.spawn("git", { args = git_add_args, stdio = { nil, nil, nil } }, function(code, signal)
    if code ~= 0 then
      local files_str = table.concat(files, " ")
      local err_msg = string.format("Failed to stage files (%s): exit code %d, signal %d", files_str, code, signal)
      vim.schedule(function()
        utils.log(err_msg, vim.log.levels.ERROR)
        vim.notify(err_msg, vim.log.levels.ERROR)
      end)
      return
    end

    utils.log(string.format("Successfully staged files: %s", table.concat(files, ", ")), vim.log.levels.DEBUG)
    if callback then callback() end
  end)
end

-- Gets the diff for multiple files using git diff
-- @param files table List of file paths to get diffs for
-- @param callback function Callback function with the diff content (string)
function M.get_file_diffs(files, callback)
  if not files or #files == 0 then
    return
  end

  local cmd = { "diff", "--cached", "--name-only" }
  for _, file in ipairs(files) do
    table.insert(cmd, file)
  end

  -- First get the list of files that have changes
  require('plenary.job'):new({
    command = "git",
    args = cmd,
    on_exit = function(j, return_val)
      if return_val > 1 then -- diff returns 1 if there are differences, 0 if none
        local stderr = table.concat(j:stderr_result() or {}, "\n")
        utils.log(string.format("Failed to get diff for files: %s", stderr), vim.log.levels.ERROR)
        return
      end

      local changed_files = {}
      local result = j:result() or {}
      for _, file in ipairs(result) do
        if file ~= "" then
          changed_files[file] = true
        end
      end

      if vim.tbl_isempty(changed_files) then
        return
      end

      -- Now get the actual diff content for all files at once
      local diff_cmd = { "diff", "--cached" }
      for _, file in ipairs(files) do
        table.insert(diff_cmd, file)
      end

      require('plenary.job'):new({
        command = "git",
        args = diff_cmd,
        on_exit = function(j2, return_val2)
          if return_val2 > 1 then
            local stderr = table.concat(j2:stderr_result() or {}, "\n")
            utils.log(string.format("Failed to get diff content: %s", stderr), vim.log.levels.ERROR)
            return
          end

          -- Parse the combined diff output into per-file diffs
          local diff_lines = j2:result() or {}
          callback(table.concat(diff_lines, "\n"))
        end,
      }):start()
    end,
  }):start()
end

-- Generates a commit message using the LLM.
-- @param files table List of file paths that were modified.
-- @param callback function Callback function with the generated message (string) or nil on error.
-- @param context string|nil Optional additional context or instructions for the commit message
function M.generate_commit_message(files, callback, context)
  utils.log("Generating commit message for files: " .. vim.inspect(files), vim.log.levels.DEBUG)

  local model_alias = settings.get_auto_commit_model()
  local model_settings = settings.get_model_settings(model_alias)

  M.get_file_diffs(files, function(diffs)
    local system_prompt = [[
You are an expert software engineer that generates concise, one-line Git commit messages based on the provided diffs.
Review the provided context and diffs which are about to be committed to a git repo.
Review the diffs carefully. Generate a one-line commit message for those changes.
The commit message should be structured as follows: <type>: <description>
Use these for <type>: fix, feat, build, chore, ci, docs, style, refactor, perf, test

Ensure the commit message:
- Starts with the appropriate prefix.
- Is in the imperative mood (e.g., "add feature" not "added feature" or "adding feature").
- Does not exceed 72 characters.

Reply only with the one-line commit message, without any additional text, explanations, or line breaks.]]

    if context and vim.trim(context) ~= "" then
      system_prompt = system_prompt .. "\n\nAdditional context for this commit (provided by the user):\n" .. context
    end

    local user_prompt = "`git diff --cached` output:\n" .. diffs

    local messages = {
      { role = "system", content = system_prompt },
      { role = "user",   content = user_prompt },
    }

    local completion_settings = {
      model = model_settings.name,
      temperature = 0.2,
      max_tokens = 200,
    }

    local client = openai.new({ url = "http://localhost:1993/v1/chat/completions" })

    client:generate_completion({ messages = messages, settings = completion_settings }, function(err, content)
      local commit_message
      if err then
        utils.log("Failed to generate commit message: " .. err, vim.log.levels.ERROR)
        -- Fallback to a generic message
        commit_message = string.format("chore: Auto-commit changes to %d files", #files)
      else
        -- Clean up the message: trim whitespace, remove potential quotes
        commit_message = vim.trim(content or "")
        commit_message = commit_message:gsub('^["\']', ''):gsub('["\']$', '')
        commit_message = vim.split(commit_message, "\n")[1] -- Ensure single line

        if commit_message == "" then
          utils.log("LLM generated an empty commit message. Using fallback.", vim.log.levels.WARN)
          commit_message = string.format("chore: Auto-commit changes to %d files", #files)
        end
      end

      utils.log("Generated commit message: " .. commit_message, vim.log.levels.DEBUG)
      callback(commit_message)
    end)
  end)
end

-- Gets the list of staged files (files added to the index but not yet committed).
-- @param callback function Callback function with the list of staged file paths (table)
function M.get_staged_files(callback)
  require('plenary.job'):new({
    command = 'git',
    args = { 'diff', '--cached', '--name-only' },
    on_exit = function(j, return_val)
      if return_val > 1 then
        local stderr = table.concat(j:stderr_result() or {}, "\n")
        require('llm-sidekick.utils').log(
          string.format("Failed to get staged files: %s", stderr), vim.log.levels.ERROR)
        callback({})
        return
      end
      local result = j:result() or {}
      local files = {}
      for _, file in ipairs(result) do
        if file ~= "" then
          table.insert(files, file)
        end
      end
      callback(files)
    end,
  }):start()
end

return M
