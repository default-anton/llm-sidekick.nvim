local chat = require("llm-sidekick.chat")
local fs = require("llm-sidekick.fs")

local spec = {
  name = "list_directory_contents",
  description = "Lists the contents (files and subdirectories) of a given directory",
  input_schema = {
    type = "object",
    properties = {
      directory_path = {
        type = "string",
        description = "The absolute or relative path to the directory to list",
      },
    },
    required = { "directory_path" },
  }
}

local json_props = string.format([[{
  "directory_path": %s
}]],
  vim.json.encode(spec.input_schema.properties.directory_path)
)

return {
  spec = spec,
  json_props = json_props,
  is_show_diagnostics = function() return true end,
  is_auto_acceptable = function() return true end,
  stop = function(tool_call, opts)
    chat.paste_at_end(string.format("**ls:** `%s`", tool_call.parameters.directory_path), opts.buffer)
  end,
  run = function(tool_call, opts)
    local path = vim.trim(tool_call.parameters.directory_path or "")
    local ok, entries = pcall(vim.fn.readdir, path)
    if not ok then
      vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.lnum - 1, tool_call.state.end_lnum, false,
        { string.format("✗ **ls:** `%s`", path, #entries) })
      error(string.format("Error: Failed to list directory %s (%s)", path, vim.inspect(entries)))
    end

    vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.lnum - 1, tool_call.state.end_lnum, false,
      { string.format("✓ **ls:** `%s` (%d files)", path, #entries) })

    local project_instructions = {}
    local file_dir = vim.fn.fnamemodify(path, ":p:h")

    local claude_files = fs.find_claude_md_files({
      buf = opts.buffer,
      start_dir = file_dir,
      stop_at_dir = vim.fn.getcwd(),
    })

    for _, claude_path in ipairs(claude_files) do
      local content = fs.read_file(claude_path)
      if content and content ~= "" then
        table.insert(project_instructions, { file_path = claude_path, project_instructions = content })
      end
    end

    if #project_instructions > 0 then
      return {
        project_instructions = project_instructions,
        directory_contents = entries,
      }
    else
      return {
        directory_contents = entries,
      }
    end
  end
}
