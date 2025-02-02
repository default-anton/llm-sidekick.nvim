local markdown = require("llm-sidekick.markdown")
local chat = require("llm-sidekick.chat")

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
  start = function(_, opts)
    chat.paste_at_end("\n\n**Path:**\n```\n", opts.buffer)
  end,
  delta = function(tool_call, opts)
    local path_written = tool_call.state.path_written or 0
    local content_written = tool_call.state.content_written or 0

    if opts.parameters.path and path_written < #opts.parameters.path then
      chat.paste_at_end(opts.parameters.path:sub(path_written + 1), opts.buffer)
      tool_call.state.path_written = #opts.parameters.path
    end

    if opts.parameters.content and content_written < #opts.parameters.content then
      if content_written == 0 then
        local language = markdown.filename_to_language(opts.parameters.path)
        chat.paste_at_end(string.format("\n```\n**Create:**\n```%s\n", language), opts.buffer)
      end
      chat.paste_at_end(opts.parameters.content:sub(content_written + 1), opts.buffer)
      tool_call.state.content_written = #opts.parameters.content
    end
  end,
  stop = function(_, opts)
    chat.paste_at_end("\n```\n", opts.buffer)
  end,
  callback = function(tool_call)
    -- tool.parameters
  end
}
