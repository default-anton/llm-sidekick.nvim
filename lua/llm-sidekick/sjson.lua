---Decodes and completes partial JSON strings into Lua tables.
---
---The `SJSON` module provides a `decode` function that aims to robustly
---decode JSON strings, even if they are incomplete or contain extra
---whitespace. It attempts to complete partial JSON structures to provide
---a valid Lua table representation of the JSON data.
---
---It handles:
---  - Complete and partial JSON objects and arrays.
---  - Leading/trailing whitespace.
---  - Empty JSON objects and arrays.
---  - Nested JSON structures.
---  - Different JSON data types (strings, numbers, booleans, null, arrays, objects).
---  - Gracefully handles invalid JSON input by returning an empty table.
local SJSON = {}

function SJSON.decode(json_string)
  if not json_string then
    return {} -- Handle nil or empty input
  end

  -- Set default options to convert null to nil
  local opts = { luanil = { object = true, array = true } }

  local ok, result = pcall(vim.json.decode, json_string, opts)
  if ok then
    return result
  end

  local completed_json = json_string

  local stack = {}
  local in_string = false
  local escaped = false

  local len = #completed_json
  for i = 1, len do
    local byte = completed_json:byte(i)
    if byte == 92 then -- backslash (\)
      escaped = not escaped
    else
      if byte == 34 and not escaped then -- double quote (")
        if not in_string then
          table.insert(stack, '"')
        else
          if stack[#stack] == '"' then
            table.remove(stack)
          end
        end
        in_string = not in_string
      elseif not in_string then
        if byte == 123 or byte == 91 then -- '{' or '['
          if byte == 123 then
            table.insert(stack, '{')
          else
            table.insert(stack, '[')
          end
        elseif byte == 125 then -- '}'
          if stack[#stack] == '{' then
            table.remove(stack)
          end
        elseif byte == 93 then -- ']'
          if stack[#stack] == '[' then
            table.remove(stack)
          end
        end
      end
      escaped = false
    end
  end

  -- Handle incomplete string sequences (Unicode escapes and trailing backslashes)
  local function handle_incomplete_string(str)
    -- Check for incomplete Unicode escape at the end
    local pattern = '\\u%x?%x?%x?$'
    if str:match(pattern) then
      return str:gsub(pattern, '')
    end
    -- Remove trailing single backslash
    if str:match('\\$') then
      return str:sub(1, -2)
    end
    return str
  end

  -- Complete incomplete numbers (decimal points and exponents)
  local function complete_number(str)
    -- Complete decimal numbers ending with '.' by removing the decimal point
    str = str:gsub("(%d+)%.$", "%1")
    -- Complete exponential numbers ending with 'e' or 'e+' or 'e-'
    str = str:gsub("(%d+)e$", "%1e0")
    str = str:gsub("(%d+)e%+$", "%1e0")
    str = str:gsub("(%d+)e%-$", "%1e0")
    return str
  end

  -- Complete trailing boolean or null values
  local function complete_trailing_value(str)
    -- Check for partial values from longest to shortest
    local partials = {
      { partial = "fals", complete = "false" },
      { partial = "tru",  complete = "true" },
      { partial = "nul",  complete = "null" },
      { partial = "fal",  complete = "false" },
      { partial = "tr",   complete = "true" },
      { partial = "nu",   complete = "null" },
      { partial = "fa",   complete = "false" },
      { partial = "t",    complete = "true" },
      { partial = "f",    complete = "false" },
      { partial = "n",    complete = "null" },
    }

    for _, v in ipairs(partials) do
      if str:sub(- #v.partial) == v.partial then
        return str:sub(1, - #v.partial - 1) .. v.complete
      end
    end

    return str
  end

  if in_string then
    completed_json = handle_incomplete_string(completed_json)
  else
    -- Remove trailing commas before closing structures
    completed_json = completed_json:gsub("%s*,%s*$", "")
    completed_json = complete_number(completed_json)
    completed_json = complete_trailing_value(completed_json)
  end

  -- Close any remaining open structures in reverse order
  for i = #stack, 1, -1 do
    if stack[i] == '{' then
      completed_json = completed_json .. '}'
    elseif stack[i] == '[' then
      completed_json = completed_json .. ']'
    elseif stack[i] == '"' then
      completed_json = completed_json .. '"'
    end
  end

  -- Try parsing the completed JSON
  ok, result = pcall(vim.json.decode, completed_json, opts)
  if ok then
    return result
  end

  -- If parsing failed, try wrapping in object brackets
  completed_json = completed_json:gsub("^%s*", "") -- Trim leading whitespace
  if not completed_json:match("^[{%[]") then
    completed_json = "{" .. completed_json .. "}"
  end

  -- Final attempt to decode
  ok, result = pcall(vim.json.decode, completed_json, opts)
  if ok then
    return result
  end

  -- Return empty table if all parsing attempts fail
  return {}
end

return SJSON
