if vim.g.loaded_llm_sidekick == 1 then
  return
end

vim.g.loaded_llm_sidekick = 1
vim.g.llm_sidekick_last_ask_buffer = nil

local M = {}

local fs = require "llm-sidekick.fs"
local bedrock = require "llm-sidekick.bedrock"
local markdown = require "llm-sidekick.markdown"
local prompts = require "llm-sidekick.prompts"
local file_editor = require "llm-sidekick.file_editor"
local llm_sidekick = require "llm-sidekick"
local speech_to_text = require "llm-sidekick.speech_to_text"
local current_project_config = {}

local OPEN_MODES = { "tab", "vsplit", "split" }
local MODE_SHORTCUTS = {
  t = "tab",
  v = "vsplit",
  s = "split"
}
local MODEL_TYPES = { "smart", "fast", "reason" }

local function load_project_config()
  local project_config_path = vim.fn.getcwd() .. "/.llmsidekick.lua"
  if vim.fn.filereadable(project_config_path) == 1 then
    local ok, config = pcall(dofile, project_config_path)
    if not ok then
      error("Failed to load project configuration: " .. vim.inspect(config))
    end

    vim.validate({ config = { config, "table" } })
    vim.validate({
      guidelines = { config.guidelines, "string", true },
      technologies = { config.technologies, "string", true },
    })
    current_project_config = config
  end
end

load_project_config()

vim.api.nvim_create_augroup("LLMSidekickProjectConfig", { clear = true })
vim.api.nvim_create_autocmd("DirChanged", {
  group = "LLMSidekickProjectConfig",
  callback = load_project_config,
  desc = "Reload LLM Sidekick project configuration when changing directories",
})

local function set_last_ask_buffer()
  local current_buf = vim.api.nvim_get_current_buf()
  if vim.b[current_buf].is_llm_sidekick_ask_buffer then
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
    file_paths = {}
  }
  for _, arg in ipairs(args) do
    if arg == "smart" then
      parsed.model = settings.get_smart_model()
    elseif arg == "fast" then
      parsed.model = settings.get_fast_model()
    elseif arg == "reason" then
      parsed.model = settings.get_reasoning_model()
    elseif vim.tbl_contains(OPEN_MODES, arg) then
      parsed.open_mode = arg
    elseif MODE_SHORTCUTS[arg] ~= nil then
      parsed.open_mode = MODE_SHORTCUTS[arg]
    elseif arg:sub(1, 1) == "%" then
      local expanded_path = vim.fn.expand(arg)
      if vim.fn.filereadable(expanded_path) == 1 or vim.fn.isdirectory(expanded_path) == 1 then
        table.insert(parsed.file_paths, expanded_path)
      else
        error("Expanded path is not a readable file: " .. expanded_path)
      end
    elseif vim.fn.filereadable(arg) == 1 or vim.fn.isdirectory(arg) == 1 then
      table.insert(parsed.file_paths, arg)
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

-- Function to fold all editor context tags in a given buffer
local function fold_editor_context(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local contexts = {}
  local current_start = nil

  -- Find all editor context pairs
  for i, line in ipairs(lines) do
    if line:match("^<editor_context>") then
      current_start = i
    elseif line:match("^</editor_context>") and current_start then
      -- Only create fold if there's content between tags
      if i > current_start then
        table.insert(contexts, { start = current_start, ["end"] = i })
      end
      current_start = nil
    end
  end

  -- Create folds for all found contexts
  for _, context in ipairs(contexts) do
    vim.api.nvim_command(string.format("%d,%dfold", context.start, context["end"]))
  end
end

local function fold_stuff(buf)
  vim.wo.foldmethod = 'manual'
  vim.cmd([[normal! zE]])

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local user_line
  for i, line in ipairs(lines) do
    if line:match("^USER:") then
      user_line = i
      break
    end
  end

  if user_line and user_line > 1 then
    vim.cmd(string.format("1,%dfold", user_line - 1))
  end

  fold_editor_context(buf)
end

local function render_snippet(relative_path, content)
  return string.format([[
%s
```
%s
```
]], relative_path, content)
end

local function render_editor_context(snippets)
  return "<editor_context>\n" .. snippets .. "\n</editor_context>"
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

local function adapt_system_prompt_for(model, prompt)
  if vim.startswith(model, "gemini") then
    return prompt:gsub("Claude", "Gemini"):gsub("Anthropic", "Google DeepMind")
  end

  if vim.startswith(model, "o1") or vim.startswith(model, "gpt") then
    return prompt:gsub("Claude", "GPT"):gsub("Anthropic", "OpenAI")
  end

  return prompt
end

local function add_file_content_to_prompt(prompt, file_paths)
  if vim.tbl_isempty(file_paths) then
    return prompt
  end

  local snippets = {}

  local function add_file(file_path)
    if vim.fn.filereadable(file_path) == 0 then
      return
    end
    local content = fs.read_file(file_path)
    if not content then
      error(string.format("Failed to read file '%s'", file_path))
    end
    local relative_path = vim.fn.fnamemodify(file_path, ":.")
    table.insert(snippets, render_snippet(relative_path, content))
  end

  for _, file_path in ipairs(file_paths) do
    if vim.fn.isdirectory(file_path) == 1 then
      local function add_files_recursively(dir)
        local handle = vim.loop.fs_scandir(dir)
        if not handle then return end

        while true do
          local name, type = vim.loop.fs_scandir_next(handle)
          if not name then break end

          local full_path = vim.fn.fnameescape(dir .. '/' .. name)
          if type == 'file' then
            add_file(full_path)
          elseif type == 'directory' then
            add_files_recursively(dir .. '/' .. name)
          end
        end
      end
      add_files_recursively(file_path)
    else
      add_file(file_path)
    end
  end

  if not vim.tbl_isempty(snippets) then
    prompt = prompt .. "Here is what I'm working on:\n" .. render_editor_context(table.concat(snippets, "\n")) .. "\n"
  end
  return prompt
end

local ask_command = function(cmd_opts)
  return function(opts)
    local parsed_args = parse_ask_args(opts.fargs)
    local model = parsed_args.model
    local open_mode = parsed_args.open_mode
    local file_paths = parsed_args.file_paths
    local range_start = -1
    local range_end = -1

    if opts.range == 2 then
      range_start = opts.line1
      range_end = opts.line2
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

      local guidelines = vim.trim(current_project_config.guidelines or "")
      if guidelines == "" then
        guidelines = "No guidelines provided."
      end

      if cmd_opts.coding then
        local system_prompt = prompts.system_prompt
        if vim.startswith(model, "o1") then
          system_prompt = prompts.openai_coding
        end
        local args = {
          os.date("%B %d, %Y"),
          guidelines,
          vim.trim(current_project_config.technologies or ""),
        }
        if not vim.startswith(model, "o1") then
          table.insert(args, cmd_opts.include_modifications and vim.trim(prompts.modifications) or "")
        end

        prompt = prompt ..
            "SYSTEM: " .. adapt_system_prompt_for(model, string.format(vim.trim(system_prompt), unpack(args)))
      elseif not vim.startswith(model, "o1") then
        local args = {
          os.date("%B %d, %Y"),
          vim.trim(guidelines),
          cmd_opts.include_modifications and vim.trim(prompts.modifications) or "",
        }
        prompt = prompt ..
            "SYSTEM: " ..
            adapt_system_prompt_for(model, string.format(vim.trim(prompts.generic_system_prompt), unpack(args)))
      end

      prompt = prompt .. "\nUSER: "
      if opts.range == 2 then
        local relative_path = vim.fn.expand("%")
        local context = table.concat(vim.api.nvim_buf_get_lines(0, range_start - 1, range_end, false), "\n")
        prompt = prompt .. "Here is what I'm working on:\n"
        local snippet = render_snippet(relative_path, context)
        prompt = prompt .. render_editor_context(snippet) .. "\n"
      end

      prompt = add_file_content_to_prompt(prompt, file_paths)
    end

    local buf = vim.api.nvim_create_buf(true, false)
    vim.b[buf].is_llm_sidekick_ask_buffer = true
    vim.b[buf].llm_sidekick_include_modifications = cmd_opts.include_modifications
    vim.g.llm_sidekick_last_ask_buffer = buf
    vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
    if vim.b[buf].llm_sidekick_include_modifications then
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
      fold_stuff(buf)
    end)
    -- Set cursor to the end of the buffer
    vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(buf), 0 })
    -- Enter insert mode at the end of the line
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('A', true, false, true), 'n', false)

    if vim.startswith(model, "anthropic.") then
      vim.schedule(function()
        bedrock.start_web_server()
      end)
    end
  end
end

vim.api.nvim_create_user_command("Chat", ask_command({ coding = false, include_modifications = false }), {
  range = true,
  nargs = "*",
  complete = function(ArgLead, CmdLine, CursorPos)
    local args = vim.split(CmdLine, "%s+")
    local file_completions = vim.fn.getcompletion(ArgLead, 'file')
    local options = {}
    if vim.trim(ArgLead) ~= "" and #file_completions > 0 then
      options = file_completions
    end
    vim.list_extend(options, MODEL_TYPES)
    vim.list_extend(options, OPEN_MODES)
    return vim.tbl_filter(function(item)
      return vim.startswith(item:lower(), ArgLead:lower()) and not vim.tbl_contains(args, item)
    end, options)
  end,
})

vim.api.nvim_create_user_command("Ask", ask_command({ coding = true, include_modifications = false }), {
  range = true,
  nargs = "*",
  complete = function(ArgLead, CmdLine, CursorPos)
    local args = vim.split(CmdLine, "%s+")
    local file_completions = vim.fn.getcompletion(ArgLead, 'file')
    local options = {}
    if vim.trim(ArgLead) ~= "" and #file_completions > 0 then
      options = file_completions
    end
    vim.list_extend(options, MODEL_TYPES)
    vim.list_extend(options, OPEN_MODES)
    return vim.tbl_filter(function(item)
      return vim.startswith(item:lower(), ArgLead:lower()) and not vim.tbl_contains(args, item)
    end, options)
  end,
})

vim.api.nvim_create_user_command("Code", ask_command({ coding = true, include_modifications = true }), {
  range = true,
  nargs = "*",
  complete = function(ArgLead, CmdLine, CursorPos)
    local args = vim.split(CmdLine, "%s+")
    local file_completions = vim.fn.getcompletion(ArgLead, 'file')
    local options = {}
    if vim.trim(ArgLead) ~= "" and #file_completions > 0 then
      options = file_completions
    end
    vim.list_extend(options, MODEL_TYPES)
    vim.list_extend(options, OPEN_MODES)
    return vim.tbl_filter(function(item)
      return vim.startswith(item:lower(), ArgLead:lower()) and not vim.tbl_contains(args, item)
    end, options)
  end,
})

local function get_content(opts, callback)
  local function add_file(file_path)
    if vim.fn.filereadable(file_path) == 0 then
      return
    end

    local content = fs.read_file(file_path)
    if not content then
      error(string.format("Failed to read file '%s'", file_path))
    end
    local relative_path = vim.fn.fnamemodify(file_path, ":.")
    callback(content, relative_path)
  end

  if opts.args and opts.args ~= "" then
    local file_path = vim.fn.expand(opts.args)
    if file_path:match("^https?://") then
      markdown.get_markdown(file_path, function(markdown_content)
        callback(markdown_content, file_path)
      end)
      return
    end
    if vim.fn.isdirectory(file_path) == 1 then
      local function add_files_recursively(dir)
        local handle = vim.loop.fs_scandir(dir)
        if not handle then return end

        while true do
          local name, type = vim.loop.fs_scandir_next(handle)
          if not name then break end

          local full_path = vim.fn.fnameescape(dir .. '/' .. name)
          if type == 'file' then
            add_file(full_path)
          elseif type == 'directory' then
            add_files_recursively(dir .. '/' .. name)
          end
        end
      end

      add_files_recursively(file_path)
    else
      add_file(file_path)
    end
  else
    local current_buf = vim.api.nvim_get_current_buf()
    local relative_path = vim.fn.expand("%:.")
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
    local content = table.concat(lines, "\n")

    callback(content, relative_path)
  end
end

-- TODO: Implement this
local function replace_system_prompt(ask_buf, opts)
  local model = ""
  local lines = vim.api.nvim_buf_get_lines(ask_buf, 0, -1, false)
  for _, line in ipairs(lines) do
    local match = line:match("^MODEL:(.+)$")
    if match then
      model = vim.trim(match)
      break
    end
  end

  if model == "" then
    error("No model specified in the buffer")
  end

  -- Find SYSTEM prompt
  local system_start = nil
  for i, line in ipairs(lines) do
    if vim.startswith(line, "SYSTEM:") then
      system_start = i
      break
    end
  end
  if not system_start then
    return
  end

  -- Find USER prompt
  local user_start = nil
  for i, line in ipairs(lines) do
    if vim.startswith(line, "USER:") then
      user_start = i
      break
    end
  end
end

local function create_stt_window()
  local width = 50
  local height = 3
  local bufnr = vim.api.nvim_create_buf(false, true)
  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = (vim.o.lines - height) / 2,
    col = (vim.o.columns - width) / 2,
    style = "minimal",
    border = "rounded"
  }
  local winnr = vim.api.nvim_open_win(bufnr, false, win_opts)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "Recording... Press Enter to stop or q to cancel",
    "",
    "🎤 Recording in progress"
  })
  return bufnr, winnr
end

vim.api.nvim_create_user_command("Stt", function()
  local mode = vim.api.nvim_get_mode().mode
  local orig_winnr = vim.api.nvim_get_current_win()
  local orig_bufnr = vim.api.nvim_get_current_buf()
  local orig_pos = vim.api.nvim_win_get_cursor(orig_winnr)

  local bufnr, winnr = create_stt_window()
  vim.api.nvim_set_current_win(winnr)

  local job
  local cancel = function()
    if vim.api.nvim_win_is_valid(winnr) then
      vim.api.nvim_win_close(winnr, true)
    end
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
    if job and not job.is_shutdown then
      vim.loop.kill(job.pid, vim.loop.constants.SIGKILL)
    end
  end

  -- Create autocmd to handle window close
  vim.api.nvim_create_autocmd("WinClosed", {
    buffer = bufnr,
    callback = function()
      cancel()
    end,
    once = true,
  })

  -- Create buffer-local keymap for the floating window
  local opts = { noremap = true, silent = true, buffer = bufnr }
  vim.keymap.set({ "n", "i" }, "q", function()
    cancel()
  end, opts)

  vim.keymap.set({ "n", "i" }, "<CR>", function()
    if job and not job.is_shutdown then
      vim.loop.kill(job.pid, vim.loop.constants.SIGINT)
    end
  end, opts)

  -- Start recording
  job = speech_to_text(function(lines)
    if vim.tbl_isempty(lines) then
      return
    end

    vim.schedule(function()
      cancel()

      if mode == "i" then
        vim.api.nvim_buf_set_text(orig_bufnr, orig_pos[1] - 1, orig_pos[2], orig_pos[1] - 1, orig_pos[2], lines)
        -- Calculate new cursor position: same line, column position + length of inserted text
        local inserted_text = table.concat(lines)
        vim.api.nvim_win_set_cursor(orig_winnr, { orig_pos[1], orig_pos[2] + #inserted_text })
      else
        local line = vim.api.nvim_buf_get_lines(orig_bufnr, orig_pos[1] - 1, orig_pos[1], true)[1]
        local new_line = line:sub(1, orig_pos[2]) .. table.concat(lines, "\n") .. line:sub(orig_pos[2] + 1)
        vim.api.nvim_buf_set_lines(orig_bufnr, orig_pos[1] - 1, orig_pos[1], true, { new_line })
        -- Move cursor to the end of inserted text
        local inserted_text = table.concat(lines)
        vim.api.nvim_win_set_cursor(orig_winnr, { orig_pos[1], orig_pos[2] + #inserted_text })
      end
    end)
  end)
  job:start()
end, {})

vim.api.nvim_create_user_command("Add", function(opts)
  local ask_buf = vim.g.llm_sidekick_last_ask_buffer
  if not ask_buf or not vim.api.nvim_buf_is_valid(ask_buf) or not vim.b[ask_buf] or not vim.b[ask_buf].is_llm_sidekick_ask_buffer then
    vim.api.nvim_err_writeln("No valid Ask buffer found. Please run the Ask command first.")
    return
  end

  get_content(opts, function(content, relative_path)
    local snippet = render_snippet(relative_path, content)
    -- Find the appropriate insertion point
    local ask_buf_line_count = vim.api.nvim_buf_line_count(ask_buf)
    local insert_point = ask_buf_line_count
    local last_user_line = ask_buf_line_count

    -- Find the last USER: line
    for i = ask_buf_line_count, 1, -1 do
      local line = vim.api.nvim_buf_get_lines(ask_buf, i - 1, i, false)[1]
      if line:match("^USER:") then
        last_user_line = i
        break
      end
    end

    -- Find the editor_context after the last user line
    for i = last_user_line, ask_buf_line_count do
      local line = vim.api.nvim_buf_get_lines(ask_buf, i - 1, i, false)[1]
      if line:match("^</editor_context>") then
        insert_point = i - 1
        break
      end
    end

    local insert_start, insert_end = insert_point, insert_point
    -- If we didn't find a </editor_context> tag, create a new <editor_context> section
    if insert_start == ask_buf_line_count then
      snippet = "USER: Here is what I'm working on:\n" .. render_editor_context(snippet)
      insert_start = last_user_line - 1
      insert_end = last_user_line
      local line = vim.api.nvim_buf_get_lines(ask_buf, last_user_line - 1, last_user_line, false)[1]
      local _, end_idx = string.find(line, "USER:")
      snippet = snippet .. "\n" .. vim.trim(line:sub(end_idx + 1))
    end

    local fragment_lines = vim.split(snippet, "\n")
    vim.api.nvim_buf_set_lines(ask_buf, insert_start, insert_end, false, fragment_lines)
    vim.api.nvim_buf_call(ask_buf, function()
      fold_stuff(ask_buf)
    end)
  end)
end, {
  range = true,
  nargs = "?",
  complete = "file"
})

return M
