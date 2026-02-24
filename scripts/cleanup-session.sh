#!/usr/bin/env bash
set -euo pipefail

# SessionEnd handler: truncate session log to prevent cross-session accumulation
# Uses : > (truncate) instead of rm to keep file descriptor valid

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd')

LOG_FILE="${CWD}/.auto-context/session-log.jsonl"

if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
  # Archive for Stop hook extraction safety (Phase 5)
  cp "$LOG_FILE" "${LOG_FILE}.prev" 2>/dev/null || true
  : > "$LOG_FILE"
fi

exit 0
