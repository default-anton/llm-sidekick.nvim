local spec = {
  name = "delete_file",
  description = [[
      Deletes the file at the given path.

      Technical details:
      - Supports both relative and absolute file paths.
      - Will not delete directories, only files.
    ]],
  input_schema = {
    type = "object",
    properties = {
      path = {
        type = "string",
        description =
        "Path to the file to delete. Accepts relative (from CWD) or absolute paths. Use forward slashes even on Windows. Examples: 'docs/old_report.txt', '/home/user/temp_files/outdated.txt', 'C:/Users/name/trash/temp.log'"
      }
    },
    required = { "path" }
  }
}

return {
  spec = spec,
  start = function(tool)
  end,
  delta = function(tool)
  end,
  stop = function(tool)
  end,
  callback = function(tool)
    -- tool.input
  end
}
