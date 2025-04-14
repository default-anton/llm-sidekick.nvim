# Auto Commit Feature

## Overview
The auto-commit feature automatically commits changes made by the LLM assistant to your git repository. This is useful for keeping track of changes made by the assistant and for maintaining a clean commit history.

## Configuration

### Enable Auto Commit
To enable auto-commit, set the `auto_commit_changes` option to `true` in your configuration:

```lua
require('llm-sidekick').setup({
  yolo_mode = {
    auto_commit_changes = true,  -- Enable auto-commit
  }
})
```

### Specify Auto Commit Model
By default, the auto-commit feature uses your default LLM model to generate commit messages. You can specify a different model specifically for generating commit messages:

```lua
require('llm-sidekick').setup({
  auto_commit_model = "gpt-4.1-mini",  -- Use a specific model for commit messages
})
```

## How It Works

1. When the assistant makes changes to files using tools like `str_replace_editor`, `create_or_replace_file`, or `edit_file_section`, these files are tracked.
2. After all tools have completed execution, if auto-commit is enabled:
   - The changes are staged using `git add`
   - The assistant generates a commit message based on the diffs of the changed files
   - The changes are committed with the generated message

## Commit Message Generation

The commit message generator:
1. Gets the diff for each modified file using `git diff --cached`
2. Sends these diffs to the LLM with instructions to generate a conventional commit message
3. Formats and cleans the response to ensure it's a proper single-line commit message

The generated commit messages follow the [Conventional Commits](https://www.conventionalcommits.org/) format, e.g.:
- `feat: Add auto-commit feature with diff-based message generation`
- `fix: Correct error handling in openai client`
- `refactor: Improve code organization in settings module`

## Fallback Behavior

If the commit message generation fails for any reason, a generic fallback message is used:
```
chore: Auto-commit changes to N files
```
where N is the number of modified files.
