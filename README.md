# llm-sidekick.nvim

AI-powered companion for Neovim. Fast, hackable, and stays out of your way.

## Table of Contents

- [Features](#features)
- [Built-in Keybindings](#built-in-keybindings)
- [Requirements](#requirements)
  - [Core Requirements](#core-requirements)
  - [API Requirements](#api-requirements)
  - [Speech-to-Text Requirements (Optional)](#speech-to-text-requirements-optional)
- [Installation](#installation)
- [Supported Models](#supported-models)
  - [Anthropic Claude Models](#anthropic-claude-models)
  - [Google Gemini Models](#google-gemini-models)
  - [OpenAI Models](#openai-models)
  - [DeepSeek AI Models](#deepseek-ai-models)
- [Usage](#usage)
  - [Plan Mode](#plan-mode)
  - [Commands](#commands)
    - [Core Commands](#core-commands)
  - [Keybindings](#keybindings)
- [Telescope Integration](#telescope-integration)
- [Project Configuration](#project-configuration)
- [License](#license)

## Features

llm-sidekick.nvim turns your editor into a powerful code companion:

- `:Chat` - Write, refactor, modify multiple files, have technical discussions about code, debugging, and architecture, and have open-ended discussions for brainstorming and creative tasks
- `:Accept` - Accept tool under the cursor
- `:AcceptAll` - Accept all tools in the last assistant message
- `:Add` - Add files, code, or URLs (any web content) to your conversation
- `:Commit` - Generate commit messages for staged changes
- `:Stt` - Use speech-to-text input instead of typing

## Built-in Keybindings

- `<C-c>` (Ctrl-C) - Cancel/stop the current model generation. This is a built-in keybinding that cannot be overridden.
- `<leader>aa` - Accept the suggestion under the cursor. This is a built-in keybinding that provides quick access to the `:Accept` command.
- `<leader>A` - Accept all suggestions in the last assistant message. This is a built-in keybinding that provides quick access to the `:AcceptAll` command.

The plugin is designed to be fast, stay out of your way, and integrate naturally with your Neovim workflow. It supports multiple AI models and lets you choose between quick responses or deep reasoning based on your needs.

## Requirements

### Core Requirements
- Neovim >= 0.10.0
- plenary.nvim
- uv (Python package manager)
- curl (for API requests)
- ddgr (for DuckDuckGo search tool)

#### Installing uv
Follow the [installation instructions](https://docs.astral.sh/uv/getting-started/installation/) for your platform.

#### Installing ddgr
- Using uv (recommended): `uv tool install ddgr`

#### Installing curl
- Ubuntu/Debian: `sudo apt-get install curl`
- macOS: `brew install curl`
- Arch Linux: `sudo pacman -S curl`

### API Requirements
You only need to set up API keys for the providers whose models you intend to use:

#### AWS Bedrock Models
AWS Bedrock requires several environment variables for authentication and configuration:

**Required Authentication (set one from each pair):**
- `LLM_SIDEKICK_AWS_ACCESS_KEY_ID` or `AWS_ACCESS_KEY_ID`
  - Your AWS access key for authentication
- `LLM_SIDEKICK_AWS_SECRET_ACCESS_KEY` or `AWS_SECRET_ACCESS_KEY`
  - Your AWS secret key for authentication

**Optional Configuration:**
- `LLM_SIDEKICK_AWS_REGION` or `AWS_REGION` or `AWS_DEFAULT_REGION`
  - AWS region for Bedrock API (defaults to 'us-east-1')
- `LLM_SIDEKICK_ROLE_ARN` or `AWS_ROLE_ARN`
  - ARN of an IAM role to assume for AWS operations
- `LLM_SIDEKICK_ROLE_SESSION_NAME` or `AWS_ROLE_SESSION_NAME`
  - Session name when assuming an IAM role

#### Anthropic (Claude models)
Set one of these environment variables:
- `LLM_SIDEKICK_ANTHROPIC_API_KEY`
- `ANTHROPIC_API_KEY`

#### OpenAI (GPT models)
Set one of these environment variables:
- `LLM_SIDEKICK_OPENAI_API_KEY`
- `OPENAI_API_KEY`

#### DeepSeek AI:
Set one of these environment variables:
- `LLM_SIDEKICK_DEEPSEEK_API_KEY`
- `DEEPSEEK_API_KEY`

#### Google Gemini Models
Set one of these environment variables:
- `LLM_SIDEKICK_GEMINI_API_KEY`
- `GEMINI_API_KEY`

### Speech-to-Text Requirements (Optional)
Required only if you plan to use the `:Stt` command:
- sox (command-line audio recording tool)
- Working audio input device
- Groq API key (set as `LLM_SIDEKICK_GROQ_API_KEY` or `GROQ_API_KEY` environment variable) for Whisper model

#### Installing sox
- Ubuntu/Debian: `sudo apt-get install sox`
- macOS: `brew install sox`
- Arch Linux: `sudo pacman -S sox`

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'default-anton/llm-sidekick.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
  },
  config = function()
    require('llm-sidekick').setup({
      -- Model aliases configuration
      aliases = {
        pro = "gemini-2.5-pro",
        flash = "gemini-2.0-flash",
        sonnet = "claude-3-7-sonnet-latest",
        bedrock_sonnet = "anthropic.claude-3-7-sonnet",
        deepseek = "deepseek-chat",
        chatgpt = "gpt-4.1",
        mini = "gpt-4.1-mini",
        high_o3_mini = "o3-mini-high",
        low_o3_mini = "o3-mini-low",
      },
      yolo_mode = {
        file_operations = false, -- Automatically accept file operations
        terminal_commands = false, -- Automatically accept terminal commands
        auto_commit_changes = true,  -- Enable auto-commit
      },
      auto_commit_model = "gpt-4.1-mini",  -- Use a specific model for commit messages
      safe_terminal_commands = {"mkdir", "touch", "git commit"} -- List of terminal commands to automatically accept
      guidelines = "", -- Global guidelines that will be added to every chat
      default = "sonnet",
    })
  end,
}
```

## Supported Models

### Anthropic Claude Models
- `claude-3-7-sonnet-latest`
- `claude-3-5-sonnet-latest`
- `claude-3-5-haiku-latest`
- `anthropic.claude-sonnet-4`

### Google Gemini Models
- Gemini 2.5 Pro `gemini-2.5-pro`
- Gemini 2.5 Flash Preview 05-20 `gemini-2.5-flash-preview-05-20`
- Gemini 2.5 Flash `gemini-2.5-flash`
- Gemini 2.0 Flash `gemini-2.0-flash`
- Gemini 2.0 Flash Thinking `gemini-2.0-flash-thinking-chat`
- Gemini 2.0 Lite `gemini-2.0-flash-lite`
- Gemini 2.0 Flash Experimental `gemini-2.0-flash-exp`

### OpenAI Models
- `o3-low`
- `o3-medium`
- `o3-high`
- `o4-mini-low`
- `o4-mini-medium`
- `o4-mini-high`
- `gpt-4.1`
- `gpt-4.1-mini`
- `gpt-4.1-nano`
- `o3-mini-low`
- `o3-mini-medium`
- `o3-mini-high`
- `o1-low`
- `o1-medium`
- `o1-high`
- `o1-preview`
- `gpt-4o`
- `gpt-4o-2024-11-20`
- `gpt-4o-2024-08-06`
- `gpt-4o-2024-05-13`
- `gpt-4o-mini`

### DeepSeek AI Models
- `deepseek-chat`: DeepSeek-V3

## Usage

### Plan Mode

llm-sidekick.nvim includes a powerful Plan Mode feature for managing complex, multi-step tasks:

- **Purpose**: Creates and maintains a `plan.md` file that serves as a shared project roadmap between you and the AI
- **When to use it**: Ideal for complex refactoring, feature implementation, debugging sessions, or any multi-step development task
- **How it works**:
  - You explicitly request a plan for complex tasks
  - The plan is stored in `plan.md` in your working directory
  - Tasks are tracked using markdown checklists (`- [ ]` for pending, `- [x]` for completed items)
  - The plan is structured hierarchically with clear sections and sub-tasks
  - Both you and the AI can update the plan as tasks progress
  - The plan is automatically included in your conversations while active
  - Once all tasks are completed, the plan can be removed

**Example usage**:
```
Create a plan for refactoring this authentication system to use JWT tokens
```

```
I need to implement server-side form validation. Let's create a plan
```

### Commands

### Core Commands

#### `:Chat [args] [paths]`
Opens a new buffer for all interactions with the LLM.  This single command handles code-related tasks (creating, modifying, or deleting files), technical discussions (debugging, architecture, code explanations), and general conversations (brainstorming, creative writing).
- Arguments:
  - Model alias: any defined alias from configuration (e.g., claude, fast, o1, mini, flash)
  - Opening mode: `t` (tab), `v` (vsplit), `s` (split)
  - Range: Visual selection to include specific code
  - File paths: Include content from specific files or directories. Examples:
    - `%` (current file)
    - `script.js data.json` (multiple files)
    - `%:h` (all files in the current directory recursively)

#### `:Add [file|url]`
Adds content to the last chat with llm-sidekick. Can add content from:
- Current buffer
- Selected range
- Specified file path
- Directory path (recursively includes all files)
- URL to documentation or other web content (converted to markdown via jina.ai Reader API - only use with public URLs)

Must be used after the `:Chat` command.

#### `:Accept`
Applies a single change from the LLM response at the current cursor position. Use for selective, careful modifications.

#### `:AcceptAll`
Applies all changes from the LLM response at once. Use for bulk, consistent modifications.

Both commands handle file operations (create/modify/delete) and are available in `:Chat` buffers.

#### `:Stt`
Starts speech-to-text recording at the current cursor position. Shows a floating window with recording status. Press Enter to stop recording and insert the transcribed text, or press q to cancel. Works in both normal and insert modes.

#### `:Commit [context]`
Commits staged changes using an LLM-generated commit message.
- If you have staged files, this command will use the LLM to generate a descriptive commit message and commit the changes.
- If there are no staged files, you'll receive a warning notification.
- Optional `[context]`: You can provide additional context (e.g., a ticket number or a brief explanation) that will be passed to the LLM to help generate a more relevant commit message.

**Examples:**

Commit staged changes automatically:
```
:Commit
```

Commit staged changes with additional context:
```
:Commit Refactor user authentication flow (TICKET-123)
```

## Keybindings

Recommended keybindings for common operations:

```lua
-- Chat with LLM about code
vim.keymap.set('n', '<leader>lc', '<cmd>Chat vsplit %<CR>', { noremap = true, desc = "Chat with the current buffer" })
vim.keymap.set('v', '<leader>lc', '<cmd>Chat vsplit<CR>', { noremap = true, desc = "Chat with selected code" })
vim.keymap.set('n', '<leader>ld', '<cmd>Chat vsplit %:h<CR>', { noremap = true, desc = "Chat with the current directory" })

-- Only set <C-a> mappings if not in telescope buffer
local function set_add_keymap()
  local opts = { noremap = true, silent = true }
  -- Check if current buffer is not a telescope prompt
  if vim.bo.filetype ~= "TelescopePrompt" and vim.bo.filetype ~= "oil" then
    vim.keymap.set('n', '<C-a>', ':Add<CR>', vim.tbl_extend('force', opts, { desc = "Add context to LLM" }))
    vim.keymap.set('v', '<C-a>', ':Add<CR>', vim.tbl_extend('force', opts, { desc = "Add selected context to LLM" }))
  end
end

-- Set up an autocmd to run when entering buffers
vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
  callback = function()
    set_add_keymap()
  end,
})

-- Speech to text
vim.keymap.set('i', '<C-o>', '<cmd>Stt<CR>', { noremap = true, silent = true, desc = "Speech to text" })
```

## Telescope Integration

If you are using [Telescope](https://github.com/nvim-telescope/telescope.nvim), you can easily add a custom action to include selected files directly into your chat buffer using the `:Add` command.

To add a keybinding within Telescope to send the selected file to `llm-sidekick.nvim`, add the following to your Telescope configuration:

```lua
require("telescope").setup {
  defaults = {
    mappings = {
      i = {
        ["<C-a>"] = function(prompt_bufnr)
          local action_state = require("telescope.actions.state")

          local picker = action_state.get_current_picker(prompt_bufnr)
          local multi_selections = picker:get_multi_selection()

          if vim.tbl_isempty(multi_selections) then
            local selected_entry = action_state.get_selected_entry()
            if selected_entry and selected_entry.path then
              local filepath = selected_entry.path
              vim.cmd('Add ' .. filepath)
            else
              vim.notify("No selection")
            end
          else
            local files = vim.tbl_map(function(s) return s.path end, multi_selections)
            vim.cmd('Add ' .. table.concat(files, ' '))
          end

          return true
        end,
      },
    },
  },
}
```

This configuration adds `<C-a>` in Telescope's `insert` mode to execute the `:Add` command with the currently selected file path, allowing you to quickly add file content to your ongoing chat sessions.

## Project Configuration

llm-sidekick.nvim can be configured per project to provide context-aware assistance.

Create a `.llmsidekick.lua` file in your project root to define project-specific guidelines and technologies:

````lua
local lsk = require("llm-sidekick")

local guidelines = string.format([[
General information about the project:
```markdown
%s
```

Design documentation from ./DESIGN.md:
```markdown
%s
```

Tailwind CSS configuration file ./tailwind.config.js:
```javascript
%s
```]],
  lsk.read_file("APP.md"),
  lsk.read_file("DESIGN.md"),
  lsk.read_file("tailwind.config.js")
)

local technologies = [[
Frontend:
- Tailwind CSS
  - @tailwindcss/container-queries
  - @tailwindcss/forms
  - @tailwindcss/typography
- PostCSS
  - autoprefixer
- React (18.3)
- Vite (vite_rails)
- Inertia.js Rails
  - inertia_rails-contrib
- Heroicons (React)

Backend:
- Ruby on Rails (8.0)
- sqlite3
]]

return {
  guidelines = guidelines,
  technologies = technologies,
}
````

This configuration allows you to:
- Provide project-specific context to the LLM
- Include design documents and architectural decisions
- Define technology stack and constraints
- Load configuration from external files
- Customize the LLM's behavior based on your project's needs

## License

Apache License, Version 2.0
Copyright (c) 2024 Anton Kuzmenko
