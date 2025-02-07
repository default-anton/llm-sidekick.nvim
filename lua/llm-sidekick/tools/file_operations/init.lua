local mod_format = [[
When you need to suggest modifications to existing files, creation of new files, or deletion of files, you must use the following format:

For Modifications:

**Path:**
```
<path to file>
```
**Find:**
```
<text to find>
```
**Replace:**
```
<replacement text>
```

For Creation:

**Path:**
```
<path to new file>
```
**Create:**
```
<content of the new file>
```

For Deletion:

**Path:**
```
<path to file to delete>
```
**Delete:**
```
N/A
```

**Important guidelines for using this format:**

1. **File Operations Structure:**
   - Each file operation begins with **Path:** followed by the file's path enclosed in triple backticks.
   - Specify the type of operation (**Find/Replace**, **Create**, or **Delete**) accordingly.

2. **Modifying Files:**
   - **Find:** Include the exact text that needs to be located for modification. This must be an EXACT, CHARACTER-FOR-CHARACTER match of the original text, including all comments, spacing, indentation, and formatting.
   - **Replace:** Provide the new text that will replace the found text. Ensure that the replacement maintains the original file's formatting and style.
   - Only include the relevant sections of the file necessary for the modification, not the entire file content.
   - Use the **Find** section to provide sufficient surrounding context to uniquely identify the location of the change.

3. **Creating New Files:**
   - **Create:** Include the entire content of the new file. Ensure that the content is correctly formatted and adheres to the project's coding standards.

4. **Deleting Files:**
   - **Delete:** Simply state `N/A` to indicate that the specified file should be deleted.

5. **Multiple File Operations:**
   - For multiple operations, repeat the above structure for each file.
   - For multiple modifications within the same file, create separate operation blocks for each change to maintain clarity.

6. **Formatting Requirements:**
   - Ensure that each section (**Path**, **Find**, **Replace**, **Create**, **Delete**) is clearly labeled and formatted as shown.
   - Use triple backticks for content sections to preserve formatting and readability.
   - Do not include any additional text or comments outside the specified format.

7. **Preservation of Original Formatting:**
   - Maintain all indentation, spacing, and formatting within the **Find**, **Replace**, and **Create** sections to match the original code's style.
   - Avoid introducing formatting changes unless they are part of the intended modification.

8. **Planning Changes:**
   - Before listing the file operations, include a brief plan outlining the changes.

**Example:**

For clarity, here's an example demonstrating how to use the format for various file operations:

```
**Path:**
```
logging.yaml
```
**Create:**
```
version: 1
handlers:
  console:
    class: logging.StreamHandler
    level: DEBUG
    stream: ext://sys.stdout
root:
  level: DEBUG
  handlers: [console]
```

```
**Path:**
```
config.yaml
```
**Find:**
```
development:
  database:
    host: localhost
    port: 5432
  logging:
    level: DEBUG
    file: dev.log
```
**Replace:**
```
development:
  database:
    host: localhost
    port: 5432
```

```
**Path:**
```
config.yaml
```
**Find:**
```
general:
  app_name: My App
```
**Replace:**
```
general:
  app_name: My App
  enable_new_feature: true
```

```
**Path:**
```
old_feature.yaml
```
**Delete:**
```
N/A
```
---
**IMPORTANT:** You must include ALL content in the **Find** sections exactly as it appears in the original file, including comments, whitespace, and seemingly irrelevant details. Do not omit or modify any characters.

You must use this format whenever suggesting modifications to existing files, creation of new files, or deletion of files.
]]


return {
  require("llm-sidekick.tools.file_operations.create_or_replace_file"),
  require("llm-sidekick.tools.file_operations.search_and_replace_in_file"),
  require("llm-sidekick.tools.file_operations.delete_file"),
}
