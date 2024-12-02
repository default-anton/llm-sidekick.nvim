if vim.g.loaded_llm_sidekick == 1 then
  return
end

vim.g.loaded_llm_sidekick = 1
vim.g.llm_sidekick_last_ask_buffer = nil

local M = {}

local bedrock = require "llm-sidekick.bedrock"
local markdown = require "llm-sidekick.markdown"
local prompts = require "llm-sidekick.prompts"
local default_filetypes = require "llm-sidekick.filetypes"
local file_editor = require "llm-sidekick.file_editor"
local llm_sidekick = require "llm-sidekick"
local current_project_config = {}

local OPEN_MODES = { "tab", "vsplit", "split" }
local MODE_SHORTCUTS = {
  t = "tab",
  v = "vsplit",
  s = "split"
}
local MODEL_TYPES = { "smart", "fast", "reasoning" }

local function load_project_config()
  local project_config_path = vim.fn.getcwd() .. "/.llmsidekick.lua"
  if vim.fn.filereadable(project_config_path) == 1 then
    local ok, config = pcall(dofile, project_config_path)
    if ok and type(config) == "table" then
      current_project_config = config
    else
      vim.api.nvim_err_writeln("Invalid .llmsidekick.lua file. Expected a table.")
    end
  end
end

load_project_config()

local function get_filetype_config(ft)
  if current_project_config and current_project_config.filetypes and current_project_config.filetypes[ft] then
    return vim.tbl_deep_extend("force", default_filetypes[ft] or {}, current_project_config.filetypes[ft])
  else
    return default_filetypes[ft]
  end
end

vim.api.nvim_create_augroup("LLMSidekickProjectConfig", { clear = true })
vim.api.nvim_create_autocmd("DirChanged", {
  group = "LLMSidekickProjectConfig",
  callback = load_project_config,
  desc = "Reload LLM Sidekick project configuration when changing directories",
})

local function set_last_ask_buffer()
  local current_buf = vim.api.nvim_get_current_buf()
  local is_ask_buffer = pcall(vim.api.nvim_buf_get_var, current_buf, "is_llm_sidekick_ask_buffer")
  if is_ask_buffer then
    vim.g.llm_sidekick_last_ask_buffer = current_buf
  end
end

vim.api.nvim_create_augroup("LLMSidekickLastAskBuffer", { clear = true })
vim.api.nvim_create_autocmd({ "BufEnter", "FocusGained" }, {
  group = "LLMSidekickLastAskBuffer",
  callback = set_last_ask_buffer,
  desc = "Set last ask buffer when focused (only for Ask buffers)",
})

local function open_buffer_in_mode(buf, mode)
  if mode == "current" then
    vim.api.nvim_set_current_buf(buf)
  elseif mode == "tab" then
    vim.cmd("tabnew")
    vim.api.nvim_set_current_buf(buf)
  elseif mode == "vsplit" then
    vim.cmd("vsplit")
    vim.api.nvim_set_current_buf(buf)
  elseif mode == "split" then
    vim.cmd("split")
    vim.api.nvim_set_current_buf(buf)
  else
    error("Invalid opening mode")
  end
end

local function parse_ask_args(args)
  local settings = require("llm-sidekick.settings")
  local parsed = {
    model = settings.get_smart_model(),
    open_mode = "current",
    append_current_file = false
  }
  for _, arg in ipairs(args) do
    if arg == "smart" then
      parsed.model = settings.get_smart_model()
    elseif arg == "fast" then
      parsed.model = settings.get_fast_model()
    elseif arg == "reasoning" then
      parsed.model = settings.get_reasoning_model()
    elseif vim.tbl_contains(OPEN_MODES, arg) then
      parsed.open_mode = arg
    elseif MODE_SHORTCUTS[arg] ~= nil then
      parsed.open_mode = MODE_SHORTCUTS[arg]
    elseif arg == "file" or arg == "f" then
      parsed.append_current_file = true
    else
      error("Invalid argument: " .. arg)
    end
  end
  return parsed
end

local function set_llm_sidekick_options()
  vim.opt_local.formatoptions:remove "t"
  vim.opt_local.formatoptions:remove "c"
  vim.opt_local.wrap = true
  vim.opt_local.textwidth = 0
  vim.opt_local.scrollbind = false
  vim.opt_local.signcolumn = "no"
end

-- Function to fold the contents of the <editor_context> tag in a given buffer
local function fold_editor_context(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local start_line, end_line
  for i, line in ipairs(lines) do
    if line:match("^<editor_context>") then
      start_line = i
      for j = i + 1, #lines do
        if lines[j]:match("^</editor_context>") then
          end_line = j
          break
        end
      end
      break
    end
  end
  if start_line and end_line and end_line > start_line then
    vim.api.nvim_set_option_value('foldmethod', 'manual', {})
    -- Delete any existing fold in the region
    pcall(function()
      vim.cmd(string.format("%dnormal zd", start_line))
    end)
    vim.api.nvim_command(string.format("%d,%dfold", start_line, end_line))
  end
end

local function render_snippet(relative_path, content, code)
  return string.format([[
%s
```%s
%s
```
]], relative_path, code, content)
end

local function render_editor_context(snippets)
  return string.format([[
<editor_context>
%s
</editor_context>
]], snippets)
end

local function is_file_prompt(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 3, false)
  if #lines < 3 then
    return false
  end

  local required_keywords = {
    ["MODEL:"] = false,
    ["TEMPERATURE:"] = false,
    ["MAX_TOKENS:"] = false
  }

  for _, line in ipairs(lines) do
    for keyword, _ in pairs(required_keywords) do
      if vim.startswith(line, keyword) then
        required_keywords[keyword] = true
        break
      end
    end
  end

  for _, found in pairs(required_keywords) do
    if not found then
      return false
    end
  end

  return true
end

local ask_command = function(cmd_opts)
  return function(opts)
    local filetype = vim.api.nvim_get_option_value("filetype", { buf = 0 })
    local language = get_filetype_config(filetype)

    local parsed_args = parse_ask_args(opts.fargs)
    local model = parsed_args.model
    local open_mode = parsed_args.open_mode
    local append_current_file = parsed_args.append_current_file
    local range_start = -1
    local range_end = -1

    if opts.range == 2 then
      range_start = opts.line1
      range_end = opts.line2
    end

    if append_current_file then
      range_start = 1
      range_end = vim.api.nvim_buf_line_count(0)
    end

    local model_settings = llm_sidekick.get_model_default_settings(model)

    local settings = {
      model = model,
      max_tokens = model_settings.max_tokens,
      temperature = model_settings.temperature,
    }

    local prompt = ""

    if is_file_prompt(0) then
      prompt = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    else
      for key, value in pairs(settings) do
        prompt = prompt .. key:upper() .. ": " .. value .. "\n"
      end

      local guidelines = cmd_opts.include_modifications and prompts.modifications or ""
      if language.guidelines and vim.trim(language.guidelines) ~= "" then
        guidelines = guidelines .. "\n\n" .. language.guidelines
      end
      if vim.startswith(model, "o1") then
        guidelines = guidelines:gsub("Claude", "You")
      end

      if language.code == "" then
        if not vim.startswith(model, "o1") then
          prompt = prompt ..
              "SYSTEM: " ..
              string.format(vim.trim(prompts.generic_system_prompt), os.date("%B %d, %Y"), vim.trim(guidelines))
        end
      else
        local system_prompt = prompts.system_prompt
        if vim.startswith(model, "o1") then
          system_prompt = prompts.openai_coding
        end
        prompt = prompt ..
            "SYSTEM: " ..
            string.format(vim.trim(system_prompt), os.date("%B %d, %Y"), vim.trim(guidelines),
              vim.trim(language.technologies))
      end

      prompt = prompt .. "\nUSER: "
      if range_start >= 0 and range_end >= 0 then
        local relative_path = vim.fn.expand("%")
        local context = table.concat(vim.api.nvim_buf_get_lines(0, range_start - 1, range_end, false), "\n")
        prompt = prompt .. "Here is what I'm working on:\n"
        local snippet = render_snippet(relative_path, context, language.code)
        prompt = prompt .. render_editor_context(snippet) .. "\n"
      end
    end

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_var(buf, "is_llm_sidekick_ask_buffer", true)
    vim.g.llm_sidekick_last_ask_buffer = buf
    vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
    if cmd_opts.include_modifications then
      file_editor.create_apply_modifications_command(buf)
    end
    open_buffer_in_mode(buf, open_mode)
    set_llm_sidekick_options()

    vim.api.nvim_buf_set_keymap(
      buf,
      "n",
      "<CR>",
      string.format("<cmd>lua require('llm-sidekick').ask(%d)<CR>", buf),
      { nowait = true, noremap = true, silent = true }
    )

    local lines = vim.split(prompt, "[\r]?\n")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_call(buf, function()
      -- Create a fold from line 1 to the line just before the first occurrence of "^USER:".
      vim.cmd('1,/^USER:/-1fold')
      fold_editor_context(buf)
    end)
    -- Set cursor to the end of the buffer
    vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(buf), 0 })
    -- Enter insert mode at the end of the line
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('A', true, false, true), 'n', false)

    vim.schedule(function()
      bedrock.start_web_server()
    end)
  end
end

vim.api.nvim_create_user_command("Ask", ask_command({ include_modifications = false }), {
  range = true,
  nargs = "*",
  complete = function(ArgLead, CmdLine, CursorPos)
    local args = vim.split(CmdLine, "%s+")
    local options = { "file" }
    vim.list_extend(options, MODEL_TYPES)
    vim.list_extend(options, OPEN_MODES)
    return vim.tbl_filter(function(item)
      return item:lower():match("^" .. ArgLead:lower()) and not vim.tbl_contains(args, item)
    end, options)
  end,
})

vim.api.nvim_create_user_command("Code", ask_command({ include_modifications = true }), {
  range = true,
  nargs = "*",
  complete = function(ArgLead, CmdLine, CursorPos)
    local args = vim.split(CmdLine, "%s+")
    local options = { "file" }
    vim.list_extend(options, MODEL_TYPES)
    vim.list_extend(options, OPEN_MODES)
    return vim.tbl_filter(function(item)
      return item:lower():match("^" .. ArgLead:lower()) and not vim.tbl_contains(args, item)
    end, options)
  end,
})

local function get_content(opts, callback)
  local content, relative_path, filetype

  if opts.args and opts.args ~= "" then
    local file_path = vim.fn.expand(opts.args)
    if file_path:match("^https?://") then
      markdown.get_markdown(file_path, function(markdown_content)
        callback(markdown_content, file_path, "markdown")
      end)
      return
    end
    if vim.fn.filereadable(file_path) == 0 then
      error("File not found or not readable: " .. file_path)
    end
    content = table.concat(vim.fn.readfile(file_path), "\n")
    relative_path = vim.fn.fnamemodify(file_path, ":.")
    filetype = vim.filetype.match({ filename = file_path })
  else
    local current_buf = vim.api.nvim_get_current_buf()
    filetype = vim.api.nvim_get_option_value("filetype", { buf = current_buf })
    relative_path = vim.fn.expand("%:.")
    local start_line, end_line
    if opts.range == 2 then
      start_line = opts.line1 - 1
      end_line = opts.line2
    else
      start_line = 0
      end_line = -1
    end
    local lines = vim.api.nvim_buf_get_lines(current_buf, start_line, end_line, false)
    if #lines == 0 then
      error("No content to add. The buffer or selection is empty.")
    end
    content = table.concat(lines, "\n")
  end

  callback(content, relative_path, filetype)
end

vim.api.nvim_create_user_command("Add", function(opts)
  if not vim.g.llm_sidekick_last_ask_buffer or not vim.api.nvim_buf_is_valid(vim.g.llm_sidekick_last_ask_buffer) then
    vim.api.nvim_err_writeln("No valid Ask buffer found. Please run the Ask command first.")
    return
  end

  get_content(opts, function(content, relative_path, filetype)
    local language = get_filetype_config(filetype)
    local snippet = render_snippet(relative_path, content, language.code)
    -- Find the appropriate insertion point
    local ask_buf = vim.g.llm_sidekick_last_ask_buffer
    local ask_buf_line_count = vim.api.nvim_buf_line_count(ask_buf)
    local insert_point = ask_buf_line_count
    local last_user_line = 1

    for i = 1, ask_buf_line_count do
      local line = vim.api.nvim_buf_get_lines(ask_buf, i - 1, i, false)[1]
      if line:match("^USER:") then
        last_user_line = i
      end
      if line:match("^<editor_context>") then
        insert_point = i
        break
      end
    end

    -- If we didn't find a </editor_context> tag, create a new <editor_context> section
    if insert_point == ask_buf_line_count then
      snippet = "Here is what I'm working on:\n" .. render_editor_context(snippet)
      insert_point = last_user_line
    end

    local fragment_lines = vim.split(snippet, "\n")
    vim.api.nvim_buf_set_lines(ask_buf, insert_point, insert_point, false, fragment_lines)
    vim.api.nvim_buf_call(ask_buf, function()
      fold_editor_context(ask_buf)
    end)
  end)
end, {
  range = true,
  nargs = "?",
  complete = "file"
})

return M
