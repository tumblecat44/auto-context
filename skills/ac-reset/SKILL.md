---
name: ac-reset
description: Clear all auto-context data and remove auto-generated sections from CLAUDE.md. Use to start fresh or uninstall auto-context from a project.
disable-model-invocation: true
---

# Auto-Context: Reset

Remove all auto-context state from this project. This is a destructive operation.

---

## Step 1: Confirm with User

Before proceeding, inform the user what will be deleted:
- `.auto-context/` directory (all conventions, candidates, anti-patterns, config, session logs)
- Auto-context marker section in CLAUDE.md (content between `<!-- auto-context:start -->` and `<!-- auto-context:end -->`, inclusive of the markers)

Ask: "This will permanently delete all auto-context data. Proceed?"

If the user says no, stop immediately.

---

## Step 2: Remove Data Store

Delete the `.auto-context/` directory:

```bash
rm -rf .auto-context/
```

Verify removal:
```bash
test ! -d .auto-context/ && echo "Data store removed" || echo "WARNING: .auto-context/ still exists"
```

If `.auto-context/` does not exist, report "No data store found" and continue to Step 3.

---

## Step 3: Clean CLAUDE.md

If CLAUDE.md does not exist, report "No CLAUDE.md found" and skip to Step 4.

If CLAUDE.md exists, check for auto-context markers:

```bash
grep -c -F "auto-context:" CLAUDE.md 2>/dev/null || echo "0"
```

If no markers found (count is 0), report "No auto-context markers found in CLAUDE.md" and skip to Step 4.

If markers exist, remove everything between `<!-- auto-context:start -->` and `<!-- auto-context:end -->` (inclusive):

```bash
awk '/<!-- auto-context:start -->/{skip=1; next} /<!-- auto-context:end -->/{skip=0; next} !skip{print}' CLAUDE.md > CLAUDE.md.ac-tmp && mv CLAUDE.md.ac-tmp CLAUDE.md
```

After removal, check if CLAUDE.md is empty or whitespace-only:
```bash
if [ ! -s CLAUDE.md ] || ! grep -q '[^[:space:]]' CLAUDE.md 2>/dev/null; then
  rm CLAUDE.md
  echo "CLAUDE.md was empty after cleanup -- removed"
fi
```

If CLAUDE.md still has user content, keep it.

Verify no orphaned markers remain:
```bash
grep -c -F "auto-context:" CLAUDE.md 2>/dev/null || echo "0"
```

If orphaned markers remain (corrupted state), remove any lines containing the marker patterns:
```bash
grep -v -F "auto-context:start" CLAUDE.md | grep -v -F "auto-context:end" > CLAUDE.md.ac-tmp && mv CLAUDE.md.ac-tmp CLAUDE.md
```

---

## Step 4: Report Results

Tell the user what was cleaned:
- Whether `.auto-context/` was found and removed (or was already absent)
- Whether CLAUDE.md was modified (marker section removed, file deleted, or no markers found)
- Suggest: "Run `/auto-context:ac-init` to re-bootstrap if desired"
