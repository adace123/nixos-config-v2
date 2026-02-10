#!/usr/bin/env bash
# AI Assistant Selector using gum

# Show header
gum style \
	--foreground 212 --border-foreground 212 --border double \
	--align center --width 50 --margin "1 2" --padding "1 4" \
	'AI Assistant Selector' 'Choose your coding companion'

# Define assistants (name|command pairs)
assistants=(
	"Claude Code|claude"
	"Opencode|opencode"
	"Gemini CLI|gemini"
	"GitHub Copilot|copilot"
)

# Extract names for selection
options=()
for entry in "${assistants[@]}"; do
	name="${entry%%|*}"
	options+=("$name")
done

# Use gum to select
selected=$(printf '%s\n' "${options[@]}" | gum choose \
	--header "Select an AI assistant:" \
	--header.foreground 212 \
	--cursor.foreground 212 \
	--selected.foreground 212 \
	--height 10)

# Launch selected assistant
if [ -n "$selected" ]; then
	for entry in "${assistants[@]}"; do
		name="${entry%%|*}"
		cmd="${entry#*|}"
		if [ "$name" = "$selected" ]; then
			clear
			gum style \
				--foreground 212 \
				"Launching $selected..."
			echo ""
			# Use eval to properly execute the command string
			eval "$cmd"
			exit 0
		fi
	done
fi
