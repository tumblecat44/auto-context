#!/usr/bin/env bash
# Token budget enforcement for auto-context
# Provides: estimate_tokens, enforce_budget

# estimate_tokens(text) - Estimate token count from text
# Uses conservative chars_per_token=3.0 (safe for Korean/CJK)
estimate_tokens() {
  local text="$1"
  local char_count=${#text}
  echo $(( char_count / 3 ))
}

# enforce_budget(content, max_tokens) - Truncate content to fit within token budget
# Returns content as-is if within budget, truncated with indicator if over
enforce_budget() {
  local content="$1"
  local max_tokens="$2"
  local max_chars=$(( max_tokens * 3 ))

  if [ ${#content} -le "$max_chars" ]; then
    echo "$content"
    return 0
  fi

  # Truncate to max_chars and append indicator
  local truncated="${content:0:$max_chars}"
  printf '%s\n\n_[truncated to fit token budget]_' "$truncated"
}
