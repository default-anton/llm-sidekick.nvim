return {
  file_operations = {
    require("llm-sidekick.tools.create_or_replace_file"),
    require("llm-sidekick.tools.replace_in_file"),
    require("llm-sidekick.tools.delete_file"),
  },
}
