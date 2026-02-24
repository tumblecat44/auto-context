#!/usr/bin/env bash
# Convention lifecycle management for auto-context
# Provides: init_lifecycle, increment_session, migrate_conventions, promote_candidates,
#           decay_conventions, get_active_conventions, log_changelog

# log_changelog(store_dir, action, text, reason, from_stage, to_stage)
# Append a single JSONL entry to changelog.jsonl
log_changelog() {
  local store_dir="$1" action="$2" text="$3" reason="$4" from_stage="$5" to_stage="$6"
  jq -nc \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg action "$action" \
    --arg text "$text" \
    --arg reason "$reason" \
    --arg from "$from_stage" \
    --arg to "$to_stage" \
    '{ts:$ts, action:$action, text:$text, reason:$reason, from_stage:$from, to_stage:$to}' \
    >> "$store_dir/changelog.jsonl"
}

# init_lifecycle(store_dir)
# Initialize lifecycle.json and changelog.jsonl if missing
init_lifecycle() {
  local store_dir="$1"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  if [ ! -f "$store_dir/lifecycle.json" ]; then
    jq -nc \
      --arg ts "$ts" \
      '{session_count:0, last_session_id:"", last_promotion_check:0, last_decay_check:0, created_at:$ts, updated_at:$ts}' \
      > "$store_dir/lifecycle.json"
  fi

  [ -f "$store_dir/changelog.jsonl" ] || touch "$store_dir/changelog.jsonl"
}

# increment_session(store_dir, session_id)
# Increment session counter for new sessions (skip for resume/compact)
# Echoes the new session_count to stdout
increment_session() {
  local store_dir="$1" session_id="$2"

  local last_sid
  last_sid=$(jq -r '.last_session_id // ""' "$store_dir/lifecycle.json" 2>/dev/null || echo "")

  # Same session (resume/compact) -- return current count without incrementing
  if [ "$session_id" = "$last_sid" ]; then
    jq -r '.session_count // 0' "$store_dir/lifecycle.json" 2>/dev/null || echo 0
    return 0
  fi

  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Increment and update atomically
  jq --arg sid "$session_id" --arg ts "$ts" '
    .session_count = (.session_count // 0) + 1 |
    .last_session_id = $sid |
    .updated_at = $ts
  ' "$store_dir/lifecycle.json" > "$store_dir/lifecycle.json.tmp" \
    && mv "$store_dir/lifecycle.json.tmp" "$store_dir/lifecycle.json"

  jq -r '.session_count' "$store_dir/lifecycle.json" 2>/dev/null || echo 1
}

# migrate_conventions(store_dir, session_count)
# Add stage and last_referenced_session to entries missing them (backward compat)
migrate_conventions() {
  local store_dir="$1" session_count="$2"

  # Migrate conventions.json
  if [ -f "$store_dir/conventions.json" ] && [ -s "$store_dir/conventions.json" ]; then
    local needs_migration
    needs_migration=$(jq '[.[] | select(.stage == null or .last_referenced_session == null)] | length' "$store_dir/conventions.json" 2>/dev/null || echo 0)
    if [ "$needs_migration" -gt 0 ]; then
      jq --argjson sc "$session_count" '
        [.[] | if .stage then . else . + {"stage":"active"} end |
               if .last_referenced_session != null then . else . + {"last_referenced_session":$sc} end]
      ' "$store_dir/conventions.json" > "$store_dir/conventions.json.tmp" \
        && mv "$store_dir/conventions.json.tmp" "$store_dir/conventions.json"
    fi
  fi

  # Migrate candidates.json
  if [ -f "$store_dir/candidates.json" ] && [ -s "$store_dir/candidates.json" ]; then
    local needs_cand_migration
    needs_cand_migration=$(jq '[.[] | select(.stage == null)] | length' "$store_dir/candidates.json" 2>/dev/null || echo 0)
    if [ "$needs_cand_migration" -gt 0 ]; then
      jq '
        [.[] | if .stage then . else . + {"stage":"observation"} end]
      ' "$store_dir/candidates.json" > "$store_dir/candidates.json.tmp" \
        && mv "$store_dir/candidates.json.tmp" "$store_dir/candidates.json"
    fi
  fi
}

# promote_candidates(store_dir)
# Promote observation-stage candidates with 3+ observations across 2+ sessions to review_pending
promote_candidates() {
  local store_dir="$1"

  [ -f "$store_dir/candidates.json" ] && [ -s "$store_dir/candidates.json" ] || return 0

  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Find candidates eligible for promotion
  local eligible
  eligible=$(jq '
    [.[] | select(
      (.stage // "observation") == "observation" and
      (.observations // 0) >= 3 and
      ((.sessions_seen // []) | length) >= 2
    )]
  ' "$store_dir/candidates.json" 2>/dev/null || echo "[]")

  local eligible_count
  eligible_count=$(echo "$eligible" | jq 'length')

  [ "$eligible_count" -gt 0 ] || return 0

  # Update candidates: set stage to review_pending for eligible ones
  jq --arg ts "$ts" '
    [.[] |
      if (.stage // "observation") == "observation" and
         (.observations // 0) >= 3 and
         ((.sessions_seen // []) | length) >= 2
      then . + {"stage":"review_pending", "promoted_at":$ts}
      else .
      end]
  ' "$store_dir/candidates.json" > "$store_dir/candidates.json.tmp" \
    && mv "$store_dir/candidates.json.tmp" "$store_dir/candidates.json"

  # Log each promotion to changelog
  echo "$eligible" | jq -r '.[].text' | while IFS= read -r text; do
    log_changelog "$store_dir" "promoted" "$text" "3+ observations across 2+ sessions" "observation" "review_pending"
  done
}

# decay_conventions(store_dir, session_count)
# Mark active conventions as decayed if not referenced in 5+ sessions
decay_conventions() {
  local store_dir="$1" session_count="$2"

  [ -f "$store_dir/conventions.json" ] && [ -s "$store_dir/conventions.json" ] || return 0

  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Find conventions eligible for decay
  local decayable
  decayable=$(jq --argjson sc "$session_count" '
    [.[] | select(
      .stage == "active" and
      (.last_referenced_session // 0) > 0 and
      ($sc - (.last_referenced_session // 0)) >= 5
    )]
  ' "$store_dir/conventions.json" 2>/dev/null || echo "[]")

  local decay_count
  decay_count=$(echo "$decayable" | jq 'length')

  [ "$decay_count" -gt 0 ] || return 0

  # Update conventions: mark decayed
  jq --argjson sc "$session_count" --arg ts "$ts" '
    [.[] |
      if .stage == "active" and
         (.last_referenced_session // 0) > 0 and
         ($sc - (.last_referenced_session // 0)) >= 5
      then . + {"stage":"decayed", "decayed_at":$ts}
      else .
      end]
  ' "$store_dir/conventions.json" > "$store_dir/conventions.json.tmp" \
    && mv "$store_dir/conventions.json.tmp" "$store_dir/conventions.json"

  # Log each decay to changelog
  echo "$decayable" | jq -r '.[] | "\(.text)\t\(.last_referenced_session // 0)"' | while IFS=$'\t' read -r text last_ref; do
    log_changelog "$store_dir" "decayed" "$text" "not referenced since session $last_ref (current: $session_count)" "active" "decayed"
  done
}

# get_active_conventions(store_dir, max_count)
# Output JSON array of active conventions sorted by confidence, capped at max_count
get_active_conventions() {
  local store_dir="$1" max_count="${2:-50}"

  [ -f "$store_dir/conventions.json" ] && [ -s "$store_dir/conventions.json" ] || { echo "[]"; return 0; }

  local all_active
  all_active=$(jq '[.[] | select(.stage == "active")] | sort_by(-.confidence)' "$store_dir/conventions.json" 2>/dev/null || echo "[]")

  local active_count
  active_count=$(echo "$all_active" | jq 'length')

  # If within cap, return all
  if [ "$active_count" -le "$max_count" ]; then
    echo "$all_active"
    return 0
  fi

  # Over cap: log evictions for entries beyond max_count
  local evicted
  evicted=$(echo "$all_active" | jq --argjson mc "$max_count" '.[$mc:]')
  echo "$evicted" | jq -r '.[].text' | while IFS= read -r text; do
    log_changelog "$store_dir" "evicted" "$text" "exceeded 50-convention cap (lowest confidence)" "active" "evicted"
  done

  # Return capped list
  echo "$all_active" | jq --argjson mc "$max_count" '.[:$mc]'
}
