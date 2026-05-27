#!/bin/bash
# =============================================================================
# Pre-Hook: Secrets Guard
# Purpose:    Block Claude Code from reading files listed in secret_files.txt.
# Input:      JSON on stdin: {"tool_name":"Read","tool_input":{"file_path":"..."},...}
# Exit codes: 0 = allow, 2 = block (file is secret)
# =============================================================================

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$HOOK_DIR/config/secret_files.txt"

# Read entire JSON input from stdin
INPUT="$(cat)"

# Extract file_path from tool_input
FILE_PATH="$(printf '%s' "$INPUT" | grep -o '"file_path":"[^"]*"' | head -1 | sed 's/"file_path":"//;s/"//')"

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Normalize: convert backslashes to forward slashes, lowercase for comparison
normalize() {
    printf '%s' "$1" | tr '\\' '/' | tr '[:upper:]' '[:lower:]'
}

NORMALIZED_PATH="$(normalize "$FILE_PATH")"

# Check config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    exit 0
fi

# Check file path against each entry in the blacklist
while IFS= read -r entry; do
    # Skip comments and empty lines
    case "$entry" in
        '#'*|'') continue ;;
    esac

    NORMALIZED_ENTRY="$(normalize "$entry")"

    # Block if the file path ends with the blacklist entry (suffix match)
    case "$NORMALIZED_PATH" in
        *"$NORMALIZED_ENTRY")
            printf "BLOCKED: Reading '%s' is not allowed (matches secret file rule '%s').\n" "$FILE_PATH" "$entry" >&2
            exit 2
            ;;
    esac
done < "$CONFIG_FILE"

exit 0
