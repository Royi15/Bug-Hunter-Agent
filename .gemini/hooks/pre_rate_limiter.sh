#!/bin/bash
# =============================================================================
# Pre-Hook 2: Rate Limiter
# Purpose:    Track command count per session, block after exceeding limit.
# Input:      JSON on stdin: {"tool_name":"Bash","tool_input":{"command":"..."},"session_id":"..."}
# Exit codes: 0 = allow (possibly with warning), 2 = blocked (limit exceeded)
# State file: data/.command_count — format per line: session_id|total|type1:N,type2:N,...
# =============================================================================
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HOOK_DIR/data"
STATE_FILE="$HOOK_DIR/data/.command_count"

# Read entire JSON input from stdin
INPUT="$(cat)"

# Extract command from tool_input
TOOL_COMMAND="$(printf '%s' "$INPUT" | grep -oE '"command":"([^"\\]|\\.)*"' | head -1 | sed 's/^"command":"//; s/"$//')"

# Extract session_id
SESSION_ID="$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//')"


# if seesion_id is empty, we use default session
if [ -z "$SESSION_ID" ]; then
    SESSION_ID="default"
fi

# read limits  and warning thresholds from config
CONFIG_FILE="$HOOK_DIR/config/hooks.conf"
if [ -f "$CONFIG_FILE" ]; then
    MAX_COMMANDS=$(grep "^MAX_COMMANDS=" "$CONFIG_FILE" | cut -d'=' -f2)
    WARNING_THRESHOLD=$(grep "^WARNING_THRESHOLD=" "$CONFIG_FILE" | cut -d'=' -f2)
fi

if [ -z "$MAX_COMMANDS" ]; then
    MAX_COMMANDS=50
fi

if [ -z "$WARNING_THRESHOLD" ]; then
    WARNING_THRESHOLD=40
fi

# extract command type (first word of the command).
CMD_TYPE=$(printf '%s' "$TOOL_COMMAND" | awk '{print $1}')

# checking if .reset_commands file exists, if exists, reset the command count for the session
RESET_FILE="$HOOK_DIR/data/.reset_commands"
if [ -f "$RESET_FILE" ]; then
    # if the reset file exists, we reset the command count for the session and remove the reset file
    if [ -f "$STATE_FILE" ]; then
        # we create a new temp file without the session_id line
        grep -v "^$SESSION_ID|" "$STATE_FILE" > "$STATE_FILE.tmp"
        mv "$STATE_FILE.tmp" "$STATE_FILE"
    fi
    rm -f "$RESET_FILE"
fi

# Find the line for the current session_id
if [ -f "$STATE_FILE" ]; then
    SESSION_LINE="$(grep "^$SESSION_ID|" "$STATE_FILE")"
fi

if [ -z "$SESSION_LINE" ]; then
    # No existing record for this session, create a new one
    TOTAL=1
    TYPE_COUNTS="$CMD_TYPE:1"
else
    # Parse existing record
    TOTAL=$(printf '%s' "$SESSION_LINE" | cut -d'|' -f2)
    TYPE_COUNTS=$(printf '%s' "$SESSION_LINE" | cut -d'|' -f3)

    # Increment total count
    TOTAL=$((TOTAL + 1))

   # Update type count
   if printf '%s' "$TYPE_COUNTS" | grep -qE "(^|,)$CMD_TYPE:"; then
        CURRENT_TYPE_COUNT=$(printf '%s' "$TYPE_COUNTS" | grep -oE "(^|,)$CMD_TYPE:[0-9]+" | cut -d':' -f2)
        NEW_TYPE_COUNT=$((CURRENT_TYPE_COUNT + 1))

        TYPE_COUNTS=$(printf '%s' "$TYPE_COUNTS" | sed -E "s/(^|,)$CMD_TYPE:$CURRENT_TYPE_COUNT/\1$CMD_TYPE:$NEW_TYPE_COUNT/")
    else
        TYPE_COUNTS="$TYPE_COUNTS,$CMD_TYPE:1"
    fi
fi

# Update the state file with the new counts
if [ -f "$STATE_FILE" ]; then
    # Remove old line for the session_id
    grep -v "^$SESSION_ID|" "$STATE_FILE" > "$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"
fi
echo "$SESSION_ID|$TOTAL|$TYPE_COUNTS" >> "$STATE_FILE"

# check the limits
if [ "$TOTAL" -gt "$MAX_COMMANDS" ]; then
    echo "BLOCKED: Session exceeded maximum allowed commands ($TOTAL/$MAX_COMMANDS)." >&2
    echo "Breakdown: $TYPE_COUNTS" >&2
    exit 2
elif [ "$TOTAL" -gt "$WARNING_THRESHOLD" ]; then
    echo "WARNING: Session is approaching the command limit ($TOTAL/$MAX_COMMANDS)." >&2
    exit 0
else
    exit 0
fi
