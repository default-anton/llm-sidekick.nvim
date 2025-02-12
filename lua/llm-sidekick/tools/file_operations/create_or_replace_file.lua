local markdown = require("llm-sidekick.markdown")
local chat = require("llm-sidekick.chat")
local signs = require("llm-sidekick.signs")

local spec = {
  name = "create_or_replace_file",
  description = [[
Create or overwrite a file with the specified content.

CRITICAL REQUIREMENTS:
- `path`: The path to the file. This must be relative to the current working directory, or it will be rejected.
- `content`: The complete content of the file to be written. The file will be overwritten if it already exists.
- This tool is not for appending or inserting into existing files.
- The tool will create any necessary directories in the path if they do not already exist.]],
  input_schema = {
    type = "object",
    properties = {
      path = {
        type = "string"
      },
      content = {
        type = "string"
      }
    },
    required = {
      "path",
      "content"
    }
  }
}

local json_props = [[{
  "path": { "type": "string" },
  "content": { "type": "string" }
}]]

local function error_handler(err)
  return debug.traceback(err, 3)
end

return {
  spec = spec,
  json_props = json_props,
  is_auto_acceptable = function(_)
    return false
  end,
  -- Initialize the streaming display with markdown formatting
  start = function(tool_call, opts)
    chat.paste_at_end("**Create:** ``", opts.buffer)
    -- Store the starting line number for later updates
    tool_call.state.path_line = vim.api.nvim_buf_line_count(opts.buffer)

    chat.paste_at_end("\n```txt\n", opts.buffer)
    tool_call.state.content_start_line = vim.api.nvim_buf_line_count(opts.buffer)
  end,
  -- Handle incremental updates for streaming file path and content
  delta = function(tool_call, opts)
    tool_call.parameters.path = vim.trim(tool_call.parameters.path or "")

    local path_written = tool_call.state.path_written or 0
    local content_written = tool_call.state.content_written or 0

    if tool_call.parameters.path and path_written < #tool_call.parameters.path then
      vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.path_line - 1, tool_call.state.path_line, false,
        { string.format("**Create:** `%s`", tool_call.parameters.path) })
      tool_call.state.path_written = #tool_call.parameters.path

      -- Update the language for syntax highlighting
      local language = markdown.filename_to_language(tool_call.parameters.path)
      vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.content_start_line - 2,
        tool_call.state.content_start_line - 1, false,
        { "```" .. language })
    end

    if tool_call.parameters.content and content_written < #tool_call.parameters.content then
      chat.paste_at_end(tool_call.parameters.content:sub(content_written + 1), opts.buffer)
      tool_call.state.content_written = #tool_call.parameters.content

      local content_end_line = tool_call.state.content_start_line +
          select(2, tool_call.parameters.content:gsub("\n", ""))
      local sign_group = string.format("%s-create_or_replace_file-content", tool_call.id)
      signs.place(opts.buffer, sign_group, tool_call.state.content_start_line, content_end_line, "llm_sidekick_green")
    end
  end,
  stop = function(tool_call, opts)
    if #tool_call.parameters.content > 0 then
      chat.paste_at_end("\n```", opts.buffer)

      local content_end_line = tool_call.state.content_start_line +
          select(2, tool_call.parameters.content:gsub("\n", ""))
      local sign_group = string.format("%s-create_or_replace_file-content", tool_call.id)
      signs.place(opts.buffer, sign_group, tool_call.state.content_start_line, content_end_line, "llm_sidekick_green")
    else
      chat.paste_at_end("```", opts.buffer)
    end
  end,
  -- Execute the actual file creation
  run = function(tool_call, opts)
    local path = vim.trim(tool_call.parameters.path or "")
    local content = tool_call.parameters.content

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
        vim.cmd("write")
      end)
    end, error_handler)

    -- Unload the buffer if it wasn't open before
    if vim.fn.bufloaded(buf) == 1 and vim.fn.bufwinnr(buf) == -1 and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end

    if not ok then
      error(string.format("Failed to write to file: %s", err))
    end

    -- Replace the tool call content with success message
    vim.api.nvim_buf_set_lines(opts.buffer, opts.start_lnum - 1, opts.end_lnum, false,
      { string.format("✓ Created file: %s", path) })

    return true
  end
}
