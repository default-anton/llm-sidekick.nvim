# llm-sidekick.nvim

The missing code companion for Neovim. Fast, hackable, and stays out of your way.

## Features

llm-sidekick.nvim turns your editor into a powerful code companion:

- `:Code` - Write, refactor, and modify multiple files
- `:Apply` - Apply suggested changes incrementally or all at once
- `:Ask` - Technical discussions about code, debugging, and architecture
- `:Add` - Add files, code, or URLs (any web content) to your conversation
- `:Stt` - Use speech-to-text input instead of typing
- `:Yolo` - Like `:Code`, but automatically applies changes and closes the chat buffer
- `:Chat` - Have open-ended discussions for brainstorming and creative tasks

The plugin is designed to be fast, stay out of your way, and integrate naturally with your Neovim workflow. It supports multiple AI models and lets you choose between quick responses or deep reasoning based on your needs.

## Requirements

### Core Requirements
- Neovim >= 0.5.0
- curl (for API requests)
- plenary.nvim
- uv (for AWS Bedrock integration)

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

Additionally, AWS Bedrock models require the `uv` package. Follow the [installation instructions](https://docs.astral.sh/uv/getting-started/installation/).

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
- Groq API key (set as `GROQ_API_KEY` environment variable)

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
        deepseek = "deepseek-chat",
        sonnet = "claude-3-5-sonnet-latest",
        exp_gemini = "gemini-exp-1206",
        o1 = "o1-preview",
        mini = "o1-mini",
        flash = "gemini-2.0-flash-exp",
        think_flash = "gemini-2.0-flash-thinking-exp-1219",
        gpt = "gpt-4o-2024-11-20",
      },
      default = "sonnet",
    })
  end,
}
```

## Supported Models

### Anthropic Claude Models
- `claude-3-5-sonnet-latest`
- `claude-3-5-haiku-latest`

### OpenAI Models
- `gpt-4o`
- `gpt-4o-2024-11-20`
- `gpt-4o-2024-08-06`
- `gpt-4o-2024-05-13`
- `gpt-4o-mini`
- `o1`
- `o1-mini`
- `o1-preview`

### DeepSeek AI Models
- `deepseek-chat`

### Google Gemini Models
- Gemini Experimental 1206 `gemini-exp-1206`
- Gemini 2.0 Flash Experimental `gemini-2.0-flash-exp`
- Gemini 2.0 Flash Thinking Experimental `gemini-2.0-flash-thinking-exp-1219`

### Ollama Models
- `ollama-qwen2.5-coder:1.5b`

Each model is configured with specific token limits and temperature settings optimized for different use cases.

## Usage

## Commands

### Core Commands

#### `:Code [args] [paths]`
Opens a new buffer for code-related tasks. Handles file operations like creating, modifying, or deleting files.
- Arguments:
  - Model alias: any defined alias from configuration (e.g., claude, fast, o1, mini, flash)
  - Opening mode: `t` (tab), `v` (vsplit), `s` (split)
  - Range: Visual selection to include specific code
  - File paths: Include content from specific files or directories. Examples:
    - `%` (current file)
    - `script.js data.json` (multiple files)
    - `%:h` (all files in the current directory recursively)

#### `:Yolo [args] [paths]`
Like `:Code`, but automatically applies changes and closes the chat buffer.
- Arguments: Same as `:Code`, minus the opening mode. Opening mode is always `split`.

#### `:Ask [args] [paths]`
Opens a new buffer for technical discussions. Optimized for debugging, architecture discussions, and code explanations.
- Arguments: Same as `:Code`

#### `:Chat [args] [paths]`
Opens a new buffer for general conversation with the LLM. Perfect for brainstorming, creative writing, or any non-technical discussions. Supports range selection for including text context.
- Arguments: Same as `:Code`

#### `:Add [file|url]`
Adds content to the last chat with llm-sidekick. Can add content from:
- Current buffer
- Selected range
- Specified file path
- Directory path (recursively includes all files)
- URL to documentation or other web content (converted to markdown via jina.ai Reader API - only use with public URLs)

Must be used after an `:Ask`, `:Code`, or `:Chat` command.

#### `:Apply [all]`
Applies file modifications from the LLM response. Handles complex operations across multiple files, including:
- Creating new files and directories
- Modifying specific sections of existing files
- Deleting files or code snippets
- Applying changes to multiple files in a single operation

Only available in buffers created by the `:Code` command.
- Without arguments: applies changes from the modification block at cursor position
- With `all`: applies all changes from the current assistant response, maintaining consistency across related modifications

#### `:Stt`
Starts speech-to-text recording at the current cursor position. Shows a floating window with recording status. Press Enter to stop recording and insert the transcribed text, or press q to cancel. Works in both normal and insert modes.

Recommended keybinding for insert mode:
```lua
vim.keymap.set('i', '<C-o>', '<cmd>Stt<CR>', { noremap = true, silent = true, desc = "Speech to text" })
```

## Keybindings

Recommended keybindings for common operations:

```lua
-- Ask LLM about code
vim.keymap.set('n', '<leader>la', '<cmd>Ask split %<CR>', { noremap = true, desc = "Ask LLM about current buffer" })
vim.keymap.set('v', '<leader>la', '<cmd>Ask split<CR>', { noremap = true, desc = "Ask LLM about selection" })

-- Code with LLM
vim.keymap.set('n', '<leader>lc', '<cmd>Code split %<CR>', { noremap = true, desc = "Start coding with LLM on current buffer" })
vim.keymap.set('v', '<leader>lc', '<cmd>Code split<CR>', { noremap = true, desc = "Start coding with LLM on selection" })
vim.keymap.set('n', '<leader>ld', '<cmd>Code split %:h<CR>', { noremap = true, desc = "Start coding with LLM on files in current directory" })

-- Apply LLM changes
vim.keymap.set('n', '<leader>lp', '<cmd>Apply all<CR>', { noremap = true, desc = "Apply all LLM changes" })

-- Add context to LLM
vim.keymap.set('n', '<leader>ad', '<cmd>Add<CR>', { noremap = true, desc = "Add context to LLM" })
vim.keymap.set('v', '<leader>ad', '<cmd>Add<CR>', { noremap = true, desc = "Add selected context to LLM" })

-- Fast coding with Yolo mode
vim.keymap.set('n', '<leader>ly', '<cmd>Yolo split %<CR>', { noremap = true, desc = "Fast coding with LLM on current buffer. Automatically applies changes and closes the chat buffer" })
vim.keymap.set('v', '<leader>ly', '<cmd>Yolo split<CR>', { noremap = true, desc = "Fast coding with LLM on selection. Automatically applies changes and closes the chat buffer" })
```

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
