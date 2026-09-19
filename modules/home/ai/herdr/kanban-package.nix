# Packaging for the herdr-kanban plugin's board.
#
# The TUI is a Python package (`plugins/kanban/kanban/`) copied into the store
# and run with the interpreter from `python3.withPackages [ textual ]`. The
# launcher is the repo's `launcher.sh` with its @PYTHON@ / @APPDIR@
# placeholders substituted for those store paths.
#
# The plugin directory herdr links stays outside the store:
# `herdr plugin link` canonicalises the linked path, so a store symlink would
# go stale on every rebuild. herdr.nix's activation copies the manifest and the
# launcher below into ~/.config/herdr/plugins-managed/kanban instead.
{
  pkgs,
}:
let
  inherit (pkgs) lib;

  python = pkgs.python3.withPackages (ps: [ ps.textual ]);

  # Every module the package must contain and import, spelled out rather than
  # discovered: the point of this list is to catch a file that is *absent* from
  # the tree, which `readDir` would simply not report. The build below also
  # asserts the reverse — nothing may be packaged that is not listed here — so a
  # new module cannot slip in unimported. `__main__` is the pane entrypoint
  # (`python -m kanban`), and is the one file whose absence would otherwise only
  # show up as a board that flashes and closes.
  required_modules = [
    "__main__"
    "app"
    "cli"
    "config"
    "demo"
    "dispatch"
    "herdr"
    "icons"
    "modals"
    "model"
    "render"
    "selftest"
    "store"
    "widgets"
  ];

  # Packaged but not imported by the check: nothing to import, it just marks
  # the directory as a package.
  unchecked_modules = [ "__init__" ];

  app = pkgs.runCommand "herdr-kanban-app" { } ''
    mkdir -p $out/share/herdr-kanban/kanban
    # Only the sources: the working tree can carry __pycache__ from a run in the
    # repo, and a stale .pyc in the store would ship as if it were source.
    cp ${./plugins/kanban/kanban}/*.py $out/share/herdr-kanban/kanban/
    cp ${./plugins/kanban/kanban}/*.tcss $out/share/herdr-kanban/kanban/

    # `nix build` copies the whole working tree, but a flake resolves through
    # git — so an untracked module builds and passes here and then dies with
    # ModuleNotFoundError the moment `just switch` deploys it (which is exactly
    # how the board came to flash and close). Fail at build time instead.
    required="${lib.concatStringsSep " " required_modules}"
    unchecked="${lib.concatStringsSep " " unchecked_modules}"

    for module in $required; do
      if [ ! -f "$out/share/herdr-kanban/kanban/$module.py" ]; then
        echo "kanban: module $module.py is missing from this build." >&2
        echo "kanban: if it exists in your working tree, it is untracked — the" >&2
        echo "kanban: flake resolves through git, so run: git add <file>" >&2
        exit 1
      fi
    done

    # The reverse: nothing may be packaged without being listed, or a new module
    # would ship unimported and unverified.
    for path in $out/share/herdr-kanban/kanban/*.py; do
      name="$(basename "$path" .py)"
      case " $required $unchecked " in
        *" $name "*) ;;
        *)
          echo "kanban: $name.py is packaged but not listed in required_modules." >&2
          echo "kanban: add it to kanban-package.nix so it gets import-checked." >&2
          exit 1
          ;;
      esac
    done

    # Import all of it with the same interpreter the launcher uses, so a missing
    # dependency or a syntax error is a failed build rather than a board that
    # flashes and closes. `__main__` is imported as a module, which does not run
    # its `if __name__ == "__main__"` guard. -B: no bytecode in the store.
    PYTHONPATH=$out/share/herdr-kanban ${python}/bin/python -B -c \
      'import ${lib.concatStringsSep ", " (map (name: "kanban." + name) required_modules)}'
  '';

  launcher = pkgs.writeScript "herdr-kanban-launcher" (
    builtins.replaceStrings
      [ "@PYTHON@" "@APPDIR@" ]
      [ "${python}/bin/python" "${app}/share/herdr-kanban" ]
      (builtins.readFile ./plugins/kanban/launcher.sh)
  );
in
{
  inherit
    python
    app
    launcher
    required_modules
    ;

  # Everything the activation script copies into the plugin directory.
  manifest = ./plugins/kanban/herdr-plugin.toml;
  config = ./plugins/kanban/config.toml;

  # Handy for a shell-level smoke test: build this and run `herdr-kanban`.
  cli = pkgs.writeShellScriptBin "herdr-kanban" ''
    export PYTHONPATH="${app}/share/herdr-kanban''${PYTHONPATH:+:$PYTHONPATH}"
    exec "${python}/bin/python" -m kanban "$@"
  '';
}
