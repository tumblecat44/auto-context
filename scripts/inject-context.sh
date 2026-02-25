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
source "${SCRIPT_DIR}/lib/lifecycle.sh"
source "${SCRIPT_DIR}/lib/path-rules.sh"

# --- Data Store Initialization ---
STORE_DIR="${CWD}/.auto-context"
mkdir -p "$STORE_DIR"

# Initialize JSON data files only if they don't exist (preserve existing data)
[ -f "$STORE_DIR/conventions.json" ]   || echo '[]' > "$STORE_DIR/conventions.json"
[ -f "$STORE_DIR/candidates.json" ]    || echo '[]' > "$STORE_DIR/candidates.json"
[ -f "$STORE_DIR/anti-patterns.json" ] || echo '[]' > "$STORE_DIR/anti-patterns.json"
[ -f "$STORE_DIR/rewards.json" ]       || echo '[]' > "$STORE_DIR/rewards.json"
[ -f "$STORE_DIR/config.json" ]        || cat > "$STORE_DIR/config.json" << 'CONF'
{
  "version": "0.1.0",
  "token_budget": 1000,
  "chars_per_token": 3.0
}
CONF

# --- Context Restoration from PreCompact Backup ---
BACKUP_DIR="${STORE_DIR}/backup"
if [ -d "$BACKUP_DIR" ]; then
  for f in conventions.json candidates.json anti-patterns.json lifecycle.json rewards.json; do
    # Restore if primary file is empty/corrupted but backup exists and is valid
    if [ -f "$BACKUP_DIR/$f" ] && [ -s "$BACKUP_DIR/$f" ]; then
      if [ ! -s "$STORE_DIR/$f" ] || ! jq empty "$STORE_DIR/$f" 2>/dev/null; then
        cp "$BACKUP_DIR/$f" "$STORE_DIR/$f" 2>/dev/null || true
      fi
    fi
  done
  # Clean up backup directory after restore check
  rm -rf "$BACKUP_DIR" 2>/dev/null || true
fi

# --- Lifecycle Initialization ---
init_lifecycle "$STORE_DIR"

# Session log: JSONL format — one JSON object per line, O(1) append
# Create if missing but never overwrite (may have current session data)
[ -f "$STORE_DIR/session-log.jsonl" ] || touch "$STORE_DIR/session-log.jsonl"

# Safety net: clear stale session log from crashed/killed sessions
# If session-log.jsonl has entries with a different session_id, this is stale data
if [ -s "$STORE_DIR/session-log.jsonl" ]; then
  STALE_COUNT=$(jq -r --arg sid "$SESSION_ID" 'select(.session_id != $sid) | .session_id' "$STORE_DIR/session-log.jsonl" 2>/dev/null | head -1 | wc -c | tr -d ' ')
  if [ "$STALE_COUNT" -gt 1 ]; then
    : > "$STORE_DIR/session-log.jsonl"
  fi
fi

# Log session start event in JSONL format
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"session_start\",\"session_id\":\"${SESSION_ID}\",\"cwd\":\"${CWD}\"}" >> "$STORE_DIR/session-log.jsonl"

# --- Lifecycle Pipeline ---
# Increment session counter (only for new sessions, not resume/compact)
SESSION_COUNT=$(increment_session "$STORE_DIR" "$SESSION_ID")

# Migrate existing conventions/candidates that lack lifecycle fields
migrate_conventions "$STORE_DIR" "$SESSION_COUNT"

# Promote eligible candidates to review_pending
promote_candidates "$STORE_DIR"

# Decay stale conventions (not referenced in 5+ sessions)
decay_conventions "$STORE_DIR" "$SESSION_COUNT"

# --- Convention Injection into CLAUDE.md ---
CLAUDE_MD="${CWD}/CLAUDE.md"
TOKEN_BUDGET=$(jq -r '.token_budget // 1000' "$STORE_DIR/config.json" 2>/dev/null || echo 1000)

# Get active conventions filtered by stage and capped at 50 (already confidence-sorted)
ACTIVE_CONVS=$(get_active_conventions "$STORE_DIR" 50)
CONV_COUNT=$(echo "$ACTIVE_CONVS" | jq 'length')

# Update last_referenced_session for all injected conventions
if [ "$CONV_COUNT" -gt 0 ]; then
  jq --argjson sc "$SESSION_COUNT" '
    [.[] | if .stage == "active" then .last_referenced_session = $sc else . end]
  ' "$STORE_DIR/conventions.json" > "$STORE_DIR/conventions.json.tmp" \
    && mv "$STORE_DIR/conventions.json.tmp" "$STORE_DIR/conventions.json"
fi

CAND_COUNT=$(jq 'length' "$STORE_DIR/candidates.json" 2>/dev/null || echo 0)
AP_COUNT=$(jq 'length' "$STORE_DIR/anti-patterns.json" 2>/dev/null || echo 0)

# --- Anti-Pattern Injection (Phase 7) ---
AP_ACTIVE=$(jq '[.[] | select(.stage == "active")] | sort_by(-.confidence)' "$STORE_DIR/anti-patterns.json" 2>/dev/null || echo "[]")
AP_INJ_COUNT=$(echo "$AP_ACTIVE" | jq 'length')

# Build anti-pattern markdown section with 200-token sub-budget
AP_CONTENT=""
if [ "$AP_INJ_COUNT" -gt 0 ]; then
  AP_CONTENT=$(echo "$AP_ACTIVE" | jq -r '"## Do NOT (Auto-Context)\n\n" + (map("- " + .text) | join("\n"))')
  AP_CONTENT=$(enforce_budget "$AP_CONTENT" 200)
fi

# Calculate remaining budget for conventions (subtract anti-pattern tokens + 50 buffer for footer)
AP_TOKENS=$(estimate_tokens "$AP_CONTENT")
CONV_BUDGET=$((TOKEN_BUDGET - AP_TOKENS - 50))
[ "$CONV_BUDGET" -lt 100 ] && CONV_BUDGET=100  # minimum convention budget

# --- Phase 8: Path-Scoped Detection & Smart Injection ---
RULES_DIR="${CWD}/.claude/rules"

# Step 1: Clean up stale auto-context-*.md rule files
cleanup_auto_rules "$RULES_DIR"

# Step 2: Separate path-scoped vs global conventions
PATH_SCOPED="[]"
GLOBAL_CONVS="[]"
OVERFLOW="[]"

if [ "$CONV_COUNT" -gt 0 ]; then
  for i in $(seq 0 $((CONV_COUNT - 1))); do
    CONV=$(echo "$ACTIVE_CONVS" | jq ".[$i]")
    SCOPE=$(detect_path_scope "$CONV")
    if [ -n "$SCOPE" ]; then
      PATH_SCOPED=$(echo "$PATH_SCOPED" | jq --arg scope "$SCOPE" --argjson conv "$CONV" '. + [$conv + {path_scope: $scope}]')
    else
      GLOBAL_CONVS=$(echo "$GLOBAL_CONVS" | jq --argjson conv "$CONV" '. + [$conv]')
    fi
  done
fi

# Step 3: Generate path-scoped rule files
PATH_SCOPED_COUNT=$(echo "$PATH_SCOPED" | jq 'length')
if [ "$PATH_SCOPED_COUNT" -gt 0 ]; then
  mkdir -p "$RULES_DIR"
  GROUPED=$(echo "$PATH_SCOPED" | jq '[group_by(.path_scope)[] | {scope: .[0].path_scope, convs: [.[].text]}]')
  generate_rule_files "$RULES_DIR" "$GROUPED"
fi

# Step 4: Build CLAUDE.md content line-by-line with confidence-sorted budget
CONV_CONTENT=""
GLOBAL_COUNT=$(echo "$GLOBAL_CONVS" | jq 'length')
INJECTED_COUNT=0

if [ "$GLOBAL_COUNT" -gt 0 ]; then
  HEADER="## Project Conventions (Auto-Context)\n\n"
  ACCUMULATED=$(estimate_tokens "$(printf '%b' "$HEADER")")
  CONV_LINES=""

  for i in $(seq 0 $((GLOBAL_COUNT - 1))); do
    CONV_TEXT=$(echo "$GLOBAL_CONVS" | jq -r ".[$i].text")
    LINE="- ${CONV_TEXT}"
    LINE_TOKENS=$(estimate_tokens "$LINE")
    NEW_TOTAL=$((ACCUMULATED + LINE_TOKENS + 1))

    if [ "$NEW_TOTAL" -le "$CONV_BUDGET" ]; then
      CONV_LINES="${CONV_LINES}${LINE}\n"
      ACCUMULATED=$NEW_TOTAL
      INJECTED_COUNT=$((INJECTED_COUNT + 1))
    else
      # Over budget: add to overflow
      OVERFLOW=$(echo "$OVERFLOW" | jq --arg t "$CONV_TEXT" '. + [$t]')
    fi
  done

  if [ -n "$CONV_LINES" ]; then
    CONV_CONTENT="$(printf '%b' "${HEADER}${CONV_LINES}")"
  fi
fi

# Step 5: Write overflow file if any global conventions exceeded budget
OVERFLOW_COUNT=$(echo "$OVERFLOW" | jq 'length')
if [ "$OVERFLOW_COUNT" -gt 0 ]; then
  mkdir -p "$RULES_DIR"
  write_overflow_file "$RULES_DIR" "$OVERFLOW"
fi

# Step 6: Combine and inject into CLAUDE.md
FULL_CONTENT=""
[ -n "$CONV_CONTENT" ] && FULL_CONTENT="$CONV_CONTENT"
if [ -n "$AP_CONTENT" ]; then
  [ -n "$FULL_CONTENT" ] && FULL_CONTENT="${FULL_CONTENT}\n\n${AP_CONTENT}" || FULL_CONTENT="$AP_CONTENT"
fi
FOOTER="\n\n_Auto-generated by auto-context plugin. Do not edit between markers._"
if [ -n "$FULL_CONTENT" ]; then
  FULL_CONTENT="${FULL_CONTENT}${FOOTER}"
  ensure_markers "$CLAUDE_MD"
  inject_content "$CLAUDE_MD" "$(printf '%b' "$FULL_CONTENT")"
else
  ensure_markers "$CLAUDE_MD"
  inject_content "$CLAUDE_MD" "_No conventions yet. Auto-Context is learning from your sessions._"
fi

# Count review-pending candidates for user awareness
REVIEW_COUNT=$(jq '[.[] | select(.stage == "review_pending")] | length' "$STORE_DIR/candidates.json" 2>/dev/null || echo 0)

# Build status line (INJECTED_COUNT = conventions in CLAUDE.md only, not overflow/path-scoped)
TOTAL_ACTIVE=$((INJECTED_COUNT + PATH_SCOPED_COUNT + OVERFLOW_COUNT))
STATUS_LINE="Auto-Context: ${INJECTED_COUNT} conventions injected"
[ "$PATH_SCOPED_COUNT" -gt 0 ] && STATUS_LINE="${STATUS_LINE}, ${PATH_SCOPED_COUNT} path-scoped"
[ "$OVERFLOW_COUNT" -gt 0 ] && STATUS_LINE="${STATUS_LINE}, ${OVERFLOW_COUNT} overflow"
STATUS_LINE="${STATUS_LINE}, ${CAND_COUNT} candidates pending"
[ "$REVIEW_COUNT" -gt 0 ] 2>/dev/null && STATUS_LINE="${STATUS_LINE} (${REVIEW_COUNT} ready for review)"
[ "$AP_COUNT" -gt 0 ] 2>/dev/null && STATUS_LINE="${STATUS_LINE}, ${AP_COUNT} anti-patterns"

# Output hook response with additionalContext for Claude
cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "${STATUS_LINE}"
  }
}
EOF

exit 0
