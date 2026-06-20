#!/bin/bash
# =============================================================================
# Post-Hook 4: Auto-Backup
# Purpose:    After a file edit, create a timestamped backup with rotation.
# Input:      JSON on stdin: {"tool_name":"Edit","tool_input":{"file_path":"..."},...}
# Exit codes: 0 always (post-hooks should not block)
# Backups:    data/.backups/<basename>.<timestamp>
# Log:        data/session.log
# =============================================================================
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
INPUT="$(cat)"

# Extract file_path from tool_input
FILE_PATH="$(printf '%s' "$INPUT" | grep -oE '"file_path":"([^"\\]|\\.)*"' | head -1 | sed 's/^"file_path":"//; s/"$//')"

# Extract session_id
SESSION_ID="$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//')"

# if session_id is empty, we use default session
if [ -z "$SESSION_ID" ]; then
    SESSION_ID="default"
fi

# if file_path is empty or the file doesnt exist, we exit 0
if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# generate a time stamp
TIMESTAMP=$(date +"%Y-%m-%d_%H%M%S")

# create backup directory if not exists
mkdir -p "$HOOK_DIR/data/.backups"

# copy the file to the backup directory with the timestamp
FILE_BASENAME=$(basename "$FILE_PATH")
BACKUP_PATH="$HOOK_DIR/data/.backups/${FILE_BASENAME}.${TIMESTAMP}"
cp "$FILE_PATH" "$BACKUP_PATH"

# get the file size
FILE_SIZE=$(wc -c < "$FILE_PATH")


# Append to .claude/hooks/data/session_<session_id>.log
LOG_TIME=$(date +"%Y-%m-%d %H:%M:%S")
LOG_FILE="$HOOK_DIR/data/session_${SESSION_ID}.log"
echo "[$LOG_TIME] BACKUP $FILE_PATH -> .backups/${FILE_BASENAME}.${TIMESTAMP} ($FILE_SIZE bytes)" >> "$LOG_FILE"

# read MAX_BACKUPS from hooks.conf
CONFIG_FILE="$HOOK_DIR/config/hooks.conf"
if [ -f "$CONFIG_FILE" ]; then
    MAX_BACKUPS=$(grep "^MAX_BACKUPS=" "$CONFIG_FILE" | cut -d'=' -f2)
fi

# if not set, default to 5
if [ -z "$MAX_BACKUPS" ]; then
    MAX_BACKUPS=5
fi

# Count existing backups for this filename
BACKUP_COUNT=$(ls "$HOOK_DIR/data/.backups/${FILE_BASENAME}."* 2>/dev/null | wc -l)

# If exceeding MAX_BACKUPS, delete the oldest ones
if [ "$BACKUP_COUNT" -gt "$MAX_BACKUPS" ]; then
    ls -t "$HOOK_DIR/data/.backups/${FILE_BASENAME}."* 2>/dev/null | tail -n +$(($MAX_BACKUPS + 1)) | xargs -r rm --
fi

exit 0
