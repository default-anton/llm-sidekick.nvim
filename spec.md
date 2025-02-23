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

**2.3 Refactoring Tasks:**

*   **User:** "Find all usages of the `deprecatedFunction`."
*   **Expected Behavior:** `llm-sidekick.nvim` should leverage LSP or other code analysis methods to identify all instances where `deprecatedFunction` is called within the codebase and present them to the user.

**2.4 General Code Understanding:**

*   **User:** "Explain how data validation is implemented in this project."
*   **Expected Behavior:** `llm-sidekick.nvim` should identify relevant code sections related to data validation (e.g., validation functions, schemas, middleware) and provide a summary or explanation based on the codebase context.

## 3. Technical Approach: Context Sources and Retrieval

To achieve auto-context, `llm-sidekick.nvim` will utilize several context sources and retrieval strategies:

**3.1 Neovim Environment:**

*   **Currently Open Files:**  The plugin will have immediate access to the content of buffers currently open in Neovim. This is crucial for tasks related to the code the user is actively working on.
*   **Recently Edited Files:**  Leveraging Neovim's history or a plugin like `persistence.nvim`, the plugin can access recently modified files, providing context related to the user's recent activity.

**3.2 Language Server Protocol (LSP):**

*   **Semantic Analysis:** LSP provides powerful code analysis capabilities, including:
    *   **Definition/Declaration Lookup:**  Find the definition of symbols (functions, classes, variables).
    *   **Reference Finding:**  Find all references to a symbol.
    *   **Document Symbols:**  Retrieve a structured outline of symbols within a file.
    *   **Workspace Symbols:**  Search for symbols across the entire project.
    *   **Type Information:**  Retrieve type information for symbols and expressions.
    *   LSP will be a primary source for understanding code structure, relationships, and navigating the codebase semantically.

**3.3 Search Indexing (Future Enhancement):**

*   **Vector Similarity Search:**  Creating a vector index of code embeddings (e.g., using Tree-sitter to parse code and generate embeddings) would enable semantic search capabilities. This would be useful for finding code snippets similar to a user query, even if they don't use exact keywords.
    * Use https://huggingface.co/Alibaba-NLP/gte-modernbert-base text embedding model.
    * **File Discovery:** Use `fd` to recursively find all project files, automatically excluding gitignored files.
    * **Code Parsing:** Use tree-sitter to parse files and extract:
        - Individual functions (with their docstrings)
        - Classes (including their methods and class-level docstrings)
        - Other relevant code structures
    * **Embedding Strategy:** 
        - Embed each function separately to allow fine-grained search
        - Embed individual methods within classes for method-level context
        - Embed full classes including their methods and docstrings for class-level context
        - Include all relevant comments in the embeddings
    * **Tree-sitter Queries:** Implement SCM files similar to aider's approach (https://raw.githubusercontent.com/Ailer-AI/aider/refs/heads/main/aider/queries/tree-sitter-languages/ruby-tags.scm) to extract code structures consistently across languages.
*   **Keyword Search:**  Traditional keyword-based search (potentially using `:vimgrep` or a Lua-based indexing solution) can complement vector search for quickly finding code based on literal terms.
*   **Tree-sitter Integration:**  Tree-sitter can be used to parse code into abstract syntax trees (ASTs). This structured representation can be leveraged for more sophisticated code analysis and indexing, potentially beyond just keyword and vector search.  For example, indexing code based on its structure and relationships.

**3.4 Multi-Step Context Retrieval Process:**

The context retrieval process should be intelligent and iterative.  It might involve the following steps:

1.  **Initial Query Analysis:** Analyze the user's natural language query to understand the intent and identify keywords or potential code entities (e.g., class names, function names).
2.  **Context Source Prioritization:**  Determine the most relevant context sources based on the query. For example, for questions about the currently open file, prioritize open buffers. For project-wide searches, utilize LSP and the search index.
3.  **Context Retrieval and Filtering:**  Query the prioritized context sources to retrieve potentially relevant information. Filter and rank the results based on relevance to the user's query.
4.  **Context Refinement (Iterative):**  Based on the initial retrieved context, the plugin might:
    *   **Identify Missing Context:** Realize that more information is needed (e.g., dependencies of a class).
    *   **Expand Search:**  Perform further searches based on the initial results to gather more context.
    *   **Re-rank Context:**  Refine the ranking of context based on newly acquired information.
5.  **Context Presentation/Utilization:**  Present the gathered context to the LLM assistant or directly utilize it to perform the requested task (e.g., generate test code, find references).

**3.5 Pathway Selection:**

Different types of user requests may require different context retrieval pathways.  For example:

*   **Factoid questions:**  Might primarily rely on keyword search, LSP symbol lookups, and open file content.
*   **Code modification tasks:**  Will require deeper context about the code to be modified, its dependencies, and related code (tests, factories).  This might involve more iterative context gathering and LSP analysis.
*   **Refactoring tasks:**  Will heavily rely on LSP's reference finding capabilities.

## 4. Challenges and Considerations

*   **Context Reranking and Relevance:**  Ensuring that the retrieved context is truly relevant to the user's query and ranked appropriately is crucial for effective assistance.  Sophisticated ranking algorithms might be needed.
*   **Performance:**  Context retrieval should be efficient and not introduce noticeable delays in Neovim. Indexing and search operations need to be optimized.
*   **Handling Ambiguous Queries:** Natural language queries can be ambiguous. The plugin needs to be robust in handling ambiguity and potentially asking clarifying questions to the user if necessary.
*   **Scalability to Large Codebases:**  The context retrieval mechanisms should scale effectively to very large codebases without becoming slow or resource-intensive.
*   **Integration with LLM Assistant:**  The way the retrieved context is presented to and utilized by the LLM assistant is important.  We need to consider how to effectively communicate the context to the LLM for optimal task performance.

## 5. Neovim Implementation Considerations

*   **Lua for Logic:**  The core logic for context retrieval and processing will be implemented in Lua.
*   **Neovim APIs:**  Utilize `vim.api` to interact with Neovim buffers, windows, and LSP.
*   **Plenary.nvim and Telescope.nvim:**  Consider leveraging Plenary.nvim for utility functions and potentially Telescope.nvim for interactive context exploration or presentation to the user (if needed).
*   **Background Processing:**  For potentially long-running tasks like indexing, consider using Neovim's job control or Lua coroutines to perform them in the background without blocking the UI.