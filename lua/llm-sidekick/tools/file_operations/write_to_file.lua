local markdown = require("llm-sidekick.markdown")
local chat = require("llm-sidekick.chat")
local signs = require("llm-sidekick.signs")

local spec = {
  name = "write_to_file",
  description =
  "Writes content to a specified file. If the file already exists, its content will be completely overwritten. If the file does not exist, it will be created, and any necessary parent directories will also be created. To delete the content of a file, provide an empty string for the 'content' argument.",
  input_schema = {
    type = "object",
    properties = {
      file_path = {
        type = "string",
        description = "The absolute or relative path to the file where content will be written",
      },
      content = {
        type = "string",
        description = "The string content to write into the file."
      },
    },
    required = { "file_path", "content" },
  }
}

local json_props = string.format([[{
  "file_path": %s,
  "content": %s
}]],
  vim.json.encode(spec.input_schema.properties.file_path),
  vim.json.encode(spec.input_schema.properties.content)
)

return {
  spec = spec,
  json_props = json_props,
  is_show_diagnostics = function() return true end,
  is_auto_acceptable = function(_, buffer)
    return require("llm-sidekick.tools.utils").is_auto_accept_edits(buffer) or
        require("llm-sidekick.settings").auto_accept_file_operations()
  end,
  stop = function(tool_call, opts)
    local path = tool_call.parameters.file_path
    local content = tool_call.parameters.content

    chat.paste_at_end(string.format("**Write:** `%s`", path), opts.buffer)

    local language = markdown.filename_to_language(path, "txt")
    chat.paste_at_end(string.format("\n````%s\n", language), opts.buffer)
    local file_text_lnum = vim.api.nvim_buf_line_count(opts.buffer)

    chat.paste_at_end(content, opts.buffer)
    local file_text_end_lnum = vim.api.nvim_buf_line_count(opts.buffer)

    chat.paste_at_end("\n````", opts.buffer)

    local sign_group = string.format("%s-write_to_file-content", tool_call.id)
    signs.place(opts.buffer, sign_group, file_text_lnum, file_text_end_lnum, "llm_sidekick_green")
  end,
  run = function(tool_call, opts)
    local path = vim.trim(tool_call.parameters.file_path or "")
    local content = tool_call.parameters.content

    local dir = vim.fn.fnamemodify(path, ":h")
    if vim.fn.isdirectory(dir) == 0 then
      local ok, err = pcall(vim.fn.mkdir, dir, "p")
      if not ok then
        vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.lnum - 1, tool_call.state.end_lnum, false,
          { string.format("✗ **Write:** `%s`", path) })
        error(string.format("Error: Failed to create dir %s (%s)", dir, vim.inspect(err)))
      end
    end

    local ok, err
    local buf = vim.fn.bufnr(path)
    if vim.api.nvim_buf_is_loaded(buf) then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n"))
      ok, err = pcall(vim.api.nvim_buf_call, buf, function()
        vim.cmd("write")
      end)
    else
      ok, err = pcall(vim.fn.writefile, vim.split(content, "\n"), path)
    end

    if not ok then
      vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.lnum - 1, tool_call.state.end_lnum, false,
        { string.format("✗ **Write:** `%s`", path) })
      error(string.format("Error: Failed to write file %s (%s)", path, vim.inspect(err)))
    end

    -- Replace the tool call content with success message
    vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.lnum - 1, tool_call.state.end_lnum, false,
      { string.format("✓ **Write:** `%s`", path) })

    return true
  end,
}
