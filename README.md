# llm-sidekick.nvim

The missing code companion for Neovim. Fast, hackable, and stays out of your way.

## Features

llm-sidekick.nvim turns your editor into a powerful code companion:

- `:Code` - Write, refactor, and modify multiple files
- `:Apply` - Apply suggested changes incrementally or all at once
- `:Ask` - Technical discussions about code, debugging, and architecture
- `:Add` - Add files, code, or URLs (any web content) to your conversation
- `:Chat` - Have open-ended discussions for brainstorming and creative tasks
- `:Stt` - Use speech-to-text input instead of typing

The plugin is designed to be fast, stay out of your way, and integrate naturally with your Neovim workflow. It supports multiple AI models and lets you choose between quick responses or deep reasoning based on your needs.

## Requirements

### Core Requirements
- Neovim >= 0.5.0
- curl (for API requests)
- plenary.nvim

#### Installing curl
- Ubuntu/Debian: `sudo apt-get install curl`
- macOS: `brew install curl`
- Arch Linux: `sudo pacman -S curl`

### API Requirements
You only need to set up API keys for the providers whose models you intend to use:

#### Anthropic (Claude models)
Set one of these environment variables:
- `LLM_SIDEKICK_ANTHROPIC_API_KEY`
- `ANTHROPIC_API_KEY`

#### OpenAI (GPT models)
Set one of these environment variables:
- `LLM_SIDEKICK_OPENAI_API_KEY`
- `OPENAI_API_KEY`

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
            -- Model configuration
            smart_model = "claude-3-5-sonnet-latest",  -- Your go-to model
            fast_model = "claude-3-5-haiku-latest",    -- Model for quick responses
            reasoning_model = "o1",                    -- Model for complex reasoning
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

### Ollama Models
- `ollama-qwen2.5-coder:1.5b`

Each model is configured with specific token limits and temperature settings optimized for different use cases.

## Usage

## Commands

### Core Commands

#### `:Code [args]`
Opens a new buffer for code-related tasks. Handles file operations like creating, modifying, or deleting files.
- Arguments:
  - Model type: `smart` (default), `fast` (quick responses), `reason` (complex problems)
  - Opening mode: `t` (tab), `v` (vsplit), `s` (split)
  - `f` (file): include entire current file
  - Range: Visual selection to include specific code

#### `:Ask [args]`
Opens a new buffer for technical discussions. Optimized for debugging, architecture discussions, and code explanations.
- Arguments: Same as `:Code`

#### `:Chat [args]`
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

See `:help llm-sidekick` for detailed documentation.

## License

Apache License, Version 2.0
Copyright (c) 2024 Anton Kuzmenko
