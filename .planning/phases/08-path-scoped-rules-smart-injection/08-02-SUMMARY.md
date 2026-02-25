# Plan 08-02 Summary: Path-Scoped Rules & Smart Injection

**Status:** Complete
**Date:** 2026-02-25

## What Was Built

### scripts/lib/path-rules.sh (new, 131 lines)
- `detect_path_scope(conv_json)`: Returns glob pattern if convention is path-scoped (ALL evidence files share common dir prefix at depth >= 2). Skips bootstrap conventions and those with < 3 evidence files. Returns empty string for global conventions.
- `generate_rule_files(rules_dir, grouped_convs_json)`: Writes `.claude/rules/auto-context-{dirname}.md` files with `paths:` YAML frontmatter. Groups conventions by path scope, caps at 5 rule files (excess merges to overflow).
- `write_overflow_file(rules_dir, overflow_texts_json)`: Writes `auto-context-overflow.md` without `paths:` frontmatter (global) for conventions that exceeded the CLAUDE.md budget.
- `cleanup_auto_rules(rules_dir)`: Removes all `auto-context-*.md` files. Only touches auto-context prefixed files.

### scripts/inject-context.sh (modified)
Injection pipeline rewritten from bulk truncation to smart confidence-weighted pipeline:

1. **Source path-rules.sh** alongside existing libraries
2. **Anti-pattern section**: Unchanged (200-token sub-budget with enforce_budget)
3. **Path-scoped detection**: Loop through active conventions, call detect_path_scope for each, separate into PATH_SCOPED vs GLOBAL_CONVS arrays
4. **Rule file generation**: cleanup old auto-context-*.md, group path-scoped conventions by scope, generate rule files
5. **Line-by-line budget building**: Iterate global conventions in confidence order, estimate tokens per line, add to CLAUDE.md content until budget reached, route remainder to overflow
6. **Overflow handling**: Write auto-context-overflow.md for global conventions that exceeded budget
7. **Status line updated**: Shows injected count, path-scoped count, overflow count separately

**Key invariant maintained:** No convention appears in both CLAUDE.md and .claude/rules/

## Preserved Logic
- Data store initialization (lines 1-65): NO CHANGES
- Lifecycle pipeline (increment_session, migrate, promote, decay): NO CHANGES
- Anti-pattern section: NO CHANGES (same 200-token sub-budget)
- Hook response output: Same JSON structure, updated status line

## Verification
- `bash -n scripts/lib/path-rules.sh` passes
- `bash -n scripts/inject-context.sh` passes
- All 4 path-rules.sh functions referenced in inject-context.sh
- estimate_tokens used for line-by-line budget accounting
- No changes to hooks.json, observe-tool.sh, or other existing scripts
