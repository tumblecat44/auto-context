#!/usr/bin/env bash
set -euo pipefail

# SessionEnd handler: truncate session log to prevent cross-session accumulation
# Uses : > (truncate) instead of rm to keep file descriptor valid

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd')

LOG_FILE="${CWD}/.auto-context/session-log.jsonl"

if [ -f "$LOG_FILE" ]; then
  : > "$LOG_FILE"
fi

exit 0
