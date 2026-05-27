#!/bin/bash
# =============================================================================
# Pre-Hook 3: Commit Message Validator
# Purpose:    Validate git commit messages follow conventional commit format.
#             Suggests a prefix if one is missing based on staged diff heuristics.
# Input:      JSON on stdin: {"tool_name":"Bash","tool_input":{"command":"..."},...}
# Exit codes: 0 = allow, 2 = block (invalid commit message)
# =============================================================================
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_FILE="$HOOK_DIR/config/commit_prefixes.txt"

# Read entire JSON input from stdin
INPUT="$(cat)"

# Extract command from tool_input
TOOL_COMMAND="$(printf '%s' "$INPUT" | grep -oE '"command":"([^"\\]|\\.)*"' | head -1 | sed 's/^"command":"//; s/"$//')"

# if commad doesnt contain "git commit", we exit 0
if ! echo "$TOOL_COMMAND" | grep -q "git commit"; then
    exit 0
fi

# if command doesnt contain -m flag than we exit 0
if ! echo "$TOOL_COMMAND" | grep -qE -- "-(a\s*)?m\s+"; then
    exit 0
fi

# Extract the commit message
COMMIT_MESSAGE="$(echo "$TOOL_COMMAND" | sed -E 's/.*-[a-z]*m\s+//' | sed -E "s/^['\"]//; s/['\"]$//")"

# load valid prefixes from state file
PREFIXES=$(cat "$STATE_FILE" | tr '\n' '|' | sed 's/|$//')
REGEX="($PREFIXES): "


# CHECK 1
# we check if the commit massage start with one of the valid prefixes
# if not, we block the commit and suggest a prefix based on the staged diff heuristics.
if ! echo "$COMMIT_MESSAGE" | grep -qE "^$REGEX"; then
    STAT_OUTPUT=$(git diff --cached --stat 2>/dev/null)
    NAME_STATUS_OUTPUT=$(git diff --cached --name-status 2>/dev/null)


    if echo "$NAME_STATUS_OUTPUT" | grep -qEi 'test|spec'; then
        SUGGESTION="test"
    elif echo "$NAME_STATUS_OUTPUT" | grep -qEi 'readme|\.md'; then
        SUGGESTION="docs"
    elif echo "$NAME_STATUS_OUTPUT" | grep -qE '^A[[:space:]]'; then
        SUGGESTION="feat"
    else

        INSERTIONS=$(echo "$STAT_OUTPUT" | tail -n 1 | grep -oE '[0-9]+ insertion' | awk '{print $1}')
        DELETIONS=$(echo "$STAT_OUTPUT" | tail -n 1 | grep -oE '[0-9]+ deletion' | awk '{print $1}')

        INSERTIONS=${INSERTIONS:-0}
        DELETIONS=${DELETIONS:-0}

        if [ "$DELETIONS" -gt "$INSERTIONS" ]; then
            SUGGESTION="refactor"
        else

            SUGGESTION="feat"
        fi
    fi

    echo "BLOCKED: Missing commit prefix. Based on your changes, try: '${SUGGESTION}: ${COMMIT_MESSAGE}'. Valid prefixes: feat, fix, docs, refactor, test, chore" >&2
    exit 2
fi

#CHECK 2
# we check that the massge is 10-72 characters long
MESSAGE_LENGTH=${#COMMIT_MESSAGE}
if [ "$MESSAGE_LENGTH" -lt 10 ] || [ "$MESSAGE_LENGTH" -gt 72 ]; then
    echo "BLOCKED: Message length must be between 10 and 72 characters." >&2
    exit 2
fi

# CHECK 3
# we check that the message does not end with a period
if echo "$COMMIT_MESSAGE" | grep -q "\.$"; then
    echo "BLOCKED: Message must not end with a period." >&2
    exit 2
fi


exit 0
