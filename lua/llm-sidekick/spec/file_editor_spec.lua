local file_editor = require('llm-sidekick.file_editor')

describe("find_modification_block", function()
  it("should find a single well-formed modification block", function()
    local content = [[
@mathweb/flask/app.py
<search>
from flask import Flask
</search>
<replace>
import math
from flask import Flask
</replace>
]]
    local lines = vim.split(content, "\n")
    local cursor_line = 2 -- Line with "@mathweb/flask/app.py"
    local result = file_editor.find_modification_block(cursor_line, lines)

    assert.is_not_nil(result)
    assert.equals(8, #result)
    assert.equals("@mathweb/flask/app.py", result[1])
    assert.equals("<search>", result[2])
    assert.equals("from flask import Flask", result[3])
    assert.equals("</search>", result[4])
    assert.equals("<replace>", result[5])
    -- Note: The replace block continues; adjust the expected lines as needed
  end)

  it("should return empty table if no block is found", function()
    local content = [[
def hello():
    print("Hello, World!")
]]
    local lines = vim.split(content, "\n")
    local cursor_line = 2
    local result = file_editor.find_modification_block(cursor_line, lines)

    assert.same({}, result)
  end)

  it("should return empty table if block is incomplete (missing <replace>)", function()
    local content = [[
@main.py
<search>
def hello():
    print("Hello, World!")
</search>
]]
    local lines = vim.split(content, "\n")
    local cursor_line = 2
    local result = file_editor.find_modification_block(cursor_line, lines)

    assert.same({}, result)
  end)

  it("should handle multiple modification blocks and find the correct one", function()
    local content = [[
@file1.py
<search>
old_code1
</search>
<replace>
new_code1
</replace>

@file2.py
<search>
old_code2
</search>
<replace>
new_code2
</replace>
]]
    local lines = vim.split(content, "\n")

    -- Test first block
    local cursor_line1 = 2
    local result1 = file_editor.find_modification_block(cursor_line1, lines)

    assert.is_not_nil(result1)
    assert.equals(7, #result1)
    assert.equals("@file1.py", result1[1])
    assert.equals("<search>", result1[2])
    assert.equals("old_code1", result1[3])
    assert.equals("</search>", result1[4])
    assert.equals("<replace>", result1[5])
    assert.equals("new_code1", result1[6])
    assert.equals("</replace>", result1[7])

    -- Test second block
    local cursor_line2 = 9
    local result2 = file_editor.find_modification_block(cursor_line2, lines)

    assert.is_not_nil(result2)
    assert.equals(7, #result2)
    assert.equals("@file2.py", result2[1])
    assert.equals("<search>", result2[2])
    assert.equals("old_code2", result2[3])
    assert.equals("</search>", result2[4])
    assert.equals("<replace>", result2[5])
    assert.equals("new_code2", result2[6])
    assert.equals("</replace>", result2[7])
  end)

  it("should handle blocks at the start and end of the file", function()
    local content = [[
@start_file.py
<search>
start_code
</search>
<replace>
new_start_code
</replace>

Middle content

@end_file.py
<search>
end_code
</search>
<replace>
new_end_code
</replace>
]]
    local lines = vim.split(content, "\n")

    -- Test start block
    local cursor_start = 2
    local result_start = file_editor.find_modification_block(cursor_start, lines)

    assert.is_not_nil(result_start)
    assert.equals(7, #result_start)
    assert.equals("@start_file.py", result_start[1])
    assert.equals("<search>", result_start[2])
    assert.equals("start_code", result_start[3])
    assert.equals("</search>", result_start[4])
    assert.equals("<replace>", result_start[5])
    assert.equals("new_start_code", result_start[6])
    assert.equals("</replace>", result_start[7])

    -- Test end block
    local cursor_end = 12
    local result_end = file_editor.find_modification_block(cursor_end, lines)

    assert.is_not_nil(result_end)
    assert.equals(7, #result_end)
    assert.equals("@end_file.py", result_end[1])
    assert.equals("<search>", result_end[2])
    assert.equals("end_code", result_end[3])
    assert.equals("</search>", result_end[4])
    assert.equals("<replace>", result_end[5])
    assert.equals("new_end_code", result_end[6])
    assert.equals("</replace>", result_end[7])
  end)

  it("should return empty table if cursor_line is not within a block", function()
    local content = [[
Some unrelated line

@file.py
<search>
code
</search>
<replace>
new_code
</replace>

Some unrelated line
]]
    local lines = vim.split(content, "\n")

    -- Cursor line before any block
    local cursor_before = 1
    local result_before = file_editor.find_modification_block(cursor_before, lines)
    assert.same({}, result_before)

    -- Cursor line within <search> but not at start
    local cursor_within_search = 4
    local result_within_search = file_editor.find_modification_block(cursor_within_search, lines)
    assert.equals(7, #result_within_search)

    -- Cursor line within <replace> at the closing tag </replace>
    local cursor_within_replace = 9
    local result_within_replace = file_editor.find_modification_block(cursor_within_replace, lines)
    assert.equals(7, #result_within_replace)

    -- Cursor line after block
    local cursor_after = 11
    local result_after = file_editor.find_modification_block(cursor_after, lines)
    assert.same({}, result_after)
  end)

  it("should return empty table if another block starts before completing the current one", function()
    local content = [[
@file1.py
<search>
code1
@file2.py
<replace>
new_code2
</replace>
]]
    local lines = vim.split(content, "\n")
    local cursor_line = 2 -- Line with "@file1.py" and start searching for block
    local result = file_editor.find_modification_block(cursor_line, lines)

    -- Since another '@' is found before '</replace>', it should return empty
    assert.same({}, result)
  end)

  it("should handle blocks with empty <search> and <replace> sections", function()
    local content = [[
@empty.py
<search>
</search>
<replace>
</replace>
]]
    local lines = vim.split(content, "\n")
    local cursor_line = 2
    local result = file_editor.find_modification_block(cursor_line, lines)

    assert.is_not_nil(result)
    assert.equals(5, #result)
    assert.equals("@empty.py", result[1])
    assert.equals("<search>", result[2])
    assert.equals("</search>", result[3])
    assert.equals("<replace>", result[4])
    assert.equals("</replace>", result[5])
  end)

  it("should handle cursor_line at the first line", function()
    local content = [[
@first_line.py
<search>
code
</search>
<replace>
new_code
</replace>
]]
    local lines = vim.split(content, "\n")
    local cursor_line = 1
    local result = file_editor.find_modification_block(cursor_line, lines)

    assert.is_not_nil(result)
    assert.equals(7, #result)
    assert.equals("@first_line.py", result[1])
    assert.equals("<search>", result[2])
    assert.equals("code", result[3])
    assert.equals("</search>", result[4])
    assert.equals("<replace>", result[5])
    assert.equals("new_code", result[6])
    assert.equals("</replace>", result[7])
  end)

  it("should handle blocks with additional unrelated lines inside", function()
    local content = [[
@complex.py
<search>
def func():
    # Some comment
    pass
</search>
<replace>
def func():
    print("Updated")
</replace>
]]
    local lines = vim.split(content, "\n")
    local cursor_line = 2
    local result = file_editor.find_modification_block(cursor_line, lines)

    assert.is_not_nil(result)
    -- The number of lines in the block may vary; adjust accordingly
    assert.equals(10, #result)
    assert.equals("@complex.py", result[1])
    assert.equals("<search>", result[2])
    assert.equals("def func():", result[3])
    assert.equals("    # Some comment", result[4])
    assert.equals("    pass", result[5])
    assert.equals("</search>", result[6])
    assert.equals("<replace>", result[7])
    assert.equals("def func():", result[8])
    assert.equals("    print(\"Updated\")", result[9])
    assert.equals("</replace>", result[10])
  end)

  it("should handle closing tags on the same line as content", function()
    local content = [[
@app.py
<search>
from flask import Flask</search>
<replace>
import math
from flask import Flask</replace>
]]
    local lines = vim.split(content, "\n")
    local cursor_line = 2
    local result = file_editor.find_modification_block(cursor_line, lines)

    assert.is_not_nil(result)
    assert.equals(6, #result)
    assert.equals("@app.py", result[1])
    assert.equals("<search>", result[2])
    assert.equals("from flask import Flask</search>", result[3])
    assert.equals("<replace>", result[4])
    assert.equals("import math", result[5])
    assert.equals("from flask import Flask</replace>", result[6])
  end)

  it("should handle mixed inline and newline closing tags", function()
    local content = [[
@app.py
<search>
print("hello")</search>
<replace>
print("world")
</replace>
]]
    local lines = vim.split(content, "\n")
    local cursor_line = 2
    local result = file_editor.find_modification_block(cursor_line, lines)

    assert.is_not_nil(result)
    assert.equals(6, #result)
    assert.equals("@app.py", result[1])
    assert.equals("<search>", result[2])
    assert.equals("print(\"hello\")</search>", result[3])
    assert.equals("<replace>", result[4])
    assert.equals("print(\"world\")", result[5])
    assert.equals("</replace>", result[6])
  end)

  it("should handle empty blocks with inline closing tags", function()
    local content = [[
@empty.py
<search></search>
<replace></replace>
]]
    local lines = vim.split(content, "\n")
    local cursor_line = 2
    local result = file_editor.find_modification_block(cursor_line, lines)

    assert.is_not_nil(result)
    assert.equals(0, #result)
  end)

  it("should handle multiple blocks with inline closing tags", function()
    local content = [[
@file1.py
<search>old_code1</search>
<replace>new_code1</replace>

@file2.py
<search>old_code2</search>
<replace>new_code2</replace>
]]
    local lines = vim.split(content, "\n")

    local cursor_line1 = 2
    local result1 = file_editor.find_modification_block(cursor_line1, lines)

    assert.is_not_nil(result1)
    assert.equals(0, #result1)

    local cursor_line2 = 6
    local result2 = file_editor.find_modification_block(cursor_line2, lines)

    assert.is_not_nil(result2)
    assert.equals(0, #result2)
  end)

  it("should return empty table for invalid inline tag formats", function()
    local content = [[
@invalid.py
<search>code</search>invalid</search>
<replace>new</replace>code</replace>
]]
    local lines = vim.split(content, "\n")
    local cursor_line = 2
    local result = file_editor.find_modification_block(cursor_line, lines)

    assert.same({}, result)
  end)


  it("should handle search text with special characters and regex metacharacters", function()
    local lines = {
      "@special.py",
      "<search>",
      "def test():",
      "    return \"Hello\\nWorld\"",
      "    # Special chars: $^*+?()[]{}|\\",
      "</search>",
      "<replace>",
      "def test():",
      "    return \"Goodbye\\nWorld\"",
      "    # More special chars: <>!@#$%^&*()",
      "</replace>"
    }
    local cursor_line = 2
    local result = file_editor.find_modification_block(cursor_line, lines)

    assert.is_not_nil(result)
    assert.equals(11, #result)
    assert.equals("@special.py", result[1])
    assert.equals("<search>", result[2])
    assert.equals("def test():", result[3])
    assert.equals("    return \"Hello\\nWorld\"", result[4])
    assert.equals("    # Special chars: $^*+?()[]{}|\\", result[5])
    assert.equals("</search>", result[6])
    assert.equals("<replace>", result[7])
    assert.equals("def test():", result[8])
    assert.equals("    return \"Goodbye\\nWorld\"", result[9])
    assert.equals("    # More special chars: <>!@#$%^&*()", result[10])
    assert.equals("</replace>", result[11])
  end)
end)

describe("parse_modification_block", function()
  local mock_cwd = "/mock/cwd"

  before_each(function()
    -- Mock vim.fn.getcwd()
    _G.vim = _G.vim or {}
    _G.vim.fn = _G.vim.fn or {}
    _G.vim.fn.getcwd = function() return mock_cwd end
    _G.vim.startswith = function(str, prefix)
      return str:sub(1, #prefix) == prefix
    end
    _G.vim.fn.fnamemodify = function(path, modifier)
      if modifier == ":p" then
        if path:sub(1, 1) == "/" then
          return path
        end
        return mock_cwd .. "/" .. path
      end
      return path
    end
  end)

  it("should parse a well-formed block correctly", function()
    local lines = {
      "@app.py",
      "<search>",
      "old_code",
      "more_old_code",
      "</search>",
      "<replace>",
      "new_code",
      "more_new_code",
      "</replace>"
    }

    local file_path, search, replace = file_editor.parse_modification_block(lines)
    assert.equals("app.py", file_path)
    assert.equals("old_code\nmore_old_code", search)
    assert.equals("new_code\nmore_new_code", replace)
  end)

  it("should handle empty search and replace sections", function()
    local lines = {
      "@empty.py",
      "<search>",
      "</search>",
      "<replace>",
      "</replace>"
    }

    local file_path, search, replace = file_editor.parse_modification_block(lines)
    assert.equals("empty.py", file_path)
    assert.equals("", search)
    assert.equals("", replace)
  end)

  it("should error when file path is outside cwd", function()
    local lines = {
      "@/etc/passwd",
      "<search>",
      "content",
      "</search>",
      "<replace>",
      "new_content",
      "</replace>"
    }

    assert.has_error(function()
      file_editor.parse_modification_block(lines)
    end, "The file path '/etc/passwd' must be within the current working directory '/mock/cwd'")
  end)

  it("should handle mixed inline and newline tags", function()
    local lines = {
      "@mixed.py",
      "<search>",
      "old_code</search>",
      "<replace>",
      "new_code</replace>"
    }

    local file_path, search, replace = file_editor.parse_modification_block(lines)
    assert.equals("mixed.py", file_path)
    assert.equals("old_code", search)
    assert.equals("new_code", replace)
  end)

  it("should handle content with special characters", function()
    local lines = {
      "@special.py",
      "<search>",
      "def test():",
      "    return \"Hello\\nWorld\"",
      "    # Special chars: $^*+?()[]{}|\\",
      "</search>",
      "<replace>",
      "def test():",
      "    return \"Goodbye\\nWorld\"",
      "    # More special chars: <>!@#$%^&*()",
      "</replace>"
    }

    local file_path, search, replace = file_editor.parse_modification_block(lines)
    assert.equals("special.py", file_path)
    assert.equals('def test():\n    return "Hello\\nWorld"\n    # Special chars: $^*+?()[]{}|\\', search)
    assert.equals('def test():\n    return "Goodbye\\nWorld"\n    # More special chars: <>!@#$%^&*()', replace)
  end)
end)
