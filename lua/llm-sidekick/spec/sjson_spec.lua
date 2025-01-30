local SJSON = require('llm-sidekick.sjson')

describe("SJSON.parse", function()
  it("parses a complete JSON object", function()
    local json_string = '{"key": "value"}'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ key = "value" }, parsed_json)
  end)

  it("parses a complete JSON array", function()
    local json_string = '[1, 2, "three"]'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ 1, 2, "three" }, parsed_json)
  end)

  it("parses a JSON string with leading/trailing whitespace", function()
    local json_string = '  \n  {"key": "value"}  \n  '
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ key = "value" }, parsed_json)
  end)

  it("parses an empty JSON object", function()
    local json_string = '{}'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({}, parsed_json)
  end)

  it("parses an empty JSON array", function()
    local json_string = '[]'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({}, parsed_json)
  end)

  it("completes a partial JSON object - missing closing brace", function()
    local json_string = '{"key": "value"'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ key = "value" }, parsed_json)
  end)

  it("completes a partial JSON array - missing closing bracket", function()
    local json_string = '[1, 2, "three"'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ 1, 2, "three" }, parsed_json)
  end)

  it("completes a partial JSON string - missing closing quote", function()
    local json_string = '{"key": "value'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ key = "value" }, parsed_json)
  end)

  it("handles an empty string input", function()
    local json_string = ''
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({}, parsed_json) -- Assuming empty input results in an empty object
  end)

  it("parses JSON with different data types", function()
    local json_string = '{"string": "text", "number": 123, "boolean": true, "null": null, "array": [1, "two"], "object": {"nested": true}}'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({
      string = "text",
      number = 123,
      boolean = true,
      null = nil,
      array = { 1, "two" },
      object = { nested = true },
    }, parsed_json)
  end)

  it("completes a partial nested JSON object", function()
    local json_string = '{"outer": {"inner": "value"'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ outer = { inner = "value" } }, parsed_json)
  end)

  it("handles trailing comma in array", function()
    local json_string = '[1, 2, 3,'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ 1, 2, 3 }, parsed_json)
  end)

  it("completes a partial nested JSON array", function()
    local json_string = '[[1, 2],'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({{ 1, 2 }}, parsed_json)
  end)

  it("handles trailing comma in object", function()
    local json_string = '{"key": "value",'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ key = "value" }, parsed_json)
  end)

  it("handles trailing comma in a string", function()
    local json_string = '["Hello,'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ "Hello," }, parsed_json)
  end)

  it("handles multiple top-level JSON values - returns an empty object", function()
    local json_string = '{"first": 1} {"second": 2}'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({}, parsed_json)
  end)

  it("handles invalid JSON input - returns an empty object", function()
    local json_string = 'invalid json'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({}, parsed_json) -- Assuming invalid JSON results in an empty object
  end)

  it("parses JSON with unicode characters", function()
    local json_string = '{"key": "你好世界"}'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ key = "你好世界" }, parsed_json)
  end)

  it("parses JSON with escape characters", function()
    local json_string = '{"key": "value with \\\\, \\\", \\n, \\t, \\r, \\b, \\f, \\/"}'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ key = "value with \\, \", \n, \t, \r, \b, \f, /" }, parsed_json)
  end)

  it("parses JSON with different number formats", function()
    local json_string = '{"integer": 123, "float": 123.45, "exponent": 1.23e4, "negative": -123, "zero": 0, "large": 1234567890123456789}'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({
      integer = 123,
      float = 123.45,
      exponent = 12300,
      negative = -123,
      zero = 0,
      large = 1234567890123456789,
    }, parsed_json)
  end)

  it("parses deeply nested JSON", function()
    local json_string = '{"level1": {"level2": {"level3": {"level4": "deep value"}}}}'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ level1 = { level2 = { level3 = { level4 = "deep value" } } } }, parsed_json)
  end)

  it("parses JSON with null values", function()
    local json_string = '{"key": null, "array": [1, null, 3]}'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ key = nil, array = { 1, nil, 3 } }, parsed_json)
  end)

  it("parses JSON with empty keys", function()
    local json_string = '{"": "empty key value"}'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ [""] = "empty key value" }, parsed_json)
  end)

  it("handles JSON with single-line comments - returns an empty object", function()
    local json_string = '{ -- comment\n "key": "value" }'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({}, parsed_json)
  end)

  it("handles JSON with multi-line comments - returns an empty object", function()
    local json_string = '{ /* multi-line comment */ "key": "value" }'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({}, parsed_json)
  end)

  it("parses JSON with unicode surrogate pairs", function()
    local json_string = '{"key": "\\uD83D\\uDE00"}' -- U+1F600 GRINNING FACE
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ key = "😀" }, parsed_json)
  end)

  it("handles incomplete 'true' value - 'tru'", function()
    local json_string = '{"key": tru'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ key = true }, parsed_json)
  end)

  it("handles incomplete 'true' value - 'tr'", function()
    local json_string = '{"key": tr'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ key = true }, parsed_json)
  end)

  it("handles incomplete 'true' value - 't'", function()
    local json_string = '{"key": t'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ key = true }, parsed_json)
  end)

  it("handles incomplete string that ends with 't'", function()
    local json_string = '{"key": "t'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ key = "t" }, parsed_json)
  end)

  it("handles incomplete 'false' value - 'fals'", function()
    local json_string = '{"key": fals'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ key = false }, parsed_json)
  end)

  it("handles incomplete 'false' value - 'fal'", function()
    local json_string = '{"key": fal'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ key = false }, parsed_json)
  end)

  it("handles incomplete 'false' value - 'fa'", function()
    local json_string = '{"key": fa'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ key = false }, parsed_json)
  end)

  it("handles incomplete 'false' value - 'f'", function()
    local json_string = '{"key": f'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ key = false }, parsed_json)
  end)

  it("handles incomplete 'null' value - 'nul'", function()
    local json_string = '{"key": nul'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ key = nil }, parsed_json)
  end)

  it("handles incomplete 'null' value - 'nu'", function()
    local json_string = '{"key": nu'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ key = nil }, parsed_json)
  end)

  it("handles incomplete 'null' value - 'n'", function()
    local json_string = '{"key": n'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ key = nil }, parsed_json)
  end)

  it("handles incomplete number - decimal without digits after point", function()
    local json_string = '{"key": 12.'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ key = 12 }, parsed_json)
  end)

  it("handles incomplete number - exponent without digits after 'e'", function()
    local json_string = '{"key": 12e'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ key = 12 }, parsed_json)
  end)

  it("handles incomplete number - exponent with sign but no digits", function()
    local json_string = '{"key": 12e+'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ key = 12 }, parsed_json)
  end)

  it("handles broken escape sequence - invalid escape sequence", function()
    local json_string = '{"key": "value\\x"}'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({}, parsed_json)
  end)

  it("handles incomplete unicode escape sequences", function()
    local json_string = '{"key": "\\uD83' -- Incomplete \uD83
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ key = "" }, parsed_json)
  end)

  it("handles complete unicode escape sequences with incomplete string", function()
    local json_string = '{"key": "\\uD83D\\uDE00' -- Complete \uD83D\uDE00, but unfinished string
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ key = "😀" }, parsed_json)
  end)

  it("handles strings ending with a single backslash", function()
    local json_string = '{"key": "value\\'
    local parsed_json = SJSON.parse(json_string)
     assert.are.same({ key = "value" }, parsed_json)
  end)

  it("handles objects with missing colon between key and value", function()
    local json_string = '{"key" "value"}'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({}, parsed_json)
  end)

  it("handles arrays with missing commas between elements", function()
    local json_string = '[1 2, 3]'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({}, parsed_json)
  end)

  it("handles strings with invalid escape sequences", function()
    local json_string = '{"key": "value\\x"}'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({}, parsed_json)
  end)

  it("handles incomplete nested structures", function()
    local json_string = '{"key": {"subkey": [1, 2, '
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ key = { subkey = { 1, 2 } } }, parsed_json)
  end)

    it("handles numbers with multiple decimal points", function()
    local json_string = '{"key": 12.34.56}'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({}, parsed_json)
  end)

  it("handles numbers with leading zeros", function()
    local json_string = '{"key": 0123}'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({ key = 123 }, parsed_json)
  end)

  it("handles extra trailing characters after valid JSON", function()
    local json_string = '{"key": "value"} extra'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({}, parsed_json)
  end)

  it("handles nil input", function()
    local parsed_json = SJSON.parse(nil)
    assert.are.same({}, parsed_json)
  end)

  it("parses literal string", function()
    local json_string = '"hello"'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same("hello", parsed_json)
  end)

  it("parses literal number", function()
    local json_string = '123'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same(123, parsed_json)
  end)

  it("parses literal true", function()
    local json_string = 'true'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same(true, parsed_json)
  end)

  it("parses literal false", function()
    local json_string = 'false'
    local parsed_json = SJSON.parse(json_string)
    assert.are.same(false, parsed_json)
  end)

  it("parses literal null", function()
    local json_string = 'null'
    local parsed_json = SJSON.parse(json_string)
    assert.is_nil(parsed_json)
  end)

  it("handles input with only whitespace", function()
    local json_string = '     '
    local parsed_json = SJSON.parse(json_string)
    assert.are.same({}, parsed_json)
  end)
end)
