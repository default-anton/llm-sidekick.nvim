return {
  file_operations = {
    require("llm-sidekick.tools.create_file"),
    require("llm-sidekick.tools.replace_in_file"),
    require("llm-sidekick.tools.delete_file"),
  },
}
