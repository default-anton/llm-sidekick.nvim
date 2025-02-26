"""Utility functions for auto_context."""

import os

def get_plugin_path() -> str:
    """Get the plugin path following XDG Base Directory Specification.

    Returns:
        str: Path to the plugin state directory
    """
    state_home = os.environ.get("XDG_STATE_HOME")
    if not state_home or state_home == "":
        state_home = os.path.expanduser("~/.local/state")

    return os.path.join(state_home, "nvim", "llm-sidekick")

def get_default_db_path() -> str:
    """Get the default path for Milvus database files.

    Returns:
        str: Path to the default Milvus database directory
    """
    plugin_path = get_plugin_path()
    db_path = os.path.join(plugin_path, "milvus-lite.db")

    # Ensure the directory exists
    os.makedirs(os.path.dirname(db_path), exist_ok=True)

    return db_path
