#!/usr/bin/env bash
# File co-change relationship tracking for auto-context
# Provides: extract_git_cochanges, merge_session_cochanges

# extract_git_cochanges(store_dir, max_commits)
# Analyze git log and write co-change pairs to file-relations.json
# Gracefully skips non-git repos (returns 0)
extract_git_cochanges() {
  local store_dir="$1" max_commits="${2:-100}"

  # Guard: must be a git repo
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Extract per-commit file lists as tab-separated blocks
  # Output: one line per commit, files tab-separated
  local commit_files
  commit_files=$(git log --name-only --pretty=format:"---" -"$max_commits" 2>/dev/null | \
    awk '/^---$/{if(block) print block; block=""; next} NF>0{block = block ? block "\t" $0 : $0} END{if(block) print block}')

  [ -z "$commit_files" ] && return 0

  # Build pairs JSON from each commit block using jq
  local pairs_json="[]"
  while IFS= read -r line; do
    [ -z "$line" ] && continue

    # Count files in this commit (tab-separated)
    local file_count
    file_count=$(echo "$line" | awk -F'\t' '{print NF}')

    # Skip single-file commits (no pairs) and large commits (>20 files = merge/bulk noise)
    [ "$file_count" -lt 2 ] && continue
    [ "$file_count" -gt 20 ] && continue

    # Generate canonical pairs (file_a < file_b) with jq
    local file_pairs
    file_pairs=$(echo "$line" | jq -Rc '
      split("\t") | . as $files |
      [range(length)] | [combinations(2)] |
      map(select(.[0] < .[1])) |
      map({files: [$files[.[0]], $files[.[1]]], count: 1})
    ' 2>/dev/null || echo "[]")

    pairs_json=$(echo "$pairs_json" "$file_pairs" | jq -s '.[0] + .[1]')
  done <<< "$commit_files"

  # Aggregate: merge duplicate pairs, sum counts
  local aggregated
  aggregated=$(echo "$pairs_json" | jq --arg ts "$ts" '
    group_by(.files) |
    map({
      files: .[0].files,
      count: ([.[].count] | add),
      sources: ["git"],
      last_seen: $ts
    }) |
    sort_by(-.count) |
    .[:500]
  ')

  # Write to file-relations.json (merge with existing session data)
  local relations_file="$store_dir/file-relations.json"
  if [ -f "$relations_file" ] && [ -s "$relations_file" ]; then
    # Merge: keep session-sourced pairs, replace git-sourced
    local existing_session
    existing_session=$(jq '[.pairs[] | select(.sources | index("session"))]' "$relations_file" 2>/dev/null || echo "[]")
    jq -nc --argjson git "$aggregated" --argjson session "$existing_session" --arg ts "$ts" --argjson mc "$max_commits" '
    {
      version: 1,
      updated_at: $ts,
      git_commits_analyzed: $mc,
      pairs: ($git + $session | group_by(.files) | map({
        files: .[0].files,
        count: ([.[].count] | add),
        sources: ([.[].sources[]] | unique),
        last_seen: $ts
      }) | sort_by(-.count) | .[:500])
    }' > "$relations_file.tmp" && mv "$relations_file.tmp" "$relations_file"
  else
    jq -nc --argjson pairs "$aggregated" --arg ts "$ts" --argjson mc "$max_commits" '
    {
      version: 1,
      updated_at: $ts,
      git_commits_analyzed: $mc,
      pairs: $pairs
    }' > "$relations_file"
  fi
}

# merge_session_cochanges(store_dir, file_pairs_json)
# Takes a JSON array of {"files": [a, b]} pairs from session tracking
# Merges into existing file-relations.json, incrementing counts for existing pairs
merge_session_cochanges() {
  local store_dir="$1" file_pairs_json="$2"

  local pair_count
  pair_count=$(echo "$file_pairs_json" | jq 'length' 2>/dev/null || echo 0)
  [ "$pair_count" -eq 0 ] && return 0

  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  local relations_file="$store_dir/file-relations.json"

  # Initialize if missing
  if [ ! -f "$relations_file" ] || [ ! -s "$relations_file" ]; then
    jq -nc --argjson pairs "$file_pairs_json" --arg ts "$ts" '
    {
      version: 1,
      updated_at: $ts,
      git_commits_analyzed: 0,
      pairs: [$pairs[] | . + {count: 1, sources: ["session"], last_seen: $ts}]
    }' > "$relations_file"
    return 0
  fi

  # Read existing, merge session pairs
  jq --argjson new_pairs "$file_pairs_json" --arg ts "$ts" '
    .updated_at = $ts |
    .pairs as $existing |
    ($new_pairs | map(. + {count: 1, sources: ["session"], last_seen: $ts})) as $session |
    .pairs = ($existing + $session |
      group_by(.files) |
      map({
        files: .[0].files,
        count: ([.[].count] | add),
        sources: ([.[].sources[]] | unique),
        last_seen: $ts
      }) |
      sort_by(-.count) |
      .[:500])
  ' "$relations_file" > "$relations_file.tmp" && mv "$relations_file.tmp" "$relations_file"
}
