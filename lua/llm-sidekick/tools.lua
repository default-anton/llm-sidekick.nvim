return {
  {
    name = "create_file",
    description = [[
      Creates or overwrites a file with specified content at the given path. Use this for generating new files or completely replacing existing ones with new content.

      Technical details:
      - Creates parent directories automatically if they don't exist
      - Overwrites existing files completely (no append mode)
      - Content is written exactly as provided - no automatic formatting
      - Won't work on binary files
    ]],
    input_schema = {
      type = "object",
      properties = {
        path = {
          type = "string",
          description =
          "Path to target file. Accepts relative (from CWD) or absolute paths. Use forward slashes even on Windows. Examples: 'docs/report.txt', '/home/user/docs/report.txt', 'C:/Users/name/file.txt'"
        },
        content = {
          type = "string",
          description =
          "The complete text content to write to the file, which will be written exactly as provided without any modification or formatting"
        }
      },
      required = { "path", "content" }
    }
  },
  {
    name = "replace_in_file",
    description = [[
      Replaces specific content in a file with exact matching. Use this to make precise modifications to existing files.

      Technical details:
      - Performs literal string replacement (no regex)
      - Case-sensitive, exact character-for-character matching
      - Works with any text file encoding
      - Replaces only the first match
      - Whitespace, newlines, indentation, and comments must match exactly
      - For multiple changes to the same file, call this tool multiple times
      - Prefer small, targeted replacements over large block changes
      - Target the minimum unique code segment needed for each change
      - Direct file modification - make sure you mean it
      - Won't work on binary files
    ]],
    input_schema = {
      type = "object",
      properties = {
        path = {
          type = "string",
          description =
          "Path to target file. Accepts relative (from CWD) or absolute paths. Use forward slashes even on Windows. Examples: 'docs/report.txt', '/home/user/docs/report.txt', 'C:/Users/name/file.txt'"
        },
        find = {
          type = "string",
          description =
          "Text to find. Must match exactly, including indentation, whitespace, newlines and comments. Case-sensitive, no regex. Even a single space difference in indentation will prevent matching."
        },
        replace = {
          type = "string",
          description =
          "Replacement text. Can be empty to delete matched text. Literal replacement, no special characters. Must use the same indentation level as the original text to maintain code formatting."
        }
      },
      required = { "path", "find", "replace" }
    }
  },
  {
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
}
