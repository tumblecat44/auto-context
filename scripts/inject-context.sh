#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read hook input from stdin (can only be read once)
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')

# Source library functions
source "${SCRIPT_DIR}/lib/markers.sh"
source "${SCRIPT_DIR}/lib/tokens.sh"

# --- Data Store Initialization ---
STORE_DIR="${CWD}/.auto-context"
mkdir -p "$STORE_DIR"

# Initialize JSON data files only if they don't exist (preserve existing data)
[ -f "$STORE_DIR/conventions.json" ]   || echo '[]' > "$STORE_DIR/conventions.json"
[ -f "$STORE_DIR/candidates.json" ]    || echo '[]' > "$STORE_DIR/candidates.json"
[ -f "$STORE_DIR/anti-patterns.json" ] || echo '[]' > "$STORE_DIR/anti-patterns.json"
[ -f "$STORE_DIR/config.json" ]        || cat > "$STORE_DIR/config.json" << 'CONF'
{
  "version": "0.1.0",
  "token_budget": 1000,
  "chars_per_token": 3.0
}
CONF

# Session log: JSONL format — one JSON object per line, O(1) append
# Create if missing but never overwrite (may have current session data)
[ -f "$STORE_DIR/session-log.jsonl" ] || touch "$STORE_DIR/session-log.jsonl"

# Log session start event in JSONL format
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"session_start\",\"session_id\":\"${SESSION_ID}\",\"cwd\":\"${CWD}\"}" >> "$STORE_DIR/session-log.jsonl"

# --- Convention Injection (stub for Plan 02) ---
# Plan 01-02 will add: read conventions, format markdown, enforce token budget, inject into CLAUDE.md markers

# --- Count conventions for status ---
CONV_COUNT=$(jq 'length' "$STORE_DIR/conventions.json" 2>/dev/null || echo 0)
CAND_COUNT=$(jq 'length' "$STORE_DIR/candidates.json" 2>/dev/null || echo 0)

# Output hook response with additionalContext for Claude
cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Auto-Context: ${CONV_COUNT} conventions active, ${CAND_COUNT} candidates pending"
  }
}
EOF

exit 0
