local chat = require("llm-sidekick.chat")
local Job = require('plenary.job')

local spec = {
  name = "fetch_web_content",
  description = "Fetch content from a web page.",
  input_schema = {
    type = "object",
    properties = {
      url = {
        type = "string",
        description = "The URL of the web page to fetch content from"
      },
      max_words = {
        type = "integer",
        description = "Maximum number of words to return. Default is 32000",
      }
    },
    required = { "url", "max_words" },
  }
}

local json_props = string.format([[{
  "url": %s,
  "max_words": %s
}]], vim.json.encode(spec.input_schema.properties.url), vim.json.encode(spec.input_schema.properties.max_words))

local function is_github_url(url)
  return url:match("^https?://github%.com")
end

local function is_plain_url(url)
  if url:match("^https?://raw%.githubusercontent%.com") then
    return true
  end

  -- Check if the URL ends with common plain text file extensions
  local plain_text_extensions = {
    "%.txt", "%.json",
  }

  for _, ext in ipairs(plain_text_extensions) do
    if url:match(ext .. "$") then
      return true
    end
  end

  return false
end

-- Utility function to convert GitHub URLs to uithub.com URLs
local function convert_github_url(url, max_words)
  local converted_url = url:gsub("https://github%.com", "https://uithub.com")

  if converted_url:match("?.*$") then
    return converted_url .. string.format("&accept=text/markdown&maxTokens=%d", max_words)
  else
    return converted_url .. string.format("?accept=text/markdown&maxTokens=%d", max_words)
  end
end

local AVG_CHARS_PER_WORD = 6

return {
  spec = spec,
  json_props = json_props,
  is_show_diagnostics = function() return true end,
  is_auto_acceptable = function() return true end,
  -- Initialize the fetch display
  start = function(tool_call, opts)
    chat.paste_at_end("**Fetching web content:** ``", opts.buffer)
    tool_call.state.url_line = vim.api.nvim_buf_line_count(opts.buffer)
  end,
  -- Handle incremental updates for streaming URL
  delta = function(tool_call, opts)
    local url = vim.trim(tool_call.parameters.url or "")
    local url_written = tool_call.state.url_written or 0

    -- Update URL display
    if url and url_written < #url then
      vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.url_line - 1, tool_call.state.url_line, false,
        { string.format("**Fetching web content:** `%s`", url) })
      tool_call.state.url_written = #url
    end
  end,
  -- Execute the fetch asynchronously
  run = function(tool_call, opts)
    local max_words = tool_call.parameters.max_words or 32000
    local url = vim.trim(tool_call.parameters.url or "")
    if url == "" then
      error("Empty URL provided")
    end

    tool_call.state.result = { success = false, result = nil }

    local fetch_url = url
    if is_github_url(url) then
      fetch_url = convert_github_url(url, max_words)
    elseif is_plain_url(url) then
      fetch_url = url
    else
      fetch_url = 'https://r.jina.ai/' .. url
    end

    local job = Job:new({
      command = require("llm-sidekick.executables").get_curl_executable(),
      args = {
        '-s',
        '--no-buffer',
        '-L', -- follow redirects
        fetch_url,
      },
      on_exit = function(j, return_val)
        local output = {}
        vim.list_extend(output, j:result() or {})
        vim.list_extend(output, { "" })
        vim.list_extend(output, j:stderr_result() or {})

        if return_val == 0 and #output > 0 then
          tool_call.state.result.success = true
          local full_content = table.concat(output, "\n")
          local max_chars = max_words * AVG_CHARS_PER_WORD
          tool_call.state.result.result = full_content:sub(1, max_chars)
        else
          tool_call.state.result.success = false
          tool_call.state.result.result = string.format("Exit code: %d\n%s", return_val, table.concat(output, "\n"))
        end

        -- Update the fetch text to show it's completed
        vim.schedule(function()
          local status = tool_call.state.result.success and "✓" or "✗"
          local final_lines = { string.format("%s Fetched content from: `%s`", status, url) }
          vim.api.nvim_buf_set_lines(opts.buffer, tool_call.state.lnum - 1, tool_call.state.end_lnum, false,
            final_lines)
        end)
      end,
    })

    return job
  end
}
