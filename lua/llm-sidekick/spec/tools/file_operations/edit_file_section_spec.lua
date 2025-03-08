local Path = require('plenary.path')
local edit_file_section = require('llm-sidekick.tools.file_operations.edit_file_section')

describe("edit_file_section", function()
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

  describe("run", function()
    it("should modify an existing file by replacing search text with replace text", function()
      local file_path = test_dir:joinpath('modify_me.txt'):absolute()
      local original_content = "Hello World!\nThis is a test file.\nGoodbye World!"
      local search_text = "Hello World!"
      local replace_text = "Hello Universe!"

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
          end_lnum = 5
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

      -- Verify the file was modified correctly
      local expected_content = "Hello Universe!\nThis is a test file.\nGoodbye World!"
      local content = Path:new(file_path):read()
      assert.equals(expected_content .. "\n", content)
    end)

    it("should maintain original indentation when applying modifications with larger indent", function()
      local file_path = test_dir:joinpath('indent_test.py'):absolute()
      local original_content = "def hello():\n    print(\"Hello, World!\")"

      -- Create the file with original content
      Path:new(file_path):write(original_content, 'w')
      assert.is_true(Path:new(file_path):exists())

      -- Create a mock tool_call object with indented search
      local tool_call = {
        parameters = {
          path = file_path,
          search = "    def hello():\n        print(\"Hello, World!\")",
          replace = "    def hello():\n        print(\"Hello, Universe!\")"
        },
        state = {
          lnum = 1,
          end_lnum = 5
        }
      }

      -- Create a mock chat buffer
      local chat_bufnr = vim.api.nvim_create_buf(true, true)

      -- Run the function
      local success, err = pcall(edit_file_section.run, tool_call, { buffer = chat_bufnr })
      if not success then
        error(err)
      end

      assert.is_true(success)

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

      -- Create a mock tool_call object with less indented search
      local tool_call = {
        parameters = {
          path = file_path,
          search = "def hello():\n    print(\"Hello, World!\")",
          replace = "def hello():\n    print(\"Hello, Universe!\")"
        },
        state = {
          lnum = 1,
          end_lnum = 5
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

      -- Verify the file content maintains original indentation
      local expected_content = "    def hello():\n        print(\"Hello, Universe!\")"
      local content = Path:new(file_path):read()
      assert.equals(expected_content .. "\n", content)
    end)

    it("should throw an error when search text is not found", function()
      local file_path = test_dir:joinpath('no_match.txt'):absolute()
      local original_content = "Line A\nLine B\nLine C"
      local search_text = "Line X"
      local replace_text = "Line Y"

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
          end_lnum = 5
        }
      }

      -- Create a mock chat buffer
      local chat_bufnr = vim.api.nvim_create_buf(true, true)

      -- Run the function and expect an error
      local success, err = pcall(edit_file_section.run, tool_call, { buffer = chat_bufnr })

      -- Assert that the function failed
      assert.is_false(success)
      -- Check that the error message contains the expected text
      assert.is_not_nil(err:match("Could not find the exact match"))

      -- Verify the file remains unchanged
      local content = Path:new(file_path):read()
      assert.equals(original_content, content)
    end)

    it("should handle editing a file that is already open in a buffer", function()
      local file_path = test_dir:joinpath('buffer_edit.txt'):absolute()
      local original_content = "First line\nSecond line\nThird line"
      local search_text = "Second line"
      local replace_text = "Modified second line"

      -- Create the file with original content
      Path:new(file_path):write(original_content, 'w')
      assert.is_true(Path:new(file_path):exists())

      -- Open the file in a buffer
      local bufnr = vim.fn.bufadd(file_path)
      vim.fn.bufload(bufnr)

      -- Create a mock tool_call object
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

      -- Create a mock chat buffer
      local chat_bufnr = vim.api.nvim_create_buf(true, true)

      -- Run the function
      local success, err = pcall(edit_file_section.run, tool_call, { buffer = chat_bufnr })
      if not success then
        error(err)
      end

      -- Assert that the function ran successfully
      assert.is_true(success)

      -- Verify the file was modified correctly
      local expected_content = "First line\nModified second line\nThird line"
      local content = Path:new(file_path):read()
      assert.equals(expected_content .. "\n", content)

      -- Also verify the buffer content was updated
      local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.equals(expected_content, table.concat(buffer_lines, "\n"))
    end)

    it("should throw an error when the file cannot be read", function()
      local file_path = test_dir:joinpath('nonexistent.txt'):absolute()

      -- Create a mock tool_call object
      local tool_call = {
        parameters = {
          path = file_path,
          search = "Some text",
          replace = "New text"
        },
        state = {
          lnum = 1,
          end_lnum = 5
        }
      }

      -- Create a mock chat buffer
      local chat_bufnr = vim.api.nvim_create_buf(true, true)

      -- Run the function and expect an error
      local success, err = pcall(edit_file_section.run, tool_call, { buffer = chat_bufnr })

      -- Assert that the function failed
      assert.is_false(success)
      -- Check that the error message contains the expected text
      assert.is_not_nil(err:match("Failed to read file"))
    end)

    it("should handle empty replacement to remove a line", function()
      local file_path = test_dir:joinpath('remove_line.txt'):absolute()
      local original_content = "Line 1\nLine to remove\nLine 3"
      local search_text = "Line to remove"
      local replace_text = ""

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
          end_lnum = 5
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

      -- Verify the file was modified correctly with the line removed
      local expected_content = "Line 1\nLine 3"
      local content = Path:new(file_path):read()
      assert.equals(expected_content .. "\n", content)
    end)
  end)
end)
