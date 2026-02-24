#!/usr/bin/env bash
set -euo pipefail

# PostToolUse / PostToolUseFailure observation handler
# Appends structured JSONL entries to session-log.jsonl for Write/Edit/Bash events
# Performance target: <100ms (single jq invocation for field extraction)

INPUT=$(cat)

# Extract all common fields in ONE jq call (avoid multiple process spawns)
IFS=$'\t' read -r TOOL_NAME SESSION_ID CWD HOOK_EVENT <<< "$(echo "$INPUT" | jq -r '[.tool_name, .session_id, .cwd, .hook_event_name] | @tsv')"

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
STORE_DIR="${CWD}/.auto-context"
LOG_FILE="${STORE_DIR}/session-log.jsonl"

# Safety net: ensure store dir and log file exist (in case SessionStart did not run)
[ -d "$STORE_DIR" ] || mkdir -p "$STORE_DIR"
[ -f "$LOG_FILE" ] || touch "$LOG_FILE"

# Handle PostToolUseFailure first
if [ "$HOOK_EVENT" = "PostToolUseFailure" ]; then
  echo "$INPUT" | jq -c --arg ts "$TS" '{ts:$ts, event:"bash_error", tool:"Bash", command:(.tool_input.command // "" | .[0:200]), error:(.error // "" | .[0:200]), session_id:.session_id}' >> "$LOG_FILE"
  exit 0
fi

# Handle PostToolUse events by tool name
case "$TOOL_NAME" in
  Write)
    echo "$INPUT" | jq -c --arg ts "$TS" '{ts:$ts, event:"file_write", tool:"Write", file:.tool_input.file_path, session_id:.session_id}' >> "$LOG_FILE"
    ;;
  Edit)
    echo "$INPUT" | jq -c --arg ts "$TS" '{ts:$ts, event:"file_edit", tool:"Edit", file:.tool_input.file_path, session_id:.session_id}' >> "$LOG_FILE"
    ;;
  Bash)
    echo "$INPUT" | jq -c --arg ts "$TS" '{ts:$ts, event:"bash_command", tool:"Bash", command:(.tool_input.command // "" | .[0:200]), session_id:.session_id}' >> "$LOG_FILE"
    ;;
esac

exit 0
