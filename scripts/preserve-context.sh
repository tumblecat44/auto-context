#!/usr/bin/env bash
set -euo pipefail

# PreCompact hook: back up critical JSON data files before context compaction.
# PreCompact only supports type:"command" (no agent or prompt hooks).
# This hook cannot block compaction -- it just creates a safety backup.

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd')

STORE_DIR="${CWD}/.auto-context"
BACKUP_DIR="${STORE_DIR}/backup"

# Only back up if store exists
[ -d "$STORE_DIR" ] || exit 0

mkdir -p "$BACKUP_DIR"

# Back up critical data files (silently skip missing files)
for f in conventions.json candidates.json anti-patterns.json lifecycle.json; do
  [ -f "$STORE_DIR/$f" ] && cp "$STORE_DIR/$f" "$BACKUP_DIR/$f" 2>/dev/null || true
done

exit 0
