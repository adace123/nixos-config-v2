#!/bin/bash
# Setup YubiKey for sudo authentication via pam-u2f
set -e

CONFIG_DIR="$HOME/.config/Yubico"
KEYS_FILE="$CONFIG_DIR/u2f_keys"

echo "YubiKey sudo authentication setup"
echo "================================="
echo

# Check if pam-u2f is installed
if ! command -v pamu2fcfg &> /dev/null; then
    echo "Error: pamu2fcfg not found. Install pam-u2f first:"
    echo "  brew install pam-u2f"
    exit 1
fi

# Check if the PAM module exists
PAM_MODULE="/opt/homebrew/lib/pam/pam_u2f.so"
if [[ ! -f "$PAM_MODULE" ]]; then
    echo "Error: PAM module not found at $PAM_MODULE"
    echo "Try reinstalling: brew reinstall pam-u2f"
    exit 1
fi

# Create config directory
mkdir -p "$CONFIG_DIR"

if [[ -f "$KEYS_FILE" ]]; then
    echo "Existing keys found at $KEYS_FILE"
    echo
    echo "Options:"
    echo "  1) Add another YubiKey (backup)"
    echo "  2) Replace all keys (start fresh)"
    echo "  3) Exit"
    echo
    read -r -p "Choose [1-3]: " choice

    case $choice in
        1)
            echo
            echo "Insert your backup YubiKey and press Enter..."
            read -r
            echo "Touch your YubiKey when it blinks..."
            pamu2fcfg -n >> "$KEYS_FILE"
            echo "Backup key added successfully!"
            ;;
        2)
            echo
            echo "Insert your primary YubiKey and press Enter..."
            read -r
            echo "Touch your YubiKey when it blinks..."
            pamu2fcfg > "$KEYS_FILE"
            echo "Keys replaced. Primary key registered."
            echo
            read -r -p "Add a backup key now? [y/N]: " backup
            if [[ "$backup" =~ ^[Yy] ]]; then
                echo "Insert your backup YubiKey and press Enter..."
                read -r
                echo "Touch your YubiKey when it blinks..."
                pamu2fcfg -n >> "$KEYS_FILE"
                echo "Backup key added!"
            fi
            ;;
        3)
            echo "Exiting."
            exit 0
            ;;
        *)
            echo "Invalid choice."
            exit 1
            ;;
    esac
else
    echo "No existing keys found. Setting up new YubiKey..."
    echo
    echo "Insert your YubiKey and press Enter..."
    read -r
    echo "Touch your YubiKey when it blinks..."
    pamu2fcfg > "$KEYS_FILE"
    echo "Primary key registered successfully!"
    echo
    read -r -p "Add a backup key now? [y/N]: " backup
    if [[ "$backup" =~ ^[Yy] ]]; then
        echo "Insert your backup YubiKey and press Enter..."
        read -r
        echo "Touch your YubiKey when it blinks..."
        pamu2fcfg -n >> "$KEYS_FILE"
        echo "Backup key added!"
    fi
fi

echo
echo "Setup complete!"
echo
echo "Test with: sudo -k && sudo echo 'YubiKey auth works!'"
echo
echo "Your YubiKey should blink. Touch it to authenticate."
echo "If the YubiKey is not inserted, Touch ID will be used as fallback."
