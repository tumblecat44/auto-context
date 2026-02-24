#!/usr/bin/env bash
set -euo pipefail

# UserPromptSubmit hook: detects explicit feedback phrases and persists
# conventions (positive) or anti-patterns (negative) to the data store.
# Performance: <10ms for non-feedback prompts (fast exit path)

INPUT=$(cat)

# Extract prompt and common fields in one jq call (same pattern as observe-tool.sh)
IFS=$'\t' read -r PROMPT SESSION_ID CWD <<< "$(echo "$INPUT" | jq -r '[.prompt, .session_id, .cwd] | @tsv')"

# Quick exit if prompt is too short to contain feedback
[ ${#PROMPT} -lt 5 ] && exit 0

STORE_DIR="${CWD}/.auto-context"

# Safety net: ensure store exists (in case SessionStart didn't run)
[ -d "$STORE_DIR" ] || mkdir -p "$STORE_DIR"
[ -f "$STORE_DIR/conventions.json" ] || echo '[]' > "$STORE_DIR/conventions.json"
[ -f "$STORE_DIR/anti-patterns.json" ] || echo '[]' > "$STORE_DIR/anti-patterns.json"

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Lowercase prompt for case-insensitive English matching
PROMPT_LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

FEEDBACK_TYPE=""

# Check NEGATIVE patterns first (more specific, avoids false positive overlap)
# English: "don't do/use", "never do/use", "stop doing/using", "avoid ..."
# Korean: "하지 마", "하지마", "쓰지 마", "쓰지마"
if echo "$PROMPT_LOWER" | grep -qE "(don'?t (do|use|ever)|never (do|use)|stop (doing|using)|avoid )" || \
   echo "$PROMPT" | grep -qF "하지 마" || echo "$PROMPT" | grep -qF "하지마" || \
   echo "$PROMPT" | grep -qF "쓰지 마" || echo "$PROMPT" | grep -qF "쓰지마"; then
  FEEDBACK_TYPE="anti-pattern"

# Check POSITIVE patterns
# English: "remember this/that/:", "always do/use", "from now on"
# Korean: "기억해", "앞으로"
elif echo "$PROMPT_LOWER" | grep -qE "(remember( this| that|:)|always (do|use)|from now on)" || \
     echo "$PROMPT" | grep -qF "기억해" || echo "$PROMPT" | grep -qF "앞으로"; then
  FEEDBACK_TYPE="convention"
fi

# No feedback detected -- exit silently (fast path)
[ -z "$FEEDBACK_TYPE" ] && exit 0

# --- Extract instruction content ---
# Strategy: if prompt contains ':', take everything after first colon (common pattern).
# Otherwise, strip known trigger phrases from lowercased prompt (macOS sed compat).
# Fallback: use full prompt if extraction produces empty string.
INSTRUCTION=""
if echo "$PROMPT" | grep -q ':'; then
  INSTRUCTION=$(echo "$PROMPT" | sed 's/^[^:]*: *//')
elif [ "$FEEDBACK_TYPE" = "anti-pattern" ]; then
  INSTRUCTION=$(echo "$PROMPT_LOWER" | sed -E "s/^.*(don'?t (do|use)|never (do|use)|stop (doing|using)|avoid |하지 ?마|쓰지 ?마) *//")
else
  INSTRUCTION=$(echo "$PROMPT_LOWER" | sed -E "s/^.*(remember( this| that)?:?|always (do|use)|from now on|기억해 ?줘?|기억해|앞으로) *//")
fi

# Trim whitespace, limit to 500 chars
INSTRUCTION=$(echo "$INSTRUCTION" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | head -c 500)

# Fallback: if extraction produced empty string, use full prompt
[ -z "$INSTRUCTION" ] && INSTRUCTION="$PROMPT"

# --- Write to appropriate data store ---
if [ "$FEEDBACK_TYPE" = "convention" ]; then
  TARGET_FILE="$STORE_DIR/conventions.json"
  LABEL="convention"
else
  TARGET_FILE="$STORE_DIR/anti-patterns.json"
  LABEL="anti-pattern"
fi

# Atomic JSON append: write to tmp then mv (prevents corruption from concurrent writes)
jq --arg text "$INSTRUCTION" --arg ts "$TS" --arg sid "$SESSION_ID" \
  '. + [{"text": $text, "confidence": 1.0, "source": "explicit", "created_at": $ts, "session_id": $sid, "stage": "active", "last_referenced_session": 0}]' \
  "$TARGET_FILE" > "$TARGET_FILE.tmp" && mv "$TARGET_FILE.tmp" "$TARGET_FILE"

# Log explicit feedback event to session log for Phase 5 visibility
LOG_FILE="$STORE_DIR/session-log.jsonl"
[ -f "$LOG_FILE" ] || touch "$LOG_FILE"
jq -nc --arg ts "$TS" --arg type "$LABEL" --arg text "$INSTRUCTION" --arg sid "$SESSION_ID" \
  '{ts:$ts, event:"explicit_feedback", type:$type, text:$text, session_id:$sid}' >> "$LOG_FILE"

# Return additionalContext confirming capture to Claude
cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "Auto-Context captured explicit ${LABEL}: ${INSTRUCTION}"
  }
}
EOF

exit 0
