local signs = require("llm-sidekick.signs")
local tc = require("llm-sidekick.tools.tool_calls")

local description = [[
Create or overwrite a file with the specified content.

**FORMAT:**

**Create:** `<path/to/file>`
```<filetype>
<file content>
```

**Critical Requirements:**
- **Create:** The path to the file. This must be relative to the project root, or it will be rejected.
- Content: The complete content of the file to be written. The file will be overwritten if it already exists. Use triple backticks to enclose the content, and include the filetype.
- The provided `filetype` will be used for syntax highlighting.
- The entire file content must be provided. This tool is not for appending or inserting into existing files.
- The tool will create any necessary directories in the path if they do not already exist.

**Example:**

**Create:** `src/components/Button.jsx`
```jsx
import React from 'react';

function Button({ onClick, children }) {
  return (
    <button onClick={onClick}>{children}</button>
  );
}

export default Button;
```]]

local function find_tool_calls(opts)
  local pattern = "%*%*Create:%*%*%s-`(.-)`\n```(%w*)\n(.-)```"
  local attribute_names = {
    "path",
    "filetype",
    "content",
  }
  local tool_calls = tc.find_tool_calls(
    opts.buffer,
    opts.start_search_line,
    opts.end_search_line,
    pattern,
    attribute_names
  )

  return vim.tbl_filter(function(tool_call)
    local abs_path = vim.fn.fnamemodify(tool_call.path, ":p")
    local cwd = vim.fn.getcwd()
    if not vim.startswith(abs_path, cwd) then
      vim.api.nvim_err_writeln(string.format("The file path '%s' must be within the current working directory '%s'",
        abs_path, cwd))

      return false
    end

    return true
  end, tool_calls)
end

local function find_tool_at_cursor(opts)
  local tool_calls = find_tool_calls(opts)

  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

  for _, tool_call in ipairs(tool_calls) do
    if cursor_line >= tool_call.start_line and cursor_line <= tool_call.end_line then
      return tool_call
    end
  end
end

local function error_handler(err)
  return debug.traceback(err, 3)
end

local function apply_tool_call(tool_call)
  local path = vim.trim(tool_call.path or "")
  local content = tool_call.content or ""

  local dir = vim.fn.fnamemodify(path, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    local success = vim.fn.mkdir(dir, "p")
    if success == 0 then
      error(string.format("Failed to create directory: %s", dir))
    end
  end

  local buf = vim.fn.bufnr(path)
  if buf == -1 then
    buf = vim.fn.bufadd(path)
    if buf == 0 then
      error(string.format("Failed to open file: %s", path))
    end
  end
  vim.fn.bufload(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n"))

  local ok, err = xpcall(function()
    vim.api.nvim_buf_call(buf, function()
      vim.cmd('write')
    end)
  end, error_handler)

  if not ok then
    -- Unload the buffer if it wasn't open before
    if vim.fn.bufloaded(buf) == 1 and vim.fn.bufwinnr(buf) == -1 then
      vim.cmd('bdelete ' .. buf)
    end
    error(string.format("Failed to write to file: %s", err))
  end

  -- Refresh any open windows displaying this file
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local win_buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_buf_get_name(win_buf) == path then
      vim.api.nvim_win_call(win, function()
        vim.cmd('checktime')
      end)
    end
  end

  -- Unload the buffer if it wasn't open before
  if vim.fn.bufloaded(buf) == 1 and vim.fn.bufwinnr(buf) == -1 then
    vim.cmd('bdelete ' .. buf)
  end
end

local function on_assistant_turn_end(opts)
  local tool_calls = find_tool_calls(opts)

  local sign_group = "llm_sidekick-write_to_file"
  signs.clear(opts.buffer, sign_group)

  for _, tool_call in ipairs(tool_calls) do
    signs.place(
      opts.buffer,
      sign_group,
      tool_call.content_start_line,
      tool_call.content_end_line,
      "llm_sidekick_green"
    )
  end

  return tool_calls
end

return {
  name = "Write to File",
  diagnostic_name = "Write",
  description = description,
  on_assistant_turn_end = on_assistant_turn_end,
  on_user_accept = function(opts)
    local tool_call = find_tool_at_cursor(opts)
    if not tool_call then
      return
    end

    local ok, err = xpcall(apply_tool_call, error_handler, tool_call)
    if not ok then
      tool_call.error = string.format("Error applying write_to_file to %s: %s", tool_call.path, vim.inspect(err))
    end

    return tool_call
  end,
  on_user_accept_all = function(opts)
    local tool_calls = find_tool_calls(opts)

    for _, tool_call in ipairs(tool_calls) do
      local ok, err = xpcall(apply_tool_call, error_handler, tool_call)
      if not ok then
        tool_call.error = string.format("Error applying write_to_file to %s: %s", tool_call.path, vim.inspect(err))
      end
    end

    return tool_calls
  end
}
