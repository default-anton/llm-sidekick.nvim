-- Tool for creating/overwriting files with streaming content display
local markdown = require("llm-sidekick.markdown")
local chat = require("llm-sidekick.chat")
local sjson = require("llm-sidekick.sjson")
local signs = require("llm-sidekick.signs")

local description = vim.json.encode([[
Creates or overwrites a file with specified content at the given path. Use this for generating new files or completely replacing existing ones with new content.

When to Use:
- Initial file creation, such as when scaffolding a new project.
- Overwriting large boilerplate files where you want to replace the entire content at once.
- When the complexity or number of changes would make replace_in_file unwieldy or error-prone.
- When you need to completely restructure a file's content or change its fundamental organization.

When to Avoid:
- If you only need to make small changes to an existing file, consider using replace_in_file instead to avoid unnecessarily rewriting the entire file.

Technical Details:
- Creates parent directories automatically if they don't exist
- Overwrites existing files completely (no append mode)
- Content is written exactly as provided - no automatic formatting
- Won't work on binary files]])

local spec_json = [[{
  "name": "create_file",
  "description": ]] .. description .. [[,
  "input_schema": {
    "type": "object",
    "properties": {
      "path": {
        "type": "string",
        "description": "Path to target file. Accepts relative (from CWD) or absolute paths. Use forward slashes even on Windows. Examples: 'docs/report.txt', '/home/user/docs/report.txt', 'C:/Users/name/file.txt'"
      },
      "content": {
        "type": "string",
        "description": "The complete text content to write to the file, which will be written exactly as provided without any modification or formatting"
      }
    },
    "required": [
      "path",
      "content"
    ]
  }
}]]

return {
  spec_json = spec_json,
  spec = sjson.decode(spec_json),
  -- Initialize the streaming display with markdown formatting
  start = function(tool_call, opts)
    chat.paste_at_end("**Create:** `<path will be determined...>`", opts.buffer)
    -- Store the starting line number for later updates
    tool_call.state.path_line = vim.api.nvim_buf_line_count(opts.buffer)

    chat.paste_at_end("\n```txt\n", opts.buffer)
    tool_call.state.content_start_line = vim.api.nvim_buf_line_count(opts.buffer)
  end,
  -- Handle incremental updates for streaming file path and content
  delta = function(tool_call, opts)
    tool_call.parameters.path = vim.trim(tool_call.parameters.path)

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

      -- Place signs for the find section
      local content_end_line = tool_call.state.content_start_line + select(2, tool_call.parameters.content:gsub("\n", ""))
      local sign_group = string.format("%s-create_file-content", tool_call.id)
      signs.clear(opts.buffer, sign_group)
      signs.place(opts.buffer, sign_group, tool_call.state.content_start_line, content_end_line, "llm_sidekick_green")
    end
  end,
  stop = function(tool_call, opts)
    if #tool_call.parameters.content > 0 then
      chat.paste_at_end("\n```", opts.buffer)
    else
      chat.paste_at_end("```", opts.buffer)
    end
  end,
  -- Execute the actual file creation
  run = function(tool_call, opts)
    local path = vim.trim(tool_call.parameters.path)
    local content = tool_call.parameters.content

    local dir = vim.fn.fnamemodify(path, ":h")
    if vim.fn.isdirectory(dir) == 0 then
      local success = vim.fn.mkdir(dir, "p")
      if success == 0 then
        error(string.format("Failed to create directory: %s", dir))
      end
    end

    local buf = vim.fn.bufnr(path, true)
    vim.fn.bufload(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n"))
    local ok, err = pcall(function()
      vim.api.nvim_buf_call(buf, function()
        vim.cmd("write")
      end)
    end)

    if not ok then
      error(string.format("Failed to write to file: %s", err))
    end

    return true
  end
}
