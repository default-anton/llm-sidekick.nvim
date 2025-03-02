if vim.g.loaded_llm_sidekick == 1 then
  return
end

local utils = require "llm-sidekick.utils"

vim.g.loaded_llm_sidekick = 1
vim.g.llm_sidekick_ns = vim.api.nvim_create_namespace('llm-sidekick')
vim.g.llm_sidekick_last_chat_buffer = nil
vim.g.llm_sidekick_tmp_dir = utils.get_temp_dir()
vim.g.llm_sidekick_log_path = vim.g.llm_sidekick_tmp_dir .. "/llm_sidekick.log"

if os.getenv("LLM_SIDEKICK_DEBUG") == "true" then
  vim.print("Log file: " .. vim.g.llm_sidekick_log_path)
end

local litellm = require "llm-sidekick.litellm"
-- Start the web server when the plugin loads
vim.schedule(function()
  litellm.start_web_server(1993)
end)

-- Define signs for LLM Sidekick
vim.fn.sign_define("llm_sidekick_red", {
  text = "▎",
  texthl = "DiffDelete",
  linehl = "DiffDelete",
  numhl = "DiffDelete"
})

vim.fn.sign_define("llm_sidekick_green", {
  text = "▎",
  texthl = "DiffAdd",
  linehl = "DiffAdd",
  numhl = "DiffAdd"
})

local project_config_path = vim.fn.getcwd() .. "/.llmsidekick.lua"

local settings = require "llm-sidekick.settings"
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

local function load_project_config()
  project_config_path = vim.fn.getcwd() .. "/.llmsidekick.lua"
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
  else
    current_project_config = {}
  end
end

load_project_config()

vim.api.nvim_create_augroup("LLMSidekickProjectConfig", { clear = true })
vim.api.nvim_create_autocmd("DirChanged", {
  group = "LLMSidekickProjectConfig",
  callback = load_project_config,
  desc = "Reload LLM Sidekick project configuration when changing directories",
})

local function set_last_chat_buffer()
  local current_buf = vim.api.nvim_get_current_buf()
  if vim.b[current_buf].is_llm_sidekick_chat then
    vim.g.llm_sidekick_last_chat_buffer = current_buf
  end
end

vim.api.nvim_create_augroup("LLMSidekickLastAskBuffer", { clear = true })
vim.api.nvim_create_autocmd({ "BufEnter", "FocusGained" }, {
  group = "LLMSidekickLastAskBuffer",
  callback = set_last_chat_buffer,
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
  local parsed = {
    model = settings.get_model(),
    open_mode = "current",
    rest = {}
  }
  for _, arg in ipairs(args) do
    if settings.has_model_for(arg) then
      parsed.model = settings.get_model(arg)
    elseif vim.tbl_contains(OPEN_MODES, arg) then
      parsed.open_mode = arg
    elseif MODE_SHORTCUTS[arg] ~= nil then
      parsed.open_mode = MODE_SHORTCUTS[arg]
    else
      table.insert(parsed.rest, arg)
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

local function render_editor_context(references)
  return "<editor_context>\n" .. references .. "\n</editor_context>"
end

local function is_llm_sidekick_chat_file(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 3, false)
  if #lines < 3 then
    return false
  end

  local required_keywords = {
    ["MODEL:"] = false,
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

local ask_command = function()
  return function(opts)
    -- Always load project config
    load_project_config()

    local parsed_args = parse_ask_args(opts.fargs)
    local model = parsed_args.model
    local open_mode = parsed_args.open_mode
    local model_settings = settings.get_model_settings(model)
    local prompt_settings = {
      model = model,
      max_tokens = model_settings.max_tokens,
    }

    if model_settings.temperature then
      prompt_settings.temperature = model_settings.temperature
    end

    local prompt = ""
    if is_llm_sidekick_chat_file(0) and not vim.b.is_llm_sidekick_chat then
      prompt = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    else
      for key, value in pairs(prompt_settings) do
        prompt = prompt .. key:upper() .. ": " .. value .. "\n"
      end

      local system_prompt = prompts.system_prompt({
        os_name = utils.get_os_name(),
        shell = vim.o.shell or "bash",
        cwd = vim.fn.getcwd(),
        just_chatting = model_settings.just_chatting
      })

      if vim.fn.filereadable("plan.md") == 1 then
        system_prompt = system_prompt .. "\n\n<llm_sidekick_file>plan.md</llm_sidekick_file>"
        system_prompt = system_prompt .. [[
]]
      end

      local guidelines = vim.trim(current_project_config.guidelines or "")
      local global_guidelines = settings.get_global_guidelines()
      if global_guidelines and global_guidelines ~= "" then
        guidelines = vim.trim(global_guidelines .. "\n" .. guidelines)
      end

      local technologies = vim.trim(current_project_config.technologies or "")

      if guidelines ~= "" or technologies ~= "" then
        system_prompt = system_prompt .. [[

---

User's Custom Instructions:
The following additional instructions are provided by the user, and should be followed to the best of your ability.]]
      end

      if guidelines ~= "" then
        system_prompt = system_prompt .. "\n\n" .. "Guidelines:\n" .. guidelines
      end

      if technologies ~= "" then
        system_prompt = system_prompt .. "\n\n" .. "Technologies:\n" .. technologies
      end

      system_prompt = vim.trim(system_prompt)
      prompt = prompt .. "SYSTEM: " .. system_prompt
      prompt = prompt .. "\nUSER: "
    end

    local buf = vim.api.nvim_create_buf(true, true)
    vim.bo[buf].buftype = "nofile"
    vim.b[buf].is_llm_sidekick_chat = true
    vim.g.llm_sidekick_last_chat_buffer = buf
    vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })

    local lines = vim.split(prompt, "[\r]?\n")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    if opts.range == 2 then
      vim.cmd(string.format("%d,%dAdd", opts.line1, opts.line2))
    elseif #parsed_args.rest > 0 then
      vim.cmd("Add " .. table.concat(parsed_args.rest, " "))
    end

    file_editor.create_apply_modifications_command(buf)
    open_buffer_in_mode(buf, open_mode)
    vim.api.nvim_buf_call(buf, function()
      fold_stuff(buf)
    end)
    set_llm_sidekick_options()

    vim.keymap.set(
      "n",
      "<CR>",
      function()
        vim.cmd('stopinsert!')
        vim.b[buf].llm_sidekick_max_turns_without_user_input = nil
        llm_sidekick.ask(buf)
      end,
      { buffer = buf, nowait = true, noremap = true, silent = true }
    )

    vim.keymap.set(
      { "n", "i" },
      "<C-c>",
      function()
        utils.stop(buf)
      end,
      { buffer = buf, nowait = true, noremap = true, silent = true }
    )

    -- Set cursor to the end of the buffer
    vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(buf), 0 })

    -- Move cursor to the end of the line
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('$', true, false, true), 'n', false)

    vim.schedule(function()
      litellm.start_web_server(1993)
    end)
  end
end

vim.api.nvim_create_user_command(
  "Chat",
  ask_command(),
  { range = true, nargs = "*", complete = utils.complete_command }
)

local function is_image_file(file_path)
  local extension = vim.fn.fnamemodify(file_path, ":e")
  return vim.tbl_contains({ "png", "jpg", "jpeg", "gif" }, extension:lower())
end

local function get_content(opts, callback)
  local function add_file(file_path)
    if vim.fn.filereadable(file_path) == 0 then
      return
    end

    local relative_path = vim.fn.fnamemodify(file_path, ":.")

    if is_image_file(file_path) then
      callback({ type = "image", path = relative_path })
    else
      callback({ type = "file", path = relative_path })
    end
  end

  if opts.args and opts.args ~= "" then
    local file_path = vim.fn.expand(vim.trim(opts.args))
    -- Convert GitHub blob URLs to raw URLs
    file_path = file_path:gsub("https://github%.com/([^/]+)/([^/]+)/blob/([^/]+)/(.*)",
      "https://raw.githubusercontent.com/%1/%2/%3/%4")

    if file_path:match("^https?://") then
      local filename = utils.url_to_filename(file_path)
      local content_path = vim.g.llm_sidekick_tmp_dir .. "/" .. filename

      -- Handle GitHub URLs
      if file_path:match("^https://raw.githubusercontent.com") then
        local content = require('llm-sidekick.http').get(file_path)
        local ok, err = pcall(vim.fn.writefile, vim.split(content, "\n"), content_path)
        if not ok then
          vim.notify(string.format("Failed to fetch content from '%s': %s", file_path, vim.inspect(err)),
            vim.log.levels.ERROR)
          return
        end

        callback({ type = "url", path = file_path }, file_path)
        return
      end

      -- Use get_markdown for non-GitHub URLs
      require('llm-sidekick.markdown').get_markdown(file_path, function(content)
        if not content then
          vim.notify(string.format("Failed to fetch content from '%s'", file_path), vim.log.levels.ERROR)
          return
        end

        local ok, err = pcall(vim.fn.writefile, vim.split(content, "\n"), content_path)
        if not ok then
          vim.notify(string.format("Failed to fetch content from '%s': %s", file_path, vim.inspect(err)),
            vim.log.levels.ERROR)
          return
        end

        callback({ type = "url", path = file_path })
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

    if start_line == 0 and end_line == -1 then
      add_file(relative_path)
    else
      callback({ type = "snippet", path = relative_path, content = table.concat(lines, "\n") })
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

-- Function to paste image from clipboard
local function paste_image()
  -- Get the current buffer
  local bufnr = vim.api.nvim_get_current_buf()
  if not vim.b[bufnr].is_llm_sidekick_chat then
    vim.notify("Can only paste images in LLM Sidekick chat buffers", vim.log.levels.ERROR)
    return
  end

  local temp_dir = vim.g.llm_sidekick_tmp_dir
  local timestamp = os.time()
  local image_path = string.format("%s/image_%d.png", temp_dir, timestamp)

  -- Try to paste image from clipboard
  vim.fn.system({ "pngpaste", image_path })
  if vim.v.shell_error ~= 0 then
    vim.notify("No image found in clipboard", vim.log.levels.WARN)
    return
  end

  -- Get cursor position
  local pos = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_get_current_line()
  local before = line:sub(1, pos[2])
  local after = line:sub(pos[2] + 1)

  -- Insert image tag at cursor position
  local image_tag = string.format("<llm_sidekick_image>%s</llm_sidekick_image>", image_path)
  local new_line = before .. image_tag .. after
  vim.api.nvim_set_current_line(new_line)

  -- Move cursor after the inserted tag
  vim.api.nvim_win_set_cursor(0, { pos[1], pos[2] + #image_tag })
end

vim.api.nvim_create_user_command("Paste", paste_image, {})

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
    if vim.api.nvim_buf_is_loaded(bufnr) then
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
  local ask_buf = vim.g.llm_sidekick_last_chat_buffer
  if not ask_buf or not vim.api.nvim_buf_is_loaded(ask_buf) or not vim.b[ask_buf] or not vim.b[ask_buf].is_llm_sidekick_chat then
    vim.api.nvim_err_writeln("No valid Ask buffer found. Please run the Ask command first.")
    return
  end

  local function insert_content(content_data)
    local snippet
    if content_data.type == "image" then
      snippet = string.format("<llm_sidekick_image>%s</llm_sidekick_image>", content_data.path)
    elseif content_data.type == "url" then
      snippet = string.format("<llm_sidekick_url>%s</llm_sidekick_url>", content_data.path)
    elseif content_data.type == "file" then
      snippet = string.format("<llm_sidekick_file>%s</llm_sidekick_file>", content_data.path)
    elseif content_data.type == "snippet" then
      snippet = string.format("````%s\n%s\n````", content_data.path, content_data.content)
    end
    -- Find the appropriate insertion point
    local ask_buf_line_count = vim.api.nvim_buf_line_count(ask_buf)
    local editor_context_end_lnum
    local last_user_line

    -- Find the last USER: line
    for i = ask_buf_line_count, 1, -1 do
      local line = vim.api.nvim_buf_get_lines(ask_buf, i - 1, i, false)[1]
      if line:match("^USER:") then
        last_user_line = i
        break
      end
    end

    if not last_user_line then
      error("No USER: line found in the buffer")
    end

    -- Find the editor_context after the last user line
    for i = last_user_line, ask_buf_line_count do
      local line = vim.api.nvim_buf_get_lines(ask_buf, i - 1, i, false)[1]
      if line:match("^</editor_context>") then
        editor_context_end_lnum = i - 1
        break
      end
    end

    if editor_context_end_lnum then
      vim.api.nvim_buf_set_lines(
        ask_buf,
        editor_context_end_lnum,
        editor_context_end_lnum,
        false,
        vim.split(snippet, "\n")
      )
    else
      local content_of_user_line = vim.api.nvim_buf_get_lines(ask_buf, last_user_line - 1, last_user_line, false)[1]
      content_of_user_line = content_of_user_line:gsub("^USER:%s*", "")
      local editor_context = vim.split(render_editor_context(snippet), "\n")
      local lines = { "USER: Here is what I'm working on:", "" }
      vim.list_extend(lines, editor_context)
      vim.list_extend(lines, { "", content_of_user_line })

      vim.api.nvim_buf_set_lines(
        ask_buf,
        last_user_line - 1,
        last_user_line,
        false,
        lines
      )
    end
  end

  if not opts.fargs or vim.tbl_isempty(opts.fargs) then
    get_content(opts, insert_content)
  else
    for _, arg in ipairs(opts.fargs) do
      local current_opts = vim.deepcopy(opts)
      current_opts.args = arg
      get_content(current_opts, insert_content)
    end
  end

  vim.api.nvim_buf_call(ask_buf, function()
    fold_stuff(ask_buf)
  end)
end, {
  range = true,
  nargs = "*",
  complete = "file"
})

-- LLM Sidekick server management commands
vim.api.nvim_create_user_command("LlmSidekick", function(opts)
  local action = opts.args
  local port = 1993

  if action == "start" then
    if litellm.is_server_ready(port) then
      vim.notify("LLM Sidekick server is already running", vim.log.levels.INFO)
      return
    end
    litellm.start_web_server(port)
    if vim.wait(10000, function() return litellm.is_server_ready(port) end) then
      vim.notify("LLM Sidekick server started successfully", vim.log.levels.INFO)
    else
      vim.notify("Failed to start LLM Sidekick server", vim.log.levels.ERROR)
    end
  elseif action == "stop" then
    litellm.stop_web_server(port)
    if vim.wait(10000, function() return not litellm.is_server_ready(port) end) then
      vim.notify("LLM Sidekick server stopped", vim.log.levels.INFO)
    else
      vim.notify("Failed to stop LLM Sidekick server", vim.log.levels.ERROR)
    end
  elseif action == "restart" then
    litellm.stop_web_server(port)
    if not vim.wait(10000, function() return not litellm.is_server_ready(port) end) then
      vim.notify("Failed to stop LLM Sidekick server", vim.log.levels.ERROR)
      return
    end
    litellm.start_web_server(port)
    if vim.wait(10000, function() return litellm.is_server_ready(port) end) then
      vim.notify("LLM Sidekick server restarted successfully", vim.log.levels.INFO)
    else
      vim.notify("Failed to restart LLM Sidekick server", vim.log.levels.ERROR)
    end
  else
    vim.notify("Invalid action. Use 'start', 'stop', or 'restart'", vim.log.levels.ERROR)
  end
end, {
  nargs = 1,
  complete = function(ArgLead, CmdLine, CursorPos)
    local actions = { "start", "stop", "restart" }
    return vim.tbl_filter(function(action)
      return vim.startswith(action, ArgLead)
    end, actions)
  end,
  desc = "Manage LLM Sidekick server (start|stop|restart)"
})
