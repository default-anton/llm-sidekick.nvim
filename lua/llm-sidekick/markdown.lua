local Job = require("plenary.job")

local function get_markdown(url, callback)
  callback = vim.schedule_wrap(callback)

  local curl = require("llm-sidekick.executables").get_curl_executable()
  local output = {}

  Job:new({
    command = curl,
    args = {
      '-s',
      '--no-buffer',
      '-L', -- follow redirects
      'https://r.jina.ai/' .. url,
    },
    on_stdout = function(_, line)
      table.insert(output, line)
    end,
    on_stderr = function(_, text)
      vim.schedule(function()
        vim.api.nvim_err_writeln("Error: " .. text)
      end)
    end,
    on_exit = function(_, return_val)
      if return_val == 0 then
        callback(table.concat(output, "\n"))
        return
      end

      vim.schedule(function()
        vim.api.nvim_err_writeln("Error: Failed to fetch markdown with exit code " .. return_val)
      end)
    end,
  }):start()
end

return {
  get_markdown = get_markdown
}
