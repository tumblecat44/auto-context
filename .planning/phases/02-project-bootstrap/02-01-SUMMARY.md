---
phase: 02-project-bootstrap
plan: 01
subsystem: skills
tags: [bash, jq, claude-code-skill, project-scanning, convention-generation]

# Dependency graph
requires:
  - phase: 01-plugin-skeleton-injection/01
    provides: Plugin scaffold, inject-context.sh, data store init
  - phase: 01-plugin-skeleton-injection/02
    provides: Marker injection pipeline, token budget enforcement
provides:
  - /auto-context:ac-init skill with multi-step project scanning instructions
  - discover-commands.sh for deterministic build/test/lint extraction
  - Convention generation pipeline writing to .auto-context/conventions.json
affects: [02-02]

# Tech tracking
tech-stack:
  added: []
  patterns: [prompt-driven-scanning-skill, deterministic-script-augmentation, convention-merge-by-source]

key-files:
  created:
    - skills/ac-init/SKILL.md
    - skills/ac-init/scripts/discover-commands.sh
  modified: []

key-decisions:
  - "SKILL.md as prompt-driven scanning (not shell-script scanning) -- leverages Claude's reasoning for pattern detection"
  - "discover-commands.sh handles deterministic extraction, SKILL.md handles pattern recognition"
  - "Bootstrap conventions scored 0.6-0.9 with source: 'bootstrap' for later lifecycle management"
  - "Merge strategy: preserve non-bootstrap conventions, replace bootstrap ones on re-run"

patterns-established:
  - "Skills use SKILL.md with disable-model-invocation: true for user-initiated actions"
  - "Bundled scripts referenced via ${CLAUDE_PLUGIN_ROOT}/skills/<name>/scripts/"
  - "Convention format: {text, confidence, source, created_at, observed_in}"
  - "7-step scanning pattern: init -> detect -> discover -> git -> sample -> synthesize -> inject"

requirements-completed: [BOOT-01, BOOT-02, BOOT-03]

# Metrics
duration: 4min
completed: 2026-02-25
---

# Phase 2 Plan 01: ac-init Skill Summary

**Project bootstrap skill with deep scanning instructions and deterministic command extraction**

## Performance

- **Duration:** 4 min
- **Tasks:** 2
- **Files created:** 2

## Accomplishments
- discover-commands.sh extracts commands from package.json (categorized build/test/lint/dev), Makefile targets, pyproject.toml tools, and Cargo.toml crate info
- Script outputs structured JSON, handles all missing config files gracefully (null values, exit 0)
- SKILL.md contains 7-step scanning instructions covering structure, config, git history, source sampling, and convention synthesis
- Scanning goes deeper than /init: naming conventions, testing patterns, architecture patterns, error handling, import style
- Convention output format matches Phase 1 schema with added source/created_at/observed_in fields
- Skill integrates with Phase 1 injection pipeline (writes conventions.json, calls inject-context.sh)

## Task Commits

1. **Task 1: Create discover-commands.sh** - `a4d2324` (feat)
2. **Task 2: Create ac-init SKILL.md** - `825027a` (feat)

## Files Created
- `skills/ac-init/SKILL.md` - 185-line multi-step scanning instructions with YAML frontmatter
- `skills/ac-init/scripts/discover-commands.sh` - 140-line executable script for command extraction

## Deviations from Plan

None - plan executed as written.

## Issues Encountered

None

## Self-Check: PASSED

Both files verified present. discover-commands.sh produces valid JSON (tested). SKILL.md has correct frontmatter and references discover-commands.sh and inject-context.sh correctly.

---
*Phase: 02-project-bootstrap*
*Completed: 2026-02-25*
