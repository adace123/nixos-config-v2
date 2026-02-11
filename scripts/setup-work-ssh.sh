#!/usr/bin/env bash
# Setup script for work SSH configuration

set -e

echo "🔑 Setting up work SSH configuration..."
echo ""

# Check if work key exists
if [ ! -f ~/.ssh/id_ed25519_work ]; then
	echo "⚠️  Work SSH key not found at ~/.ssh/id_ed25519_work"
	read -p "Would you like to generate a new work SSH key? (y/n) " -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_work -C "work-key"
		echo "✅ Work SSH key generated"
		echo ""
		echo "📋 Your work public key:"
		cat ~/.ssh/id_ed25519_work.pub
		echo ""
		echo "👆 Add this key to your work git server"
		echo ""
	fi
else
	echo "✅ Work SSH key found at ~/.ssh/id_ed25519_work"
fi

# Create work SSH config if it doesn't exist
if [ ! -f ~/.ssh/work-config ]; then
	echo ""
	echo "📝 Creating work SSH config from example..."

	if [ -f ~/.ssh/work-config.example ]; then
		cp ~/.ssh/work-config.example ~/.ssh/work-config
		echo "✅ Created ~/.ssh/work-config from example"
		echo ""
		echo "⚠️  IMPORTANT: Edit ~/.ssh/work-config and update:"
		echo "   - HostName: your work git server address"
		echo "   - Host: the alias you want to use (e.g., work-git, gitlab-work)"
		echo ""
		read -p "Would you like to edit it now? (y/n) " -n 1 -r
		echo
		if [[ $REPLY =~ ^[Yy]$ ]]; then
			${EDITOR:-nano} ~/.ssh/work-config
		fi
	else
		echo "⚠️  Example file not found. Run 'darwin-rebuild switch' first."
	fi
else
	echo "✅ Work SSH config already exists at ~/.ssh/work-config"
fi

# Create work git config if it doesn't exist
if [ ! -f ~/.config/git/work-config ]; then
	echo ""
	echo "📝 Creating work git config from example..."
	mkdir -p ~/.config/git

	if [ -f ~/.config/git/work-config.example ]; then
		cp ~/.config/git/work-config.example ~/.config/git/work-config
		echo "✅ Created ~/.config/git/work-config from example"
		echo ""
		echo "⚠️  IMPORTANT: Edit ~/.config/git/work-config and update:"
		echo "   - user.email: your work email"
		echo "   - url.insteadOf: your work git server URL pattern"
		echo ""
		read -p "Would you like to edit it now? (y/n) " -n 1 -r
		echo
		if [[ $REPLY =~ ^[Yy]$ ]]; then
			${EDITOR:-nano} ~/.config/git/work-config
		fi
	else
		echo "⚠️  Example file not found. Run 'darwin-rebuild switch' first."
	fi
else
	echo "✅ Work git config already exists at ~/.config/git/work-config"
fi

# Create work projects directory
if [ ! -d ~/Projects/work ]; then
	echo ""
	read -p "Would you like to create ~/Projects/work directory? (y/n) " -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		mkdir -p ~/Projects/work
		echo "✅ Created ~/Projects/work directory"
	fi
else
	echo "✅ Work projects directory exists at ~/Projects/work"
fi

echo ""
echo "✨ Setup complete!"
echo ""
echo "📖 Next steps:"
echo "   1. Add your work public key (~/.ssh/id_ed25519_work.pub) to your work git server"
echo "   2. Edit ~/.ssh/work-config with your work git server hostname"
echo "   3. Edit ~/.config/git/work-config with your work email"
echo "   4. Clone work repos to ~/Projects/work/"
echo ""
echo "💡 Usage examples:"
echo "   For personal GitHub: git clone git@github.com:user/repo.git"
echo "   For work git server: git clone git@work-git:company/repo.git ~/Projects/work/repo"
echo ""
