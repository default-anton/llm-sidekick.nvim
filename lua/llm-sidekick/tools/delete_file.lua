local sjson = require("llm-sidekick.sjson")
local chat = require("llm-sidekick.chat")

local description = vim.json.encode([[
Deletes the file at the given path.

Technical details:
- Supports both relative and absolute file paths.
- Will not delete directories, only files.]])

local spec_json = [[{
  "name": "delete_file",
  "description": ]] .. description .. [[,
  "input_schema": {
    "type": "object",
    "properties": {
      "path": {
        "type": "string",
        "description": "Path to the file to delete. Accepts relative (from CWD) or absolute paths. Use forward slashes even on Windows. Examples: 'docs/old_report.txt', '/home/user/temp_files/outdated.txt', 'C:/Users/name/trash/temp.log'"
      }
    },
    "required": [ "path" ]
  }
}]]

return {
  spec_json = spec_json,
  spec = sjson.decode(spec_json),
  start = function(tool_call, opts)
    chat.paste_at_end("**Delete:** `<path will be determined...>", opts.buffer)
    -- Store the line number where path will be updated
    tool_call.state.path_line = vim.api.nvim_buf_line_count(opts.buffer)
  end,
  delta = function(tool_call, opts)
    local path_written = tool_call.state.path_written or 0

    if tool_call.parameters.path and path_written < #tool_call.parameters.path then
      vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.path_line - 1, tool_call.state.path_line, false,
        { string.format("**Delete:** `%s`", tool_call.parameters.path) })
      tool_call.state.path_written = #tool_call.parameters.path
    end
  end,
  run = function(tool_call, opts)
    local path = tool_call.parameters.path

    -- Check if file exists first
    local ftype = vim.fn.getftype(path)
    if ftype == '' then
      return true
    end

    if ftype ~= 'file' then
      error(string.format("Path is not a file: %s", path))
    end

    local ok, err = vim.loop.fs_unlink(path)
    if not ok then
      error(string.format("Failed to delete file '%s': %s", path, err))
    end

    -- Close the buffer if it's open
    local deleted_file_buffer = vim.fn.bufnr(path)
    if deleted_file_buffer ~= -1 then
      vim.api.nvim_buf_delete(deleted_file_buffer, { force = true })
    end

    return true
  end
}
