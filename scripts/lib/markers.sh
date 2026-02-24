#!/usr/bin/env bash
# Marker section management for CLAUDE.md
# Provides: has_markers, validate_markers, ensure_markers, inject_content

MARKER_START="<!-- auto-context:start -->"
MARKER_END="<!-- auto-context:end -->"

# _count_marker(file, pattern) - Safely count occurrences of pattern in file
# Returns a clean integer (handles grep edge cases on macOS)
_count_marker() {
  local file="$1"
  local pattern="$2"
  grep -c -F "$pattern" "$file" 2>/dev/null | head -1 || echo 0
}

# has_markers(file) - Returns 0 if both start and end markers exist, 1 otherwise
has_markers() {
  local file="$1"
  [ -f "$file" ] || return 1
  local start_count end_count
  start_count=$(_count_marker "$file" "$MARKER_START")
  end_count=$(_count_marker "$file" "$MARKER_END")
  [ "$start_count" -gt 0 ] && [ "$end_count" -gt 0 ] && return 0
  return 1
}

# validate_markers(file) - Check marker integrity
# Returns: "valid" (exit 0), "missing_file"/"missing_both"/"corrupted" (exit 1)
validate_markers() {
  local file="$1"

  if [ ! -f "$file" ]; then
    echo "missing_file"
    return 1
  fi

  local start_count end_count
  start_count=$(_count_marker "$file" "$MARKER_START")
  end_count=$(_count_marker "$file" "$MARKER_END")

  # No markers at all
  if [ "$start_count" -eq 0 ] && [ "$end_count" -eq 0 ]; then
    echo "missing_both"
    return 1
  fi

  # Exactly one of each - check ordering
  if [ "$start_count" -eq 1 ] && [ "$end_count" -eq 1 ]; then
    local start_line end_line
    start_line=$(grep -n -F "$MARKER_START" "$file" | head -1 | cut -d: -f1)
    end_line=$(grep -n -F "$MARKER_END" "$file" | head -1 | cut -d: -f1)
    if [ "$start_line" -lt "$end_line" ]; then
      echo "valid"
      return 0
    fi
  fi

  # Any other state: duplicates, reversed, orphaned
  echo "corrupted"
  return 1
}

# ensure_markers(file) - Guarantee valid markers exist
ensure_markers() {
  local file="$1"
  local status

  # File doesn't exist: create with just markers
  if [ ! -f "$file" ]; then
    printf '%s\n%s\n' "$MARKER_START" "$MARKER_END" > "$file"
    # Verify fix
    status=$(validate_markers "$file")
    if [ "$status" != "valid" ]; then
      echo "ERROR: ensure_markers failed to create valid markers" >&2
      return 1
    fi
    return 0
  fi

  status=$(validate_markers "$file") || true

  case "$status" in
    valid)
      # Already valid, nothing to do
      return 0
      ;;
    missing_both)
      # Append markers at end of file
      printf '\n%s\n%s\n' "$MARKER_START" "$MARKER_END" >> "$file"
      ;;
    *)
      # Corrupted: remove ALL existing markers, then append fresh pair
      local tmpfile="${file}.ac-tmp"
      grep -v -F "$MARKER_START" "$file" | grep -v -F "$MARKER_END" > "$tmpfile" || true
      mv "$tmpfile" "$file"
      printf '\n%s\n%s\n' "$MARKER_START" "$MARKER_END" >> "$file"
      ;;
  esac

  # Always verify the repair worked
  status=$(validate_markers "$file")
  if [ "$status" != "valid" ]; then
    echo "ERROR: ensure_markers failed to repair markers (status: $status)" >&2
    return 1
  fi
  return 0
}

# inject_content(file, content) - Replace everything between markers with new content
# Uses awk (NOT sed -i) for macOS/Linux compatibility
inject_content() {
  local file="$1"
  local content="$2"
  local tmpfile="${file}.ac-tmp"

  awk -v marker_start="$MARKER_START" -v marker_end="$MARKER_END" -v new_content="$content" '
    $0 == marker_start {
      print
      print new_content
      skip = 1
      next
    }
    $0 == marker_end {
      print
      skip = 0
      next
    }
    !skip { print }
  ' "$file" > "$tmpfile"

  mv "$tmpfile" "$file"
}
