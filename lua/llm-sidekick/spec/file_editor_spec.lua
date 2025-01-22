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

  it("should delete a file", function()
    local file_path = test_dir:joinpath('delete_me.txt'):absolute()

    Path:new(file_path):write('', 'w')
    local chatbuf = vim.api.nvim_create_buf(true, true)
    local mod_block = {
      "ASSISTANT:",
      "@" .. test_dir:joinpath('delete_me.txt'):absolute(),
      "<delete />",
    }
    vim.api.nvim_buf_set_lines(chatbuf, 0, -1, false, mod_block)

    file_editor.apply_modifications(chatbuf, true)
    assert.is_false(Path:new(file_path):exists())

    local diagnostics = vim.diagnostic.get(chatbuf, { severity = vim.diagnostic.severity.INFO })
    assert.is_not_nil(diagnostics)
    assert.equals(1, #diagnostics)
    assert.is_not_nil(diagnostics[1].message:match("Successfully deleted file"))
  end)

  it("should create a new file", function()
    local file_path = test_dir:joinpath('new_file.txt'):absolute()
    local replace_content = "This is a new file.\nWith multiple lines."

    assert.is_false(Path:new(file_path):exists())

    local chatbuf = vim.api.nvim_create_buf(true, true)
    local mod_block = {
      "ASSISTANT: @" .. test_dir:joinpath('new_file.txt'):absolute(),
      "<create>",
      "This is a new file.",
      "With multiple lines.",
      "</create>",
    }
    vim.api.nvim_buf_set_lines(chatbuf, 0, -1, false, mod_block)

    file_editor.apply_modifications(chatbuf, true)

    assert.is_true(Path:new(file_path):exists())
    local content = Path:new(file_path):read()
    assert.equals(replace_content .. "\n", content)

    local diagnostics = vim.diagnostic.get(chatbuf, { severity = vim.diagnostic.severity.INFO })
    assert.is_not_nil(diagnostics)
    assert.equals(1, #diagnostics)
    assert.is_not_nil(diagnostics[1].message:match("Successfully created file"))
  end)

  it("should create a new file with underscore in filename", function()
    local file_path = test_dir:joinpath('views/users/_index.html.erb'):absolute()
    local replace_content = "This is a new file with underscore.\nIt should be created."

    assert.is_false(Path:new(file_path):exists())

    local chatbuf = vim.api.nvim_create_buf(true, true)
    local mod_block = {
      "ASSISTANT:",
      "@" .. file_path,
      "<create>",
      "This is a new file with underscore.",
      "It should be created.",
      "</create>",
    }
    vim.api.nvim_buf_set_lines(chatbuf, 0, -1, false, mod_block)

    file_editor.apply_modifications(chatbuf, true)

    assert.is_true(Path:new(file_path):exists())
    local content = Path:new(file_path):read()
    assert.equals(replace_content .. "\n", content)

    local diagnostics = vim.diagnostic.get(chatbuf, { severity = vim.diagnostic.severity.INFO })
    assert.is_not_nil(diagnostics)
    assert.equals(1, #diagnostics)
    assert.is_not_nil(diagnostics[1].message:match("Successfully created file"))
  end)

  it("should modify an existing file by replacing search text with replace text", function()
    local file_path = test_dir:joinpath('modify_me.txt'):absolute()
    local original_content = "Hello World!\nThis is a test file.\nGoodbye World!"
    local search_text = "Hello World!"
    local replace_text = "Hello Universe!"

    Path:new(file_path):write(original_content, 'w')
    assert.is_true(Path:new(file_path):exists())

    local bufnr = vim.api.nvim_create_buf(true, true)

    local mod_block = {
      "ASSISTANT:",
      "@" .. test_dir:joinpath('modify_me.txt'):absolute(),
      "<search>",
      search_text,
      "</search>",
      "<replace>",
      replace_text,
      "</replace>",
    }
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, mod_block)

    file_editor.apply_modifications(bufnr, true)

    local expected_content = "Hello Universe!\nThis is a test file.\nGoodbye World!"
    local content = Path:new(file_path):read()
    assert.equals(expected_content .. "\n", content)

    local diagnostics = vim.diagnostic.get(bufnr, { severity = vim.diagnostic.severity.INFO })
    assert.is_not_nil(diagnostics)
    assert.equals(1, #diagnostics)
    assert.is_not_nil(diagnostics[1].message:match("Successfully updated file"))
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
    local mod_block_1 = {
      "ASSISTANT:",
      "@" .. test_dir:joinpath('multi_modify.txt'):absolute(),
      "<search>",
      search_text_1,
      "</search>",
      "<replace>",
      replace_text_1,
      "</replace>",
    }
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, mod_block_1)

    -- Apply first modification
    file_editor.apply_modifications(bufnr, true)

    -- Verify the first modification
    local expected_content_1 = "Line 1\nSecond Line\nLine 3\nLine 4"
    local content_1 = Path:new(file_path):read()
    assert.equals(expected_content_1 .. "\n", content_1)

    local diagnostics = vim.diagnostic.get(bufnr, { severity = vim.diagnostic.severity.INFO })
    assert.is_not_nil(diagnostics)
    assert.equals(1, #diagnostics)
    assert.is_not_nil(diagnostics[1].message:match("Successfully updated file"))

    -- Insert the second modification block below the first
    local mod_block_2 = {
      "ASSISTANT:",
      "@" .. test_dir:joinpath('multi_modify.txt'):absolute(),
      "<search>",
      search_text_2,
      "</search>",
      "<replace>",
      replace_text_2,
      "</replace>",
    }
    vim.api.nvim_buf_set_lines(bufnr, #mod_block_1, -1, false, mod_block_2)

    -- Apply second modification
    file_editor.apply_modifications(bufnr, true)

    -- Verify the second modification
    local expected_content_2 = "Line 1\nSecond Line\nLine 3\nFourth Line"
    local content_2 = Path:new(file_path):read()
    assert.equals(expected_content_2 .. "\n", content_2)

    diagnostics = vim.diagnostic.get(bufnr, { severity = vim.diagnostic.severity.INFO })
    assert.is_not_nil(diagnostics)
    assert.equals(2, #diagnostics)
    assert.is_not_nil(diagnostics[1].message:match("Successfully updated file"))
    assert.is_not_nil(diagnostics[2].message:match("Successfully updated file"))
  end)

  it("should handle applying modifications to multiple files", function()
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

    local mod_block = {
      "ASSISTANT:",
      "@" .. test_dir:joinpath('multi_file1.txt'):absolute(),
      "<search>",
      search_text1,
      "</search>",
      "<replace>",
      replace_text1,
      "</replace>",
      "@" .. test_dir:joinpath('multi_file2.txt'):absolute(),
      "<search>",
      search_text2,
      "</search>",
      "<replace>",
      replace_text2,
      "</replace>",
    }
    vim.api.nvim_buf_set_lines(chatbuf, 0, -1, false, mod_block)

    file_editor.apply_modifications(chatbuf, true)

    -- Verify file1 has been modified
    local expected_content1 = "Apple\nBlueberry\nCherry"
    local content1 = Path:new(file1_path):read()
    assert.equals(expected_content1 .. "\n", content1)

    -- Verify file2 has been modified
    local expected_content2 = "Dog\nEagle\nFrog"
    local content2 = Path:new(file2_path):read()
    assert.equals(expected_content2 .. "\n", content2)
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
    local mod_block = {
      "ASSISTANT:",
      "@" .. test_dir:joinpath('no_match.txt'):absolute(),
      "<search>",
      search_text,
      "</search>",
      "<replace>",
      replace_text,
      "</replace>",
    }
    vim.api.nvim_buf_set_lines(chatbuf, 0, -1, false, mod_block)

    file_editor.apply_modifications(chatbuf, true)

    -- Verify the file remains unchanged
    local content = Path:new(file_path):read()
    assert.equals(original_content, content)

    local errors = vim.diagnostic.get(chatbuf, { severity = vim.diagnostic.severity.ERROR })
    assert.is_not_nil(errors)
    assert.is_true(#errors > 0)
    assert.is_not_nil(errors[1].message:match("Could not find search pattern"))
  end)

  it("skip modifications with block_lines not present in the buffer", function()
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
    local mod_block = {
      "ASSISTANT:",
      "@" .. test_dir:joinpath('missing_block.txt'):absolute(),
      "<search>",
      search_text,
      "</search>",
      "<replace>",
      replace_text,
      "</replace>",
    }
    vim.api.nvim_buf_set_lines(chatbuf, 0, -1, false, mod_block)

    file_editor.apply_modifications(chatbuf, true)

    -- Verify the file remains unchanged
    local content = Path:new(file_path):read()
    assert.equals(original_content, content)
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
    local mod_block = {
      "ASSISTANT:",
      "@" .. test_dir:joinpath('indent_test.py'):absolute(),
      "<search>",
      "    def hello():",
      "        print(\"Hello, World!\")",
      "</search>",
      "<replace>",
      "    def hello():",
      "        print(\"Hello, Universe!\")",
      "</replace>",
    }
    vim.api.nvim_buf_set_lines(chatbuf, 0, -1, false, mod_block)

    -- Apply modifications
    file_editor.apply_modifications(chatbuf, true)

    -- Verify the file content maintains original indentation
    local expected_content = "def hello():\n    print(\"Hello, Universe!\")"
    local content = Path:new(file_path):read()
    assert.equals(expected_content .. "\n", content)
  end)

  it("should maintain original indentation when applying modifications with smaller indent", function()
    local file_path = test_dir:joinpath('indent_test.py'):absolute()
    local original_content = "    def hello():\n        print(\"Hello, World!\")"

    -- Create the file with original content
    Path:new(file_path):write(original_content, 'w')
    assert.is_true(Path:new(file_path):exists())

    -- Create a buffer for the modifications
    local chatbuf = vim.api.nvim_create_buf(true, true)

    -- Insert modification block with different indentation
    local mod_block = {
      "ASSISTANT:",
      "@" .. test_dir:joinpath('indent_test.py'):absolute(),
      "<search>",
      "def hello():",
      "    print(\"Hello, World!\")",
      "</search>",
      "<replace>",
      "def hello():",
      "    print(\"Hello, Universe!\")",
      "</replace>",
    }
    vim.api.nvim_buf_set_lines(chatbuf, 0, -1, false, mod_block)

    -- Apply modifications
    file_editor.apply_modifications(chatbuf, true)

    -- Verify the file content maintains original indentation
    local expected_content = "    def hello():\n        print(\"Hello, Universe!\")"
    local content = Path:new(file_path):read()
    assert.equals(expected_content .. "\n", content)
  end)

  it("should handle search and replace tags not ending on their own line", function()
    local file_path = test_dir:joinpath('inline_tags.txt'):absolute()
    local original_content = "This is a test.\nAnother line.\nEnd of file."
    local search_text = "Another line."
    local replace_text = "Modified line."

    -- Create the file with original content
    Path:new(file_path):write(original_content, 'w')
    assert.is_true(Path:new(file_path):exists())

    -- Create a buffer for the modifications
    local chatbuf = vim.api.nvim_create_buf(true, true)

    -- Insert modification block with inline tags
    local mod_block = {
      "ASSISTANT:",
      "@" .. test_dir:joinpath('inline_tags.txt'):absolute(),
      "<search>",
      search_text .. "</search>",
      "<replace>",
      replace_text .. "</replace>",
    }
    vim.api.nvim_buf_set_lines(chatbuf, 0, -1, false, mod_block)

    -- Apply modifications
    file_editor.apply_modifications(chatbuf, true)

    -- Verify the file content
    local expected_content = "This is a test.\nModified line.\nEnd of file."
    local content = Path:new(file_path):read()
    assert.equals(expected_content .. "\n", content)
  end)

  it("should handle search and replace tags not starting on their own line", function()
    local file_path = test_dir:joinpath('inline_tags.txt'):absolute()
    local original_content = "This is a test.\nAnother line.\nEnd of file."
    local search_text = "Another line."
    local replace_text = "Modified line."

    -- Create the file with original content
    Path:new(file_path):write(original_content, 'w')
    assert.is_true(Path:new(file_path):exists())

    -- Create a buffer for the modifications
    local chatbuf = vim.api.nvim_create_buf(true, true)

    -- Insert modification block with inline tags
    local mod_block = {
      "ASSISTANT:",
      "@" .. test_dir:joinpath('inline_tags.txt'):absolute(),
      "<search>" .. search_text,
      "</search>",
      "<replace>" .. replace_text,
      "</replace>",
    }
    vim.api.nvim_buf_set_lines(chatbuf, 0, -1, false, mod_block)

    -- Apply modifications
    file_editor.apply_modifications(chatbuf, true)

    -- Verify the file content
    local expected_content = "This is a test.\nModified line.\nEnd of file."
    local content = Path:new(file_path):read()
    assert.equals(expected_content .. "\n", content)
  end)

  it("should handle search and replace tags not starting and ending on their own line", function()
    local file_path = test_dir:joinpath('inline_tags.txt'):absolute()
    local original_content = "This is a test.\nAnother line.\nEnd of file."
    local search_text = "Another line."
    local replace_text = "Modified line."

    -- Create the file with original content
    Path:new(file_path):write(original_content, 'w')
    assert.is_true(Path:new(file_path):exists())

    -- Create a buffer for the modifications
    local chatbuf = vim.api.nvim_create_buf(true, true)

    -- Insert modification block with inline tags
    local mod_block = {
      "ASSISTANT:",
      "@" .. test_dir:joinpath('inline_tags.txt'):absolute(),
      "<search>" .. search_text .. "</search>",
      "<replace>" .. replace_text .. "</replace>",
    }
    vim.api.nvim_buf_set_lines(chatbuf, 0, -1, false, mod_block)

    -- Apply modifications
    file_editor.apply_modifications(chatbuf, true)

    -- Verify the file content
    local expected_content = "This is a test.\nModified line.\nEnd of file."
    local content = Path:new(file_path):read()
    assert.equals(expected_content .. "\n", content)
  end)
end)
