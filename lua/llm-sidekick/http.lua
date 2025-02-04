local Job = require("plenary.job")

local M = {}

function M.get(url)
  local curl = require("llm-sidekick.executables").get_curl_executable()
  local output = {}
  local error_output = nil
  local done = false

  local job = Job:new({
    command = curl,
    args = {
      '-s',
      '--no-buffer',
      '-L', -- follow redirects
      url,
    },
    on_stdout = function(_, line)
      table.insert(output, line)
    end,
    on_stderr = function(_, text)
      if text and text ~= "" then
        error_output = text
      end
    end,
    on_exit = function(_, return_val)
      if return_val ~= 0 then
        error_output = error_output or ("Failed with exit code " .. return_val)
      end
      done = true
    end,
  })

  job:start()

  -- Wait for job to complete with a timeout of 10 seconds
  if not vim.wait(10000, function() return done end, 50) then
    error("Failed to fetch URL: " .. url .. "\n" .. "Timeout")
  end

  if error_output then
    error("Failed to fetch URL: " .. url .. "\n" .. error_output)
  end

  return table.concat(output, "\n")
end

return M
