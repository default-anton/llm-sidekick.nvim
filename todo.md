Can't apply the modification block below.

@plugin/llm-sidekick.lua
<search>
local function ask_command(cmd_opts)
  return function(opts)
    local parsed_args = parse_ask_args(opts.fargs)
    local model = parsed_args.model
    local open_mode = parsed_args.open_mode
    local file_paths = parsed_args.file_paths
    local range_start = -1
    local range_end = -1
</search>
<replace>
local function ask_command(cmd_opts)
  return function(opts)
    local parsed_args = parse_ask_args(opts.fargs)
    local model = parsed_args.model
    local open_mode = parsed_args.open_mode
    local file_paths = parsed_args.file_paths
    local range_start = -1
    local range_end = -1
    local auto_apply = cmd_opts.auto_apply or false
</replace>


<search>
      local ok, decoded = pcall(vim.json.decode, line)
      if ok and decoded and decoded.candidates and decoded.candidates[1] and
          decoded.candidates[1].content and decoded.candidates[1].content.parts and
          decoded.candidates[1].content.parts[1].text then
        local content = decoded.candidates[1].content.parts[1].text
        callback(message_types.DATA, content)
      end
</search>
<replace>
      local ok, decoded = pcall(vim.json.decode, line)
      if ok and decoded and decoded.candidates and decoded.candidates[1] and
          decoded.candidates[1].content and decoded.candidates[1].content.parts then
        for _, part in ipairs(decoded.candidates[1].content.parts) do
          if part.text then
            callback(message_types.DATA, part.text)
          end
        end
      end
</replace>
