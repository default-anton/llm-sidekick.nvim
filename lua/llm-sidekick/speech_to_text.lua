local Job = require('plenary.job')

local FILE_PATH = "/tmp/llm-sidekick-recording.mp3"
local PROMPT =
"Hey, I've been looking at the project implementation details and thinking about our approach. You know, we might need to refactor some of the core modules to improve performance. What are your thoughts on using async patterns for the new features?"

local function record_voice(output_file)
  if vim.fn.executable("sox") == 0 then
    error("sox is not installed")
  end

  return Job:new({
    command = 'sox',
    args = {
      '-q',          -- quiet mode
      '-d',          -- default audio device
      '-c', '1',     -- mono channel
      '-t', 'mp3',   -- mp3 format
      '-C', '128.2', -- compression
      output_file,   -- output file
      'rate', '16k'  -- sample rate
    },
  })
end

local function transcribe(callback)
  return Job:new({
    command = "curl",
    args = {
      "https://api.groq.com/openai/v1/audio/transcriptions",
      "-H", "Authorization: bearer " .. (os.getenv("GROQ_API_KEY") or ""),
      "-H", "Content-Type: multipart/form-data",
      "-F", "file=@" .. FILE_PATH,
      "-F", "model=whisper-large-v3-turbo",
      "-F", "temperature=0.0",
      "-F", "response_format=text",
      "-F", "language=en",
      "-F", "prompt=" .. PROMPT,
    },
    on_exit = function(j, return_val)
      if return_val == 0 then
        local lines = vim.tbl_map(vim.trim, j:result())
        callback(lines)
      else
        vim.schedule(function()
          local result = table.concat(j:stderr_result(), "\n")
          vim.notify("Error (code " .. return_val .. "): " .. result, vim.log.levels.ERROR)
        end)
      end
    end,
  })
end

local function speech_to_text(callback)
  local job = record_voice(FILE_PATH)
  job:after_success(function(_, _, signal)
    if signal == 0 then
      transcribe(callback):start()
    end
  end)
  return job
end

return speech_to_text
