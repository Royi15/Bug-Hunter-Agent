#!/bin/bash
# =============================================================================
# Hook Runner
# Purpose:    Standalone simulator of Claude Code's hook execution for testing.
#             Reads hooks_config.txt, matches event+tool, runs hooks in order.
# Usage:      echo '<json>' | ./hook_runner.sh <event_type> <tool_name>
# Examples:
#   echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"},"session_id":"s1"}' \
#       | ./hook_runner.sh PreToolUse Bash
#   echo '{"tool_name":"Edit","tool_input":{"file_path":"main.c"},"session_id":"s1"}' \
#       | ./hook_runner.sh PostToolUse Edit
# =============================================================================

# ── Colour codes ───────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

RUNNER_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$RUNNER_DIR/hooks_config.txt"

# ── Argument validation ────────────────────────────────────────────────────────
if [ -z "$1" ] || [ -z "$2" ]; then
    printf '%bUsage:%b echo '"'"'<json>'"'"' | %s <event_type> <tool_name>\n' "$BOLD" "$RESET" "$0"
    printf '\n'
    printf 'event_type examples: PreToolUse, PostToolUse, Stop\n'
    printf 'tool_name  examples: Bash, Edit, Write, MultiEdit, *\n'
    printf '\n'
    printf 'Config file: %s\n' "$CONFIG_FILE"
    exit 1
fi

EVENT_TYPE="$1"
TOOL_NAME="$2"

# ── Validate config file ───────────────────────────────────────────────────────
if [ ! -f "$CONFIG_FILE" ]; then
    printf '%bERROR:%b Config file not found: %s\n' "$RED" "$RESET" "$CONFIG_FILE" >&2
    exit 1
fi

# ── Read stdin into temp file (hooks need to re-read it) ──────────────────────
TEMP_FILE="$(mktemp)"
trap 'rm -f "$TEMP_FILE"' EXIT
cat > "$TEMP_FILE"

printf '%b─── Hook Runner (%s / %s) ───%b\n' "$BOLD" "$EVENT_TYPE" "$TOOL_NAME" "$RESET"
printf '\n'

# ── Statistics ─────────────────────────────────────────────────────────────────
MATCHED=0
PASSED=0
BLOCKED=0
WARNINGS=0
FINAL_EXIT=0

# first we count the MATCHED hooks before we run them, since those are the orders from the forume.
# the forums says that we need to print the number of all matched hooks even if we break before we run them all.
while IFS=':' read -r CONF_EVENT CONF_MATCHER CONF_SCRIPT; do
    # Skip comments and empty lines
    case "$CONF_EVENT" in '#'*|'') continue ;; esac

    # we skip the line if we doesnt recognize the EVENT_TYPE
    if [ "$CONF_EVENT" != "$EVENT_TYPE" ]; then
        continue
    fi

    # we skip the line if the matcher doesnt match the TOOL_NAME and is not '*'
    if [ "$CONF_MATCHER" != "$TOOL_NAME" ] && [ "$CONF_MATCHER" != "*" ]; then
        continue
    fi

    # if we are here, it means that the line is matched, so we increment the MATCHED counter
    MATCHED=$((MATCHED + 1))
done < "$CONFIG_FILE"


while IFS=':' read -r CONF_EVENT CONF_MATCHER CONF_SCRIPT; do
    # Skip comments and empty lines
    case "$CONF_EVENT" in
            '#'*|'') continue ;;
    esac

    # we skip the line if we doesnt recognize the EVENT_TYPE
    if [ "$CONF_EVENT" != "$EVENT_TYPE" ]; then
        continue
    fi

    # we skip the line if the matcher doesnt match the TOOL_NAME and is not '*'
    if [ "$CONF_MATCHER" != "$TOOL_NAME" ] && [ "$CONF_MATCHER" != "*" ]; then
        continue
    fi


    # Resolve script path if it starts with ./
    if [[ "$CONF_SCRIPT" == ./* ]]; then
        SCRIPT_PATH="$RUNNER_DIR/${CONF_SCRIPT:2}"
    else
        SCRIPT_PATH="$CONF_SCRIPT"
    fi

    printf '%bRunning hook:%b %s\n' "$CYAN" "$RESET" "$SCRIPT_PATH"

    # temp file to catch errors, letting normal output print directly
    TMP_ERR=$(mktemp)

    # here we execute the hook, and save the errors in the TMP_ERR
    bash "$SCRIPT_PATH" < "$TEMP_FILE" 2> "$TMP_ERR"

    # we save the exit code of the last command (the hook script)
    EXIT_CODE=$?

    # we save the errors output from the file
    STDERR_OUTPUT="$(cat "$TMP_ERR")"

    # remove the file
    rm -f "$TMP_ERR"

    # we print according to the EXIT_CODE of the hook script
    case "$EXIT_CODE" in
        0)
            printf '%b✔ Passed%b\n' "$GREEN" "$RESET"
            PASSED=$((PASSED + 1))
            ;;
        2)
            printf '%b✖ BLOCKED%b\n' "$RED" "$RESET"
            if [ -n "$STDERR_OUTPUT" ]; then
                printf '%bHook error output:%b\n%s\n' "$RED" "$RESET" "$STDERR_OUTPUT"
            fi
            BLOCKED=$((BLOCKED + 1))
            FINAL_EXIT=2
            printf '%bChain stopped due to BLOCKED hook.%b\n' "$RED" "$RESET"
            break
            ;;
        *)
            printf '%b⚠  Warning (exit %d)%b\n' "$YELLOW" "$EXIT_CODE" "$RESET"
            if [ -n "$STDERR_OUTPUT" ]; then
                printf '%bHook error output:%b\n%s\n' "$YELLOW" "$RESET" "$STDERR_OUTPUT"
            fi
            WARNINGS=$((WARNINGS + 1))
            ;;
    esac
    printf '\n'
done < "$CONFIG_FILE"



# ── Summary ────────────────────────────────────────────────────────────────────
printf '%b─── Hook Execution Summary ─────────────%b\n' "$BOLD" "$RESET"
printf 'Matched:  %d hooks\n' "$MATCHED"
printf '%bPassed:   %d%b\n' "$GREEN" "$PASSED" "$RESET"
if [ "$BLOCKED" -gt 0 ]; then
    printf '%bBlocked:  %d%b\n' "$RED" "$BLOCKED" "$RESET"
else
    printf 'Blocked:  %d\n' "$BLOCKED"
fi
if [ "$WARNINGS" -gt 0 ]; then
    printf '%bWarnings: %d%b\n' "$YELLOW" "$WARNINGS" "$RESET"
else
    printf 'Warnings: %d\n' "$WARNINGS"
fi

exit $FINAL_EXIT
