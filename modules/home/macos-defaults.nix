{ lib, pkgs, ... }:
let
  # ⌥⌘Space (Option+Command+Space) opens Finder's Spotlight-style search window
  # ("Search This Mac"). macOS has no switch for it in System Settings →
  # Keyboard Shortcuts: it is symbolic hotkey 65 in the per-user
  # com.apple.symbolichotkeys domain, where an id *absent* from the plist means
  # "default, enabled". Storing the id with `enabled = false` turns it off.
  #
  # `defaults write -dict-add` cannot express that entry: it refuses nested
  # composite types, and an old-style value (`{enabled = 0;}`) is stored as
  # strings, which the login-time reader does not accept for the boolean and
  # integer fields. So patch a copy of the exported domain with PlistBuddy,
  # which writes real types, and import it back.
  #
  # The domain is per-user, so this has to run as the user rather than in the
  # root activation, and WindowServer only reads it when a login session starts:
  # a switch flips the shortcut for the next login, not the current one.
  disableFinderSearchHotkey = pkgs.writeShellScript "disable-finder-search-hotkey" ''
    set -euo pipefail

    domain=com.apple.symbolichotkeys
    tmp=$(/usr/bin/mktemp -t symbolichotkeys)
    trap 'rm -f "$tmp"' EXIT

    /usr/bin/defaults export "$domain" "$tmp"
    # Both the containing dict and the id itself may be missing on a fresh
    # account: absent means default-enabled, so add rather than rely on them.
    /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys dict" "$tmp" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Delete :AppleSymbolicHotKeys:65" "$tmp" 2>/dev/null || true
    /usr/libexec/PlistBuddy \
      -c "Add :AppleSymbolicHotKeys:65 dict" \
      -c "Add :AppleSymbolicHotKeys:65:enabled bool false" \
      "$tmp"
    /usr/libexec/PlistBuddy \
      -c "Add :AppleSymbolicHotKeys:65:value dict" \
      -c "Add :AppleSymbolicHotKeys:65:value:type string standard" \
      -c "Add :AppleSymbolicHotKeys:65:value:parameters array" \
      -c "Add :AppleSymbolicHotKeys:65:value:parameters:0 integer 32" \
      -c "Add :AppleSymbolicHotKeys:65:value:parameters:1 integer 49" \
      -c "Add :AppleSymbolicHotKeys:65:value:parameters:2 integer 1572864" \
      "$tmp"
    /usr/bin/defaults import "$domain" "$tmp"
  '';
in
{
  home.activation.disableFinderSearchHotkey = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${disableFinderSearchHotkey}
  '';
}
