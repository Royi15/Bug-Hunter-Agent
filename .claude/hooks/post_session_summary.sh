#!/bin/bash
# =============================================================================
# Post-Hook 6: Session Summary
# Purpose:    Generate a formatted summary from session.log when Claude stops.
# Input:      JSON on stdin: {"session_id":"...","cwd":"...","stop_hook_active":false}
# Exit codes: 0 always
# IMPORTANT:  Checks stop_hook_active first to prevent infinite loops.
# =============================================================================
INPUT="$(cat)"

# Check if stop_hook_active is true, if yes, we skip the summary generation to avoid infinite loops
if printf '%s' "$INPUT" | grep -q '"stop_hook_active":true'; then
    exit 0
fi

# Extract session_id
SESSION_ID="$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//')"

# Set log path to .claude/hooks/data/session_<session_id>.log
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$HOOK_DIR/data/session_$SESSION_ID.log"

# Check if log doesnt exist or is empty
if [ ! -s "$LOG_FILE" ]; then
    echo "No session activity recorded."
    exit 0
fi


# Gather statistics from the log:
# Total lines
TOTAL_ACTIONS=$(wc -l < "$LOG_FILE")

# Count backup lines
BACKUPS_MADE=$(grep -c " BACKUP " "$LOG_FILE")

# Count SYNTAX_OK and SYNTAX_ERROR lines separately
SYNTAX_OK=$(grep -c " SYNTAX_OK " "$LOG_FILE")
SYNTAX_ERROR=$(grep -c " SYNTAX_ERROR " "$LOG_FILE")

# First and last timestamps
START_TIME=$(head -n 1 "$LOG_FILE" | awk -F'[][]' '{print $2}')
END_TIME=$(tail -n 1 "$LOG_FILE" | awk -F'[][]' '{print $2}')

# Top 3 most-edited files
FORMATTED_TOP_FILES=$(grep " BACKUP " "$LOG_FILE" | awk '{print $4}' | sort | uniq -c | sort -rn | head -n 3 | awk '{ e="edits"; if($1==1) e="edit"; print "  " NR ". " $2 " (" $1 " " e ")" }')
# File type counts
FORMATTED_FILE_TYPES=$(grep -E " BACKUP | SYNTAX_" "$LOG_FILE" | awk '{print $4}' | awk -F. 'NF>1 {print "."$NF}' | sort | uniq -c | sort -rn | awk '{printf "  %-8s files: %d\n", $2, $1}')

TOTAL_SYNTAX_CHECKS=$((SYNTAX_OK + SYNTAX_ERROR))

REPORT=$(cat <<EOF
════════════════════════════════════════
        SESSION SUMMARY REPORT
════════════════════════════════════════

Session: $SESSION_ID
Period:  $START_TIME -> $END_TIME

── Activity ─────────────────────────
  Total actions: $TOTAL_ACTIONS
  Backups made:  $BACKUPS_MADE
  Syntax checks: $TOTAL_SYNTAX_CHECKS
  Syntax errors: $SYNTAX_ERROR

── Most Edited Files ────────────────
$FORMATTED_TOP_FILES

── File Types ───────────────────────
$FORMATTED_FILE_TYPES
EOF
)

# we must replace newlines with \n to ensure we dont destory the json format
REPORT_SAFE_FOR_JSON="${REPORT//$'\n'/\\n}"

printf '{"systemMessage": "%s"}\n' "$REPORT_SAFE_FOR_JSON"

exit 0
