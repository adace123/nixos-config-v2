#!/bin/bash
# Install (or remove) the ASIX AX88179 USB 3.0 -> gigabit Ethernet driver.
#
# Why this is a script and not a Homebrew cask: the chip is USB vendor-class
# (bDeviceClass 0xFF), so macOS ships no driver for it. The USB interface is
# published, nothing binds to it, no en* interface is ever created, and the
# adapter never appears in Network settings. (The newer AX88179A speaks native
# CDC-NCM and needs none of this.)
#
# Homebrew's `asix-ax88179` cask would install exactly this package, but it is
# disabled upstream:
#
#   disable! date: "2026-09-01", because: :fails_gatekeeper_check
#
# `brew` refuses disabled casks, so listing it in modules/darwin/homebrew.nix
# would fail adoption on every `just switch`. This script vendors the same
# vendor package instead, pinned and checksummed.
#
# Re-run after a major macOS upgrade: the DriverKit extension can stop loading.
#
#   ./scripts/setup-asix-ethernet.sh              # install
#   ./scripts/setup-asix-ethernet.sh --uninstall  # remove
set -euo pipefail

# Pinned to the release Homebrew's cask referenced. FILE_ID is ASIX's opaque
# download id; SHA256 is the cask's own checksum, so a changed payload aborts.
VERSION="2.5.0"
FILE_ID="1951"
SHA256="616fc388b5a10462f9aa5b1780fb86bc7230a40431da4a287cffd5fbcacc47b0"

URL="https://www.asix.com.tw/en/support/download/file/${FILE_ID}"
WORK="$(mktemp -d)"
MOUNT=""

usage() {
	cat <<'EOF'
Usage: setup-asix-ethernet.sh [--uninstall]

  (no args)     Install the ASIX AX88179 driver, then require approval in
                System Settings and a reboot.
  --uninstall   Remove the driver with ASIX's own uninstaller.
  -h, --help    Show this help.
EOF
}

cleanup() {
	if [[ -n $MOUNT ]]; then
		hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
	fi
	rm -rf "$WORK"
}
trap cleanup EXIT

MODE="install"
case "${1:-}" in
"") ;;
--uninstall) MODE="uninstall" ;;
-h | --help)
	usage
	exit 0
	;;
*)
	echo "Unknown argument: $1" >&2
	usage >&2
	exit 1
	;;
esac

echo "ASIX AX88179 USB Ethernet driver v${VERSION}"
echo "==========================================="
echo

if [[ $MODE == "install" ]]; then
	# Receipt names are inconsistent (the vendor ships e.g.
	# com.mygreatcompany.pkg.AX88179178A and com.asix.ax88179.uninstall), so
	# match either token rather than relying on the asix prefix.
	if pkgutil --pkgs 2>/dev/null | grep -qiE 'asix|ax88179'; then
		echo "A driver is already installed; reinstalling (this is the fix for a"
		echo "driver that stopped loading after a macOS upgrade)."
		echo
	fi
fi

echo "Downloading from asix.com.tw..."
ZIP="$WORK/asix.zip"
curl -fL --progress-bar -o "$ZIP" "$URL"

actual="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
if [[ $actual != "$SHA256" ]]; then
	echo "Error: checksum mismatch — refusing to install" >&2
	echo "  expected $SHA256" >&2
	echo "  got      $actual" >&2
	exit 1
fi
echo "Checksum OK"

unzip -oq "$ZIP" -d "$WORK/x"
DMG="$(find "$WORK/x" -maxdepth 1 -name '*.dmg' -print -quit)"
if [[ -z $DMG ]]; then
	echo "Error: no .dmg found in the downloaded archive" >&2
	exit 1
fi

MOUNT="$(hdiutil attach -readonly -nobrowse -noverify "$DMG" | awk -F'\t' '/\/Volumes\//{print $NF; exit}')"
if [[ -z $MOUNT ]]; then
	echo "Error: could not mount $DMG" >&2
	exit 1
fi

if [[ $MODE == "uninstall" ]]; then
	PKG="$(find "$MOUNT" -maxdepth 1 -name '*Uninstall*.pkg' -print -quit)"
else
	PKG="$(find "$MOUNT" -maxdepth 1 -name '*Installer*.pkg' -print -quit)"
fi
if [[ -z $PKG ]]; then
	echo "Error: no suitable .pkg found in $MOUNT" >&2
	exit 1
fi

if pkgutil --check-signature "$PKG" 2>/dev/null | grep -q "signed by a developer certificate"; then
	echo "Package signature: valid (ASIX Developer ID)"
else
	echo "Warning: package is not signed by an Apple developer certificate." >&2
	read -r -p "Continue anyway? [y/N] " reply
	[[ $reply =~ ^[Yy]$ ]] || exit 1
fi

echo
sudo installer -pkg "$PKG" -target /
echo

if [[ $MODE == "uninstall" ]]; then
	echo "Driver removed. Reboot to finish."
	exit 0
fi

cat <<'EOF'
Driver installed. Two manual steps remain — neither can be automated:

  1. Approve the extension:
       System Settings -> General -> Login Items & Extensions
       -> Driver Extensions -> allow "ASIX ELECTRONICS CORPORATION"

     If that toggle is greyed out, this Mac is MDM-managed (Jamf) and the
     approval is policy-blocked — that is an IT request, not a local fix.

  2. Reboot (the installer requires it; the extension will not load until then).

Verify after rebooting:

  ifconfig -a | grep -A3 '^en[0-9]'   # a new en* with a burned-in MAC appears
  networksetup -listallhardwareports  # adapter shows as a real USB LAN device
EOF
