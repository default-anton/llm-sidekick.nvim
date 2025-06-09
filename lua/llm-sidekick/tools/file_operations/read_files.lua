local chat = require("llm-sidekick.chat")
local fs = require("llm-sidekick.fs")

local spec = {
  name = "read_files",
  description = "Reads the entire content of specified files and returns their contents. If an error occurs (e.g., the file is not found or permissions are denied), a descriptive error message string is returned.",
  input_schema = {
    type = "object",
    properties = {
      file_paths = {
        type = "array",
        items = {
          type = "string"
        },
        description = "An array of absolute or relative paths to the files that need to be read."
      }
    },
    required = { "file_paths" }
  }
}

json_props = string.format([[{
  "file_paths": %s
}]],
  vim.json.encode(spec.input_schema.properties.file_paths)
)

return {
  spec = spec,
  json_props = json_props,
  is_show_diagnostics = function() return true end,
  is_auto_acceptable = function() return true end,
  stop = function(tool_call, opts)
    for _, file_path in ipairs(tool_call.parameters.file_paths) do
      chat.paste_at_end(string.format("**Read:** `%s`", file_path), opts.buffer)
    end
  end,
  run = function(tool_call, opts)
    local results = {}
    local buf_messages = {}
    local cwd = vim.fn.getcwd()

    for _, file_path in ipairs(tool_call.parameters.file_paths) do
      local content_lines = {}
      local success = true
      local buf = vim.fn.bufnr(file_path)

      if vim.api.nvim_buf_is_loaded(buf) then
        content_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      else
        local ok, lines = pcall(vim.fn.readfile, file_path)
        if not ok then
          success = false
          content_lines = {
            string.format("Error: Failed to read file %s (%s)", file_path, vim.inspect(lines))
          }
        end
        content_lines = lines
      end

      if success then
        table.insert(results, {
          file_path = file_path,
          success = true,
          content = table.concat(content_lines, "\n"),
        })
        table.insert(buf_messages, string.format("✓ **Read:** `%s`", file_path))
      else
        table.insert(results, {
          file_path = file_path,
          success = false,
          error = content_lines[1],
        })
        table.insert(buf_messages, string.format("✗ **Read:** `%s`", file_path))
      end

      local file_dir = vim.fn.fnamemodify(file_path, ":p:h")
      local project_files = fs.find_project_instruction_files({
        buf = opts.buffer,
        start_dir = file_dir,
        stop_at_dir = cwd,
      })

      for _, project_file_path in ipairs(project_files) do
        local content = fs.read_file(project_file_path)
        if content and content ~= "" then
          table.insert(results, {
            file_path = project_file_path,
            project_instructions = content,
          })
        end
      end
    end

    vim.api.nvim_buf_set_lines(
      opts.buffer,
      tool_call.state.lnum - 1,
      tool_call.state.end_lnum,
      false,
      buf_messages
    )
    return results
  end,
}
