# llm-sidekick.nvim

The missing code companion for Neovim. Fast, hackable, and stays out of your way.

## Features

- Chat with LLMs directly in Neovim
- Smart context handling for code-related queries
- Speech-to-text support
- Apply code modifications suggested by LLMs
- Multiple model support (Claude, OpenAI)

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

## Usage

## Commands

### Core Commands

#### `:Chat [args]`
Opens a new buffer for general conversation with the LLM. Perfect for brainstorming, creative writing, or any non-technical discussions.
- Arguments:
  - Model type: `smart` (default), `fast` (quick responses), `reason` (complex problems)
  - Opening mode: `t` (tab), `v` (vsplit), `s` (split)
  - `f`: include entire current file

#### `:Ask [args]`
Opens a new buffer to ask software engineering and development-related questions. Uses a prompt optimized for technical discussions and problem-solving. Accepts an optional range to include the selected code.
- Arguments: Same as `:Chat`

#### `:Code [args]`
Similar to `:Ask` but includes additional context for file modifications.
- Arguments: Same as `:Chat`

#### `:Add [file|url]`
Adds content to the last chat with llm-sidekick. Can add content from:
- Current buffer
- Selected range
- Specified file path
- Directory path (recursively includes all files)
- URL to documentation or other web content (converted to markdown via jina.ai Reader API - only use with public URLs)

Must be used after an `:Ask`, `:Code`, or `:Chat` command.

#### `:Apply [all]`
Applies file modifications from the LLM response. Only available in buffers created by the `:Code` command.
- Without arguments: applies changes from the modification block at cursor position
- With `all`: applies all changes from the current assistant response

#### `:Stt`
Starts speech-to-text recording at the current cursor position. Shows a floating window with recording status. Press Enter to stop recording and insert the transcribed text, or press q to cancel. Works in both normal and insert modes.

See `:help llm-sidekick` for detailed documentation.

## License

Apache License, Version 2.0  
Copyright (c) 2024 Anton Kuzmenko
