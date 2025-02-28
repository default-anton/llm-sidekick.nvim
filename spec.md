# Feature: Auto-Context
## 1. Goal

To empower `llm-sidekick.nvim` to act as a codebase expert, capable of understanding and responding to user requests related to their project without requiring explicit context specification from the user. The plugin should intelligently and automatically gather relevant context from the codebase to effectively assist with various software engineering tasks.

## 2. User Stories and Use Cases

This feature aims to support a wide range of development tasks. Here are some key user stories illustrating the intended functionality:

**2.1 Factoid Questions:**

*   **User:** "Where is the authentication middleware defined?"
*   **Expected Behavior:** `llm-sidekick.nvim` should identify and present the file and code location where the authentication middleware is defined in the codebase.

**2.2 Code Modification Assistance:**

*   **User:** "Write unit tests for the `UserService` class."
*   **Expected Behavior:** `llm-sidekick.nvim` should:
    *   Locate the `UserService` class definition.
    *   Identify its dependencies.
    *   Find existing tests related to `UserService` or similar services.
    *   Potentially locate test factories or data fixtures used in the project.
    *   Provide a starting point for writing unit tests, potentially including boilerplate code or suggestions based on the gathered context.

**2.3 General Code Understanding:**

*   **User:** "Explain how data validation is implemented in this project."
*   **Expected Behavior:** `llm-sidekick.nvim` should identify relevant code sections related to data validation (e.g., validation functions, schemas, middleware) and provide a summary or explanation based on the codebase context.

## 3. Technical Approach: Context Sources and Retrieval

To achieve auto-context, `llm-sidekick.nvim` will utilize several context sources and retrieval strategies:

**3.1 Neovim Environment:**

*   **Currently Open Files:**  The plugin will have immediate access to the content of buffers currently open in Neovim. This is crucial for tasks related to the code the user is actively working on.
*   **Recently Edited Files:**  Leveraging Neovim's history or a plugin like `persistence.nvim`, the plugin can access recently modified files, providing context related to the user's recent activity.
