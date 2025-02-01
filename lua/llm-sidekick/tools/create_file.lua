local markdown = require("llm-sidekick.markdown")

local spec = {
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
}

return {
  spec = spec,
  start = function(tool_call)
    local line_count = vim.api.nvim_buf_line_count(0)
    tool_call.state.file_path_lnum = line_count + 4
    tool_call.state.create_lnum = line_count + 7

    local create_suggestion = {
      "",
      "**File Path:**",
      "```",
      "",
      "```",
      "**Create:**",
      "```",
      "```",
      "",
    }

    vim.api.nvim_buf_set_lines(0, -1, -1, false, create_suggestion)
  end,
  delta = function(tool_call)
    if tool_call.input.path then
      vim.api.nvim_buf_set_lines(0, tool_call.state.file_path_lnum - 1, tool_call.state.file_path_lnum, false,
        { tool_call.input.path })
    end

    if tool_call.input.content and tool_call.input.content ~= "" then
      if not tool_call.state.first_content then
        local language = markdown.filename_to_language(tool_call.input.path)

        vim.api.nvim_buf_set_lines(
          0,
          tool_call.state.create_lnum - 1,
          tool_call.state.create_lnum,
          false,
          { "```" .. language }
        )
        vim.api.nvim_buf_set_lines(
          0,
          tool_call.state.create_lnum,
          tool_call.state.create_lnum,
          false,
          { tool_call.input.content }
        )
        tool_call.state.first_content = true
        return
      end

      local lines = vim.split(tool_call.input.content, "\n")
      lines[#lines + 1] = "```"
      vim.api.nvim_buf_set_lines(0, tool_call.state.create_lnum, -1, false, lines)
    end
  end,
  stop = function(_)
  end,
  callback = function(tool_call)
    -- tool.input
  end
}
