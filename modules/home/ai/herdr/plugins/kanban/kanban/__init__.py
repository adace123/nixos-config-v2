"""herdr-kanban — a kanban board for agent work, inside herdr.

The board keeps its own task list (`store`), reads live workspace and agent
state from the herdr CLI (`herdr`), and draws everything as a Textual app
(`app` + `render`). See ../herdr-plugin.toml for the plugin manifest.
"""

__version__ = "0.1.0"
