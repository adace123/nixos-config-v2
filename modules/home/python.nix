{ pkgs, ... }:
{
  home = {
    packages = with pkgs; [
      # Python version
      python313 # Python 3.13 (only version)

      # UV - Fast Python package installer and resolver
      uv # Replaces pip, pip-tools, pipx, poetry, pyenv, virtualenv

      # Python development tools
      ruff # Extremely fast Python linter and formatter (includes LSP)
      mypy # Static type checker

      # Python packages (these come with Python or should be installed via uv/pip in projects)
      python313Packages.ipython # Enhanced Python REPL
      python313Packages.requests # HTTP library for Python
    ];

    # Python environment configuration
    sessionVariables = {
      # UV configuration
      UV_PYTHON_PREFERENCE = "only-managed"; # Prefer UV-managed Python versions
      UV_LINK_MODE = "copy"; # Copy files instead of hardlinking

      # Python configuration
      PYTHONBREAKPOINT = "ipdb.set_trace"; # Use ipdb for breakpoints
      PYTHON_CONFIGURE_OPTS = "--enable-shared --enable-optimizations --with-lto";
    };

    # UV configuration file
    file.".config/uv/uv.toml".text = ''
      # UV configuration
      python-preference = "only-managed"
      link-mode = "copy"
    '';

    # Ruff configuration (Black-compatible)
    file.".config/ruff/ruff.toml".text = ''
      # Ruff configuration - Black compatible
      line-length = 88
      target-version = "py313"

      [lint]
      select = ["E", "F", "I", "N", "W", "UP"]
      # Ignore rules that conflict with Black
      ignore = [
        "E501",  # Line too long (handled by formatter)
        "W191",  # Indentation contains tabs (Black uses spaces)
        "E111",  # Indentation is not a multiple of 4 (Black's choice)
        "E114",  # Indentation is not a multiple of 4 (comment)
        "E117",  # Over-indented
        "E203",  # Whitespace before ':' (Black compatibility)
      ]

      [format]
      quote-style = "double"
      indent-style = "space"
      line-ending = "auto"
      skip-magic-trailing-comma = false
    '';
  };

  # Shell aliases for Python development
  programs.zsh.shellAliases = {
    # UV shortcuts
    uv-init = "uv init";
    uv-add = "uv add";
    uv-sync = "uv sync";
    uv-run = "uv run";
    uv-tool = "uv tool";

    # Python shortcuts
    py = "ipython";

    # Virtual environment
    venv = "uv venv";
    activate = "source .venv/bin/activate";

    # Testing
    test = "uv run pytest";

    # Linting and formatting
    lint = "ruff check .";
    format = "ruff format .";
    typecheck = "mypy .";

    marimo = "uvx marimo";
  };
}
