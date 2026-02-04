#!/usr/bin/env bash
# Migration script to move SSH keys to 1Password

set -e

echo "🔐 Migrating SSH keys to 1Password"
echo ""

# Check if 1Password CLI is installed
if ! command -v op &> /dev/null; then
    echo "❌ 1Password CLI (op) is not installed"
    echo "Install it from: https://1password.com/downloads/command-line/"
    exit 1
fi

# Check if SSH agent is enabled in 1Password
if [ ! -S ~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock ]; then
    echo "❌ 1Password SSH agent is not enabled"
    echo ""
    echo "To enable it:"
    echo "1. Open 1Password"
    echo "2. Go to Settings → Developer"
    echo "3. Enable 'Use the SSH agent'"
    echo "4. Check 'Display key names when authorizing connections'"
    exit 1
fi

echo "✅ 1Password SSH agent is enabled"
echo ""

# Display current keys
echo "📋 Your current SSH keys:"
echo ""
echo "Personal key:"
cat ~/.ssh/id_ed25519.pub
echo ""
echo "Work key:"
cat ~/.ssh/id_ed25519.work.pub
echo ""

echo "📝 Next steps:"
echo ""
echo "1. Import your SSH keys to 1Password:"
echo "   - Open 1Password"
echo "   - Click '+' → 'SSH Key'"
echo "   - Paste your PRIVATE key content"
echo "   - Name it (e.g., 'GitHub Personal' and 'GitLab Work')"
echo ""
echo "2. Get your public keys from 1Password for git signing:"
echo "   ssh-add -L"
echo ""
echo "3. Update these files with your public keys:"
echo "   - modules/home/git.nix (user.signingkey)"
echo "   - ~/.config/git/work-config (user.signingkey)"
echo ""
echo "4. Add your public keys to GitHub/GitLab:"
echo "   - GitHub: Settings → SSH and GPG keys"
echo "   - GitLab: Preferences → SSH Keys"
echo "   - Also add to 'Signing Keys' section for commit verification"
echo ""
echo "5. Rebuild your config:"
echo "   darwin-rebuild switch --flake ~/Projects/nixos-config-v2"
echo ""
echo "6. Test SSH connections:"
echo "   ssh -T git@github.com"
echo "   ssh -T git@work-git"
echo ""
