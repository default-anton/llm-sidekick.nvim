local file_editor = require('llm-sidekick.file_editor')
local Path = require('plenary.path')

describe("apply_modifications", function()
  local original_nvim_err_writeln = vim.api.nvim_err_writeln
  local test_dir = Path:new('lua/llm-sidekick/spec/testdata')

  before_each(function()
    -- Ensure the testdata directory exists
    if not test_dir:exists() then
      local success, err = pcall(function()
        test_dir:mkdir({ parents = true })
      end)
      if not success then
        error("Failed to create test directory: " .. tostring(err))
      end
    end
  end)

  after_each(function()
    vim.api.nvim_err_writeln = original_nvim_err_writeln

    -- Close all buffers that belong to testdata directory
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      local buf_name = vim.api.nvim_buf_get_name(buf)
      if buf_name:match('^' .. test_dir:absolute()) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end

    -- Clean up the testdata directory after all tests
    if test_dir:exists() then
      test_dir:rm({ recursive = true })
    end
  end)

  it("should delete a file when both search and replace are empty", function()
    local file_path = test_dir:joinpath('delete_me.txt'):absolute()

    Path:new(file_path):write('', 'w')
    local bufnr = vim.api.nvim_create_buf(true, true)
    local mod_block = {
      "@" .. test_dir:joinpath('delete_me.txt'):absolute(),
      "<search>",
      "</search>",
      "<replace>",
      "</replace>",
    }
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, mod_block)

    vim.api.nvim_win_set_buf(0, bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    file_editor.apply_modifications(bufnr, false)
    assert.is_false(Path:new(file_path):exists())
  end)

  it("should create a new file when search is empty and replace is provided", function()
    local file_path = test_dir:joinpath('new_file.txt'):absolute()
    local replace_content = "This is a new file.\nWith multiple lines."

    assert.is_false(Path:new(file_path):exists())

    local bufnr = vim.api.nvim_create_buf(true, true)
    local mod_block = {
      "@" .. test_dir:joinpath('new_file.txt'):absolute(),
      "<search>",
      "</search>",
      "<replace>",
      "This is a new file.",
      "With multiple lines.",
      "</replace>",
    }
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, mod_block)

    vim.api.nvim_win_set_buf(0, bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    file_editor.apply_modifications(bufnr, false)

    assert.is_true(Path:new(file_path):exists())
    local content = Path:new(file_path):read()
    assert.equals(replace_content .. "\n", content)
  end)

  it("should modify an existing file by replacing search text with replace text", function()
    local file_path = test_dir:joinpath('modify_me.txt'):absolute()
    local original_content = "Hello World!\nThis is a test file.\nGoodbye World!"
    local search_text = "Hello World!"
    local replace_text = "Hello Universe!"

    Path:new(file_path):write(original_content, 'w')
    assert.is_true(Path:new(file_path):exists())

    local bufnr = vim.api.nvim_create_buf(true, true)

    local mod_block = vim.split(
      table.concat({
        "@" .. test_dir:joinpath('modify_me.txt'):absolute(),
        "<search>",
        search_text,
        "</search>",
        "<replace>",
        replace_text,
        "</replace>",
      }, "\n"),
      "\n"
    )
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, mod_block)

    vim.api.nvim_win_set_buf(0, bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    file_editor.apply_modifications(bufnr, false)

    local expected_content = "Hello Universe!\nThis is a test file.\nGoodbye World!"
    local content = Path:new(file_path):read()
    assert.equals(expected_content .. "\n", content)

    local buffer_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local expected_buffer_content = {
      "@" .. test_dir:joinpath('modify_me.txt'):absolute(),
      "<changes_applied>",
      "Hello Universe!",
      "</changes_applied>",
    }
    assert.same(expected_buffer_content, buffer_content)
  end)

  it("should handle multiple apply_modifications calls correctly", function()
    local file_path = test_dir:joinpath('multi_modify.txt'):absolute()
    local original_content = "Line 1\nLine 2\nLine 3\nLine 4"
    local search_text_1 = "Line 2"
    local replace_text_1 = "Second Line"
    local search_text_2 = "Line 4"
    local replace_text_2 = "Fourth Line"

    -- Create the file with original content
    Path:new(file_path):write(original_content, 'w')
    assert.is_true(Path:new(file_path):exists())

    -- Open the file in a buffer
    local bufnr = vim.api.nvim_create_buf(true, true)

    -- Insert the first modification block
    local mod_block_1 = vim.split(
      table.concat({
        "ASSISTANT:",
        "@" .. test_dir:joinpath('multi_modify.txt'):absolute(),
        "<search>",
        search_text_1,
        "</search>",
        "<replace>",
        replace_text_1,
        "</replace>",
      }, "\n"),
      "\n"
    )
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, mod_block_1)

    -- Set cursor at the beginning of the first modification block
    vim.api.nvim_win_set_buf(0, bufnr)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    -- Apply first modification
    file_editor.apply_modifications(bufnr, false)

    -- Verify the first modification
    local expected_content_1 = "Line 1\nSecond Line\nLine 3\nLine 4"
    local content_1 = Path:new(file_path):read()
    assert.equals(expected_content_1 .. "\n", content_1)

    -- Insert the second modification block below the first
    local mod_block_2 = {
      "@" .. test_dir:joinpath('multi_modify.txt'):absolute(),
      "<search>",
      search_text_2,
      "</search>",
      "<replace>",
      replace_text_2,
      "</replace>",
    }
    vim.api.nvim_buf_set_lines(bufnr, #mod_block_1, -1, false, mod_block_2)


    -- Set cursor at the beginning of the second modification block
    vim.api.nvim_win_set_buf(0, bufnr)
    vim.api.nvim_win_set_cursor(0, { #mod_block_1 + 2, 0 })

    -- Apply second modification
    file_editor.apply_modifications(bufnr, false)

    -- Verify the second modification
    local expected_content_2 = "Line 1\nSecond Line\nLine 3\nFourth Line"
    local content_2 = Path:new(file_path):read()
    assert.equals(expected_content_2 .. "\n", content_2)

    -- Verify the buffer reflects both modifications
    local buffer_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local expected_buffer_content = {
      'ASSISTANT:',
      '@/Users/akuzmenko/code/llm-sidekick.nvim/lua/llm-sidekick/spec/testdata/multi_modify.txt',
      '<changes_applied>',
      'Second Line',
      '</changes_applied>',
      '@/Users/akuzmenko/code/llm-sidekick.nvim/lua/llm-sidekick/spec/testdata/multi_modify.txt',
      '<changes_applied>',
      'Fourth Line',
      '</changes_applied>'
    }
    assert.same(expected_buffer_content, buffer_content)
  end)

  it("should handle applying modifications to multiple files with `is_all` flag", function()
    local file1_path = test_dir:joinpath('multi_file1.txt'):absolute()
    local file2_path = test_dir:joinpath('multi_file2.txt'):absolute()

    local original_content1 = "Apple\nBanana\nCherry"
    local original_content2 = "Dog\nElephant\nFrog"

    local search_text1 = "Banana"
    local replace_text1 = "Blueberry"

    local search_text2 = "Elephant"
    local replace_text2 = "Eagle"

    -- Create the files with original content
    Path:new(file1_path):write(original_content1, 'w')
    Path:new(file2_path):write(original_content2, 'w')
    assert.is_true(Path:new(file1_path):exists())
    assert.is_true(Path:new(file2_path):exists())

    local chatbuf = vim.api.nvim_create_buf(true, true)

    -- Insert modification blocks for both files
    -- Insert the modification block
    local mod_block1 = vim.split(
      table.concat({
        "ASSISTANT:",
        "@" .. test_dir:joinpath('multi_file1.txt'):absolute(),
        "<search>",
        search_text1,
        "</search>",
        "<replace>",
        replace_text1,
        "</replace>",
      }, "\n"),
      "\n"
    )

    local mod_block2 = {
      "@" .. test_dir:joinpath('multi_file2.txt'):absolute(),
      "<search>",
      search_text2,
      "</search>",
      "<replace>",
      replace_text2,
      "</replace>",
    }

    -- Insert both blocks into the first buffer
    vim.api.nvim_buf_set_lines(chatbuf, 0, -1, false, vim.list_extend(mod_block1, { '', unpack(mod_block2) }))

    -- Apply modifications with is_all = true
    file_editor.apply_modifications(chatbuf, true)

    -- Verify file1 has been modified
    local expected_content1 = "Apple\nBlueberry\nCherry"
    local content1 = Path:new(file1_path):read()
    assert.equals(expected_content1 .. "\n", content1)

    -- Verify file2 has been modified
    local expected_content2 = "Dog\nEagle\nFrog"
    local content2 = Path:new(file2_path):read()
    assert.equals(expected_content2 .. "\n", content2)

    local expected_chat_buf_content = {
      "ASSISTANT:",
      "@" .. test_dir:joinpath('multi_file1.txt'):absolute(),
      "<changes_applied>",
      replace_text1,
      "</changes_applied>",
      "",
      "@" .. test_dir:joinpath('multi_file2.txt'):absolute(),
      "<changes_applied>",
      replace_text2,
      "</changes_applied>",
    }

    assert.same(expected_chat_buf_content, vim.api.nvim_buf_get_lines(chatbuf, 0, -1, false))
  end)

  it("should handle the case where the search text is not found", function()
    local file_path = test_dir:joinpath('no_match.txt'):absolute()
    local original_content = "Line A\nLine B\nLine C"
    local search_text = "Line X"
    local replace_text = "Line Y"

    Path:new(file_path):write(original_content, 'w')
    assert.is_true(Path:new(file_path):exists())

    local chatbuf = vim.api.nvim_create_buf(true, true)

    -- Insert the modification block
    local mod_block = vim.split(
      table.concat({
        "@" .. test_dir:joinpath('no_match.txt'):absolute(),
        "<search>",
        search_text,
        "</search>",
        "<replace>",
        replace_text,
        "</replace>",
      }, "\n"),
      "\n"
    )
    vim.api.nvim_buf_set_lines(chatbuf, 0, -1, false, mod_block)

    -- Apply modifications
    -- Capture Neovim's error messages
    local err_messages = {}
    _G.vim.api.nvim_err_writeln = function(msg)
      table.insert(err_messages, msg)
    end

    vim.api.nvim_win_set_buf(0, chatbuf)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    file_editor.apply_modifications(chatbuf, false)

    -- Verify that an error message was displayed
    assert.is_true(#err_messages > 0)
    assert.is_not_nil(err_messages[1]:match("Could not find search pattern"))

    -- Verify the file remains unchanged
    local content = Path:new(file_path):read()
    assert.equals(original_content, content)

    -- Verify the buffer remains unchanged
    assert.same(mod_block, vim.api.nvim_buf_get_lines(chatbuf, 0, -1, false))
  end)

  it("should handle applying modifications with block_lines not present in the buffer", function()
    local file_path = test_dir:joinpath('missing_block.txt'):absolute()
    local original_content = "Line One\nLine Two\nLine Three"
    local search_text = "Line Two"
    local replace_text = "Second Line"

    -- Create the file with original content
    Path:new(file_path):write(original_content, 'w')
    assert.is_true(Path:new(file_path):exists())

    -- Create a buffer for the file
    local file_buf = vim.fn.bufadd(file_path)
    -- Manually delete all lines in the file buffer
    vim.api.nvim_buf_set_lines(file_buf, 0, #vim.split(original_content, "\n"), false, {})
    -- Open the file in a buffer
    local chatbuf = vim.api.nvim_create_buf(true, true)

    -- Insert a modification block that does not exist in the buffer
    local mod_block = vim.split(
      table.concat({
        "@" .. test_dir:joinpath('missing_block.txt'):absolute(),
        "<search>",
        search_text,
        "</search>",
        "<replace>",
        replace_text,
        "</replace>",
      }, "\n"),
      "\n"
    )
    vim.api.nvim_buf_set_lines(chatbuf, 0, -1, false, mod_block)

    -- Apply modifications
    -- Capture the error
    local err_messages = {}
    _G.vim.api.nvim_err_writeln = function(msg)
      table.insert(err_messages, msg)
    end

    vim.api.nvim_win_set_buf(0, chatbuf)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    file_editor.apply_modifications(chatbuf, false)

    -- Verify that an error message was displayed
    assert.is_true(#err_messages > 0)
    assert.is_not_nil(err_messages[1]:match("Could not find search pattern"))

    -- Verify the file remains unchanged
    local content = Path:new(file_path):read()
    assert.equals(original_content, content)
  end)

  it("should ignore blocks with changes_applied tags and apply valid blocks", function()
    local file_path = test_dir:joinpath('mixed_blocks.txt'):absolute()
    local original_content = "Line One\nLine Two\nLine Three"

    -- Create the file with original content
    Path:new(file_path):write(original_content, 'w')
    assert.is_true(Path:new(file_path):exists())

    -- Create a buffer with both types of blocks
    local chatbuf = vim.api.nvim_create_buf(true, true)
    local mod_blocks = {
      "ASSISTANT:",
      "@" .. file_path,
      "<changes_applied>",
      "This block should be ignored",
      "</changes_applied>",
      "",
      "@" .. file_path,
      "<search>",
      "Line Two",
      "</search>",
      "<replace>",
      "Modified Line",
      "</replace>",
    }
    vim.api.nvim_buf_set_lines(chatbuf, 0, -1, false, mod_blocks)

    -- Apply modifications
    vim.api.nvim_win_set_buf(0, chatbuf)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    file_editor.apply_modifications(chatbuf, true)

    -- Verify the file content was modified according to the valid block
    local expected_content = "Line One\nModified Line\nLine Three"
    local content = Path:new(file_path):read()
    assert.equals(expected_content .. "\n", content)

    -- Verify the buffer content reflects the changes correctly
    local expected_buffer_content = {
      "ASSISTANT:",
      "@" .. file_path,
      "<changes_applied>",
      "This block should be ignored",
      "</changes_applied>",
      "",
      "@" .. file_path,
      "<changes_applied>",
      "Modified Line",
      "</changes_applied>",
    }
    assert.same(expected_buffer_content, vim.api.nvim_buf_get_lines(chatbuf, 0, -1, false))
  end)

  it("should maintain original indentation when applying modifications with larger indent", function()
    local file_path = test_dir:joinpath('indent_test.py'):absolute()
    local original_content = "def hello():\n    print(\"Hello, World!\")"

    -- Create the file with original content
    Path:new(file_path):write(original_content, 'w')
    assert.is_true(Path:new(file_path):exists())

    -- Create a buffer for the modifications
    local chatbuf = vim.api.nvim_create_buf(true, true)

    -- Insert modification block with different indentation
    local mod_block = vim.split(
      table.concat({
        "@" .. test_dir:joinpath('indent_test.py'):absolute(),
        "<search>",
        "    def hello():",
        "        print(\"Hello, World!\")",
        "</search>",
        "<replace>",
        "    def hello():",
        "        print(\"Hello, Universe!\")",
        "</replace>",
      }, "\n"),
      "\n"
    )
    vim.api.nvim_buf_set_lines(chatbuf, 0, -1, false, mod_block)

    -- Apply modifications
    vim.api.nvim_win_set_buf(0, chatbuf)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    file_editor.apply_modifications(chatbuf, false)

    -- Verify the file content maintains original indentation
    local expected_content = "def hello():\n    print(\"Hello, Universe!\")"
    local content = Path:new(file_path):read()
    assert.equals(expected_content .. "\n", content)

    -- Verify the buffer reflects the changes with correct indentation
    local buffer_content = vim.api.nvim_buf_get_lines(chatbuf, 0, -1, false)
    local expected_buffer_content = {
      "@" .. test_dir:joinpath('indent_test.py'):absolute(),
      "<changes_applied>",
      "def hello():",
      "    print(\"Hello, Universe!\")",
      "</changes_applied>",
    }
    assert.same(expected_buffer_content, buffer_content)
  end)
end)

describe("find_modification_block", function()
  it("should find a single well-formed modification block", function()
    local lines = {
      "@mathweb/flask/app.py",
      "<search>",
      "from flask import Flask",
      "</search>",
      "<replace>",
      "import math",
      "from flask import Flask",
      "</replace>",
    }
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
    local lines = {
      "def hello():",
      "    print(\"Hello, World!\")",
    }
    local cursor_line = 2
    local result = file_editor.find_modification_block(cursor_line, lines)

    assert.same({}, result)
  end)

  it("should return empty table if block is incomplete (missing <replace>)", function()
    local lines = {
      "@main.py",
      "<search>",
      "def hello():",
      "    print(\"Hello, World!\")",
      "</search>",
    }
    local cursor_line = 2
    local result = file_editor.find_modification_block(cursor_line, lines)

    assert.same({}, result)
  end)

  it("should handle multiple modification blocks and find the correct one", function()
    local lines = {
      "@file1.py",
      "<search>",
      "old_code1",
      "</search>",
      "<replace>",
      "new_code1",
      "</replace>",
      "",
      "@file2.py",
      "<search>",
      "old_code2",
      "</search>",
      "<replace>",
      "new_code2",
      "</replace>",
    }
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
    local lines = {
      "@start_file.py",
      "<search>",
      "start_code",
      "</search>",
      "<replace>",
      "new_start_code",
      "</replace>",
      "",
      "Middle content",
      "",
      "@end_file.py",
      "<search>",
      "end_code",
      "</search>",
      "<replace>",
      "new_end_code",
      "</replace>",
    }
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
    local lines = {
      "Some unrelated line",
      "",
      "@file.py",
      "<search>",
      "code",
      "</search>",
      "<replace>",
      "new_code",
      "</replace>",
      "",
      "Some unrelated line",
    }
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
    local lines = {
      "@file1.py",
      "<search>",
      "code1",
      "@file2.py",
      "<replace>",
      "new_code2",
      "</replace>",
    }
    local cursor_line = 2 -- Line with "@file1.py" and start searching for block
    local result = file_editor.find_modification_block(cursor_line, lines)

    -- Since another '@' is found before '</replace>', it should return empty
    assert.same({}, result)
  end)

  it("should handle blocks with empty <search> and <replace> sections", function()
    local lines = {
      "@empty.py",
      "<search>",
      "</search>",
      "<replace>",
      "</replace>",
    }
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
    local lines = {
      "@first_line.py",
      "<search>",
      "code",
      "</search>",
      "<replace>",
      "new_code",
      "</replace>",
    }
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
    local lines = {
      "@complex.py",
      "<search>",
      "def func():",
      "    # Some comment",
      "    pass",
      "</search>",
      "<replace>",
      "def func():",
      "    print(\"Updated\")",
      "</replace>",
    }
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
    local lines = {
      "@app.py",
      "<search>",
      "from flask import Flask</search>",
      "<replace>",
      "import math",
      "from flask import Flask</replace>",
    }
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
    local lines = {
      "@app.py",
      "<search>",
      "print(\"hello\")</search>",
      "<replace>",
      "print(\"world\")",
      "</replace>",
    }
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
    local lines = {
      "@empty.py",
      "<search></search>",
      "<replace></replace>",
    }
    local cursor_line = 2
    local result = file_editor.find_modification_block(cursor_line, lines)

    assert.is_not_nil(result)
    assert.equals(0, #result)
  end)

  it("should handle multiple blocks with inline closing tags", function()
    local lines = {
      "@file1.py",
      "<search>old_code1</search>",
      "<replace>new_code1</replace>",
      "",
      "@file2.py",
      "<search>old_code2</search>",
      "<replace>new_code2</replace>",
    }
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
    local lines = {
      "@invalid.py",
      "<search>code</search>invalid</search>",
      "<replace>new</replace>code</replace>",
    }
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

  it("should ignore blocks with changes_applied tags and find regular blocks", function()
    local lines = {
      "@applied.py",
      "<changes_applied>",
      "def new_function():",
      "    print('Already applied')",
      "</changes_applied>",
      "",
      "@pending.py",
      "<search>",
      "def old_function():",
      "    pass",
      "</search>",
      "<replace>",
      "def old_function():",
      "    print('Not yet applied')",
      "</replace>",
    }

    -- Test cursor in changes_applied block
    local cursor_applied = 2
    local result_applied = file_editor.find_modification_block(cursor_applied, lines)
    assert.same({}, result_applied)

    -- Test cursor in regular block
    local cursor_regular = 8
    local result_regular = file_editor.find_modification_block(cursor_regular, lines)

    assert.is_not_nil(result_regular)
    assert.equals(9, #result_regular)
    assert.equals("@pending.py", result_regular[1])
    assert.equals("<search>", result_regular[2])
    assert.equals("def old_function():", result_regular[3])
    assert.equals("    pass", result_regular[4])
    assert.equals("</search>", result_regular[5])
    assert.equals("<replace>", result_regular[6])
    assert.equals("def old_function():", result_regular[7])
    assert.equals("    print('Not yet applied')", result_regular[8])
    assert.equals("</replace>", result_regular[9])
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
