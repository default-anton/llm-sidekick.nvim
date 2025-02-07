local M = {}

-- Finds tool calls within a given text based on a regex pattern.
-- Extracts specified attributes from each tool call and calculates their line numbers.
-- @param buffer integer: The buffer number of the input text.
-- @param start_search_line integer: The line number to start searching from.
-- @param end_search_line integer: The line number to stop searching at.
-- @param pattern string: The regex pattern to match tool calls.
-- @param attribute_names table: A list of attribute names to extract from each match.
-- @return table: A table of tool call objects, each containing the extracted attributes and line number information.
function M.find_tool_calls(buffer, start_search_line, end_search_line, pattern, attribute_names)
  local buffer_lines = vim.api.nvim_buf_get_lines(buffer, start_search_line - 1, end_search_line, false)
  buffer_lines[1] = buffer_lines[1]:gsub("^ASSISTANT:%s*", "")
  local text = table.concat(buffer_lines, "\n")

  local found_tool_calls = {}
  local start = 1

  while true do
    local match_group = { text:find(pattern, start) }

    local start_pos, end_pos = match_group[1], match_group[2]
    if not start_pos then
      break
    end

    local matches = vim.list_slice(match_group, 3)
    if #matches ~= #attribute_names then
      error(string.format(
        "Expected %d matches, got %d. attribute_names: %s, matches: %s",
        #attribute_names,
        #matches,
        vim.inspect(attribute_names),
        vim.inspect(matches)
      ))
    end

    local body = text:sub(start_pos, end_pos)
    local start_line = start_pos == 1 and 1 or select(2, text:sub(1, start_pos):gsub("\n", ""))
    local end_line = start_line + select(2, body:gsub("\n", ""))
    local tool_call = {
      start_line = start_search_line + start_line,
      end_line = start_search_line + end_line,
      body = body,
    }
    for i, match in ipairs(matches) do
      local match_start_pos = body:find(match, 1, true)
      local match_start_line = start_line + select(2, body:sub(1, match_start_pos):gsub("\n", ""))
      local match_end_line = match_start_line + select(2, match:gsub("\n", ""))
      tool_call[attribute_names[i]] = match
      tool_call[attribute_names[i] .. "_start_line"] = start_search_line + match_start_line
      tool_call[attribute_names[i] .. "_end_line"] = start_search_line + match_end_line
    end

    table.insert(found_tool_calls, tool_call)

    start = end_pos + 1
  end

  return found_tool_calls
end

return M
