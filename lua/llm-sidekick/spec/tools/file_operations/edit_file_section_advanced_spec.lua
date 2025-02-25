local Path = require('plenary.path')
local edit_file_section = require('llm-sidekick.tools.file_operations.edit_file_section')

describe("edit_file_section advanced scenarios", function()
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

  describe("run with complex scenarios", function()
    it("should handle multiline replacements with mixed indentation", function()
      local file_path = test_dir:joinpath('complex_indent.lua'):absolute()
      local original_content = [[
local function test()
  if condition then
    for i = 1, 10 do
      print(i)
      if i > 5 then
        print("Greater than 5")
      end
    end
  end
end]]

      local search_text = [[  if condition then
    for i = 1, 10 do
      print(i)
      if i > 5 then
        print("Greater than 5")
      end
    end]]

      local replace_text = [[  if condition then
    for i = 1, 10 do
      print("Number: " .. i)
      if i > 5 then
        print("Greater than 5")
        print("Almost done!")
      end
    end]]

      -- Create the file with original content
      Path:new(file_path):write(original_content, 'w')
      assert.is_true(Path:new(file_path):exists())

      -- Create a mock tool_call object
      local tool_call = {
        parameters = {
          path = file_path,
          search = search_text,
          replace = replace_text
        },
        state = {
          lnum = 1,
          end_lnum = 10
        }
      }

      -- Create a mock chat buffer
      local chat_bufnr = vim.api.nvim_create_buf(true, true)

      -- Run the function
      local success, err = pcall(edit_file_section.run, tool_call, { buffer = chat_bufnr })
      if not success then
        error(err)
      end

      -- Assert that the function ran successfully
      assert.is_true(success)

      -- Expected result after replacement
      local expected_content = [[
local function test()
  if condition then
    for i = 1, 10 do
      print("Number: " .. i)
      if i > 5 then
        print("Greater than 5")
        print("Almost done!")
      end
    end
  end
end]]

      local content = Path:new(file_path):read()
      assert.equals(expected_content .. "\n", content)
    end)

    it("should handle replacements at the beginning of the file", function()
      local file_path = test_dir:joinpath('beginning_file.txt'):absolute()
      local original_content = "First line\nSecond line\nThird line"
      local search_text = "First line"
      local replace_text = "New first line"

      Path:new(file_path):write(original_content, 'w')
      assert.is_true(Path:new(file_path):exists())

      local tool_call = {
        parameters = {
          path = file_path,
          search = search_text,
          replace = replace_text
        },
        state = {
          lnum = 1,
          end_lnum = 3
        }
      }

      local chat_bufnr = vim.api.nvim_create_buf(true, true)
      local success, err = pcall(edit_file_section.run, tool_call, { buffer = chat_bufnr })
      if not success then
        error(err)
      end

      assert.is_true(success)
      local expected_content = "New first line\nSecond line\nThird line"
      local content = Path:new(file_path):read()
      assert.equals(expected_content .. "\n", content)
    end)

    it("should handle replacements at the end of the file", function()
      local file_path = test_dir:joinpath('end_file.txt'):absolute()
      local original_content = "First line\nSecond line\nThird line"
      local search_text = "Third line"
      local replace_text = "New third line"

      Path:new(file_path):write(original_content, 'w')
      assert.is_true(Path:new(file_path):exists())

      local tool_call = {
        parameters = {
          path = file_path,
          search = search_text,
          replace = replace_text
        },
        state = {
          lnum = 1,
          end_lnum = 3
        }
      }

      local chat_bufnr = vim.api.nvim_create_buf(true, true)
      local success, err = pcall(edit_file_section.run, tool_call, { buffer = chat_bufnr })
      if not success then
        error(err)
      end

      assert.is_true(success)
      local expected_content = "First line\nSecond line\nNew third line"
      local content = Path:new(file_path):read()
      assert.equals(expected_content .. "\n", content)
    end)

    it("should handle replacements with empty lines in search and replace", function()
      local file_path = test_dir:joinpath('empty_lines.txt'):absolute()
      local original_content = "Line 1\n\nLine 3\n\nLine 5"
      local search_text = "Line 3\n\nLine 5"
      local replace_text = "Line 3\nNew Line 4\nLine 5"

      Path:new(file_path):write(original_content, 'w')
      assert.is_true(Path:new(file_path):exists())

      local tool_call = {
        parameters = {
          path = file_path,
          search = search_text,
          replace = replace_text
        },
        state = {
          lnum = 1,
          end_lnum = 5
        }
      }

      local chat_bufnr = vim.api.nvim_create_buf(true, true)
      local success, err = pcall(edit_file_section.run, tool_call, { buffer = chat_bufnr })
      if not success then
        error(err)
      end

      assert.is_true(success)
      local expected_content = "Line 1\n\nLine 3\nNew Line 4\nLine 5"
      local content = Path:new(file_path):read()
      assert.equals(expected_content .. "\n", content)
    end)

    it("should handle special characters in search and replace", function()
      local file_path = test_dir:joinpath('special_chars.txt'):absolute()
      local original_content =
      "Line with (parentheses), [brackets] and {braces}\nSecond line with * special ^ characters $ and % percent"
      local search_text = "Line with (parentheses), [brackets] and {braces}"
      local replace_text = "Line with (parentheses), [square brackets] and {braces}"

      Path:new(file_path):write(original_content, 'w')
      assert.is_true(Path:new(file_path):exists())

      local tool_call = {
        parameters = {
          path = file_path,
          search = search_text,
          replace = replace_text
        },
        state = {
          lnum = 1,
          end_lnum = 3
        }
      }

      local chat_bufnr = vim.api.nvim_create_buf(true, true)
      local success, err = pcall(edit_file_section.run, tool_call, { buffer = chat_bufnr })
      if not success then
        error(err)
      end

      assert.is_true(success)
      local expected_content =
      "Line with (parentheses), [square brackets] and {braces}\nSecond line with * special ^ characters $ and % percent"
      local content = Path:new(file_path):read()
      assert.equals(expected_content .. "\n", content)
    end)

    it("should handle multiple identical search patterns and replace the first occurrence", function()
      local file_path = test_dir:joinpath('multiple_matches.txt'):absolute()
      local original_content = "Repeated line\nSome other content\nRepeated line"
      local search_text = "Repeated line"
      local replace_text = "Modified line"

      Path:new(file_path):write(original_content, 'w')
      assert.is_true(Path:new(file_path):exists())

      local tool_call = {
        parameters = {
          path = file_path,
          search = search_text,
          replace = replace_text
        },
        state = {
          lnum = 1,
          end_lnum = 3
        }
      }

      local chat_bufnr = vim.api.nvim_create_buf(true, true)
      local success, err = pcall(edit_file_section.run, tool_call, { buffer = chat_bufnr })
      if not success then
        error(err)
      end

      assert.is_true(success)
      local expected_content = "Modified line\nSome other content\nRepeated line"
      local content = Path:new(file_path):read()
      assert.equals(expected_content .. "\n", content)
    end)

    it("should handle very large files efficiently", function()
      local file_path = test_dir:joinpath('large_file.txt'):absolute()

      -- Create a large file (100,000 lines)
      local file = io.open(file_path, 'w')
      assert.is_not_nil(file)

      -- Write 99,998 lines of filler content
      for i = 1, 99998 do
        file:write("Line " .. i .. "\n")
      end

      -- Write target content to replace
      file:write("This is the target line 1\n")
      file:write("This is the target line 2\n")
      file:close()

      assert.is_true(Path:new(file_path):exists())

      -- Create a mock tool_call object
      local tool_call = {
        parameters = {
          path = file_path,
          search = "This is the target line 1\nThis is the target line 2",
          replace = "This line has been replaced 1\nThis line has been replaced 2"
        },
        state = {
          lnum = 1,
          end_lnum = 5
        }
      }

      -- Create a mock chat buffer
      local chat_bufnr = vim.api.nvim_create_buf(true, true)

      -- Run the function and measure memory usage
      local success, err = pcall(edit_file_section.run, tool_call, { buffer = chat_bufnr })
      if not success then
        error(err)
      end

      -- Assert that the function ran successfully
      assert.is_true(success)

      -- Verify the last two lines were replaced correctly
      local file_handle = io.open(file_path, 'r')
      assert.is_not_nil(file_handle)

      -- Go to the end of the file
      file_handle:seek("end", -100) -- Go near the end
      local last_lines = file_handle:read("*a")
      file_handle:close()

      -- Check that the replacement text is in the file
      assert.is_not_nil(last_lines:match("This line has been replaced 1"))
      assert.is_not_nil(last_lines:match("This line has been replaced 2"))
    end)
  end)
end)
