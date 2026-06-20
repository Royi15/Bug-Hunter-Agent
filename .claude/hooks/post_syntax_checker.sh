#!/bin/bash
# =============================================================================
# Post-Hook 5: Syntax Checker
# Purpose:    Run appropriate syntax checker based on file extension after edit.
# Input:      JSON on stdin: {"tool_name":"Edit","tool_input":{"file_path":"..."},...}
# Exit codes: 0 = syntax OK (or no checker), 1 = syntax error (warn, don't block)
# Supported:  .sh/.bash (bash -n), .py (python3 -m py_compile), .c/.h (gcc -fsyntax-only)
# =============================================================================
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
INPUT="$(cat)"

# Extract file_path from tool_input
FILE_PATH="$(printf '%s' "$INPUT" | grep -oE '"file_path":"([^"\\]|\\.)*"' | head -1 | sed 's/^"file_path":"//; s/"$//')"

# Extract session_id
SESSION_ID="$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//')"

# if file path is empty or the file doesnt exist, we exit 0
if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

LOG_FILE="$HOOK_DIR/data/session_${SESSION_ID}.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# extract file extension
EXTENSION="${FILE_PATH##*.}"

# case test the file extension and run the appropriate syntax checker
case "$EXTENSION" in
    sh|bash)
        if ! OUTPUT=$(bash -n "$FILE_PATH" 2>&1); then
            echo "SYNTAX ERROR in $FILE_PATH: $OUTPUT" >&2
            echo "[$TIMESTAMP] SYNTAX_ERROR $FILE_PATH ($EXTENSION)" >> "$LOG_FILE"
            exit 1
        else
            echo "Syntax OK: $FILE_PATH"
            echo "[$TIMESTAMP] SYNTAX_OK $FILE_PATH ($EXTENSION)" >> "$LOG_FILE"
            exit 0
        fi
        ;;
    py)
        if ! OUTPUT=$(python3 -m py_compile "$FILE_PATH" 2>&1); then
            echo "SYNTAX ERROR in $FILE_PATH: $OUTPUT" >&2
            echo "[$TIMESTAMP] SYNTAX_ERROR $FILE_PATH ($EXTENSION)" >> "$LOG_FILE"
            exit 1
        else
            echo "Syntax OK: $FILE_PATH"
            echo "[$TIMESTAMP] SYNTAX_OK $FILE_PATH ($EXTENSION)" >> "$LOG_FILE"
            exit 0
        fi
        ;;
    c|h)
        if ! OUTPUT=$(gcc -fsyntax-only "$FILE_PATH" 2>&1); then
            echo "SYNTAX ERROR in $FILE_PATH: $OUTPUT" >&2
            echo "[$TIMESTAMP] SYNTAX_ERROR $FILE_PATH ($EXTENSION)" >> "$LOG_FILE"
            exit 1
        else
            echo "Syntax OK: $FILE_PATH"
            echo "[$TIMESTAMP] SYNTAX_OK $FILE_PATH ($EXTENSION)" >> "$LOG_FILE"
            exit 0
        fi
        ;;
    *)
        printf "No syntax checker for .%s\n" "$EXTENSION" >&2
        exit 0

esac
