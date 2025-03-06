local M = {}

local spinner_styles = {
  dots = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
  line = { "|", "/", "-", "\\" },
}

local default_style = "line"

-- Active spinners by buffer
local active_spinners = {}

local function get_spinner_frames(style)
  return spinner_styles[style] or spinner_styles[default_style]
end

function M.start(bufnr, style, position)
  if active_spinners[bufnr] then
    M.stop(bufnr)
  end

  -- Default position is at the end of the buffer
  position = position or "end"
  style = style or default_style

  local frames = get_spinner_frames(style)
  local index = 1
  local extmark_id = nil
  local ns_id = vim.g.llm_sidekick_ns

  local timer = vim.loop.new_timer()

  local function update_spinner()
    local frame = frames[index]
    index = (index % #frames) + 1

    -- Update the spinner text in the buffer
    vim.schedule(function()
      if not vim.api.nvim_buf_is_loaded(bufnr) then
        M.stop(bufnr)
        return
      end

      local line_count = vim.api.nvim_buf_line_count(bufnr)
      local last_line = vim.api.nvim_buf_get_lines(bufnr, line_count - 1, line_count, false)[1]

      if extmark_id then
        vim.api.nvim_buf_del_extmark(bufnr, ns_id, extmark_id)
      end

      if position == "end" then
        extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_count - 1, #last_line, {
          virt_text = { { " " .. frame .. " ", "Comment" } },
          virt_text_pos = "eol",
        })
      end
    end)
  end

  -- Start the timer to update the spinner every 100ms
  timer:start(0, 100, update_spinner)

  active_spinners[bufnr] = {
    timer = timer,
    extmark_id = extmark_id,
    style = style,
  }

  update_spinner()

  return true
end

function M.stop(bufnr)
  local spinner = active_spinners[bufnr]
  if not spinner then
    return false
  end

  if spinner.timer then
    spinner.timer:stop()
    spinner.timer:close()
  end

  if spinner.extmark_id and vim.api.nvim_buf_is_loaded(bufnr) then
    vim.api.nvim_buf_del_extmark(bufnr, vim.g.llm_sidekick_ns, spinner.extmark_id)
  end

  active_spinners[bufnr] = nil

  return true
end

function M.stop_all()
  for bufnr, _ in pairs(active_spinners) do
    M.stop(bufnr)
  end
end

return M
