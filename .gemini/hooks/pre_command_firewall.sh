#!/bin/bash
# =============================================================================
# Pre-Hook 1: Command Firewall
# Purpose:    Block dangerous bash commands before execution.
# Input:      JSON on stdin: {"tool_name":"Bash","tool_input":{"command":"..."},...}
# Exit codes: 0 = allow, 2 = block (dangerous pattern matched)
# =============================================================================
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$HOOK_DIR/config/dangerous_patterns.txt"

# Read entire JSON input from stdin
INPUT="$(cat)"

# Extract name from tool_name
TOOL_NAME="$(printf '%s' "$INPUT" | grep -o '"tool_name":"[^"]*"' | head -1 | sed 's/"tool_name":"//;s/"//')"

if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi


# Extract command from tool_input
TOOL_COMMAND="$(printf '%s' "$INPUT" | grep -oE '"command":"([^"\\]|\\.)*"' | head -1 | sed 's/^"command":"//; s/"$//')"

if [ -z "$TOOL_COMMAND" ]; then
    exit 0
fi

if [ ! -f "$CONFIG_FILE" ]; then
    exit 0
fi

# Check command against each Regex pattern in the config file
while IFS= read -r pattern; do
    #skip empty lines and comments
    case "$pattern" in
        '#'* | '') continue ;;
    esac
    # using grep -qE to evaluate the regex pattern against the command
    if printf '%s' "$TOOL_COMMAND" | grep -qE "$pattern"; then
        printf "BLOCKED: Command matches dangerous pattern '%s'. Please use a safer alternative.\n" "$pattern" >&2
        exit 2
    fi
done < "$CONFIG_FILE"


exit 0
