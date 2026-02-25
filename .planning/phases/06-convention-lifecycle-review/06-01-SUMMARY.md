---
phase: 06-convention-lifecycle-review
plan: 01
subsystem: lifecycle
tags: [bash, jq, jsonl, state-machine, lifecycle, conventions]

# Dependency graph
requires:
  - phase: 05-pattern-extraction
    provides: "Candidate conventions from session log analysis"
  - phase: 04-explicit-feedback
    provides: "Explicit feedback entries in conventions.json and anti-patterns.json"
  - phase: 01-plugin-skeleton-injection
    provides: "inject-context.sh SessionStart hook, markers.sh, tokens.sh"
provides:
  - "Lifecycle state machine library (scripts/lib/lifecycle.sh) with 7 functions"
  - "Session counter tracking in lifecycle.json"
  - "Candidate promotion (observation -> review_pending) at 3+ observations across 2+ sessions"
  - "Convention decay after 5+ sessions without reference"
  - "50-convention cap enforcement with confidence-based eviction"
  - "Backward-compatible migration of Phase 2/4 entries with stage and last_referenced_session fields"
  - "Changelog audit trail in changelog.jsonl for all lifecycle transitions"
  - "Lifecycle-aware convention injection pipeline in inject-context.sh"
  - "Review-pending count in session status line"
affects: [06-02-PLAN, 06-03-PLAN, 07-anti-patterns-reward, 08-path-scoped-rules]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Lifecycle state machine with 4 stages: observation -> review_pending -> active -> decayed"
    - "Session counter monotonic increment with resume/compact detection"
    - "Atomic JSON writes with jq > .tmp && mv pattern (multi-line continuation)"
    - "Defensive jq field access with // alternative operator for missing fields"
    - "JSONL changelog audit trail for all state transitions"

key-files:
  created:
    - scripts/lib/lifecycle.sh
  modified:
    - scripts/inject-context.sh
    - scripts/detect-feedback.sh

key-decisions:
  - "Explicit feedback entries get stage:active immediately (user-approved by definition, LIFE-06 research note)"
  - "last_referenced_session set to current session_count on migration (prevents immediate decay of existing entries)"
  - "Candidates also migrated with stage:observation for consistency"
  - "Evicted conventions (beyond 50 cap) logged to changelog.jsonl for audit visibility"

patterns-established:
  - "Lifecycle pipeline order: init -> increment session -> migrate -> promote -> decay -> get active -> inject"
  - "Convention filtering by stage==active before injection (decayed and review_pending excluded)"
  - "last_referenced_session updated atomically for all active conventions on each SessionStart"

requirements-completed: [LIFE-01, LIFE-02, LIFE-03, LIFE-04, LIFE-05, TRNS-05]

# Metrics
duration: 2min
completed: 2026-02-25
---

# Phase 6 Plan 01: Lifecycle State Machine Summary

**4-stage convention lifecycle with session tracking, candidate promotion, decay enforcement, 50-convention cap, and JSONL changelog audit trail**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-25T18:00:00Z
- **Completed:** 2026-02-25T18:01:14Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Created lifecycle.sh library with 7 functions implementing the full convention lifecycle state machine
- Integrated lifecycle pipeline into inject-context.sh: session counter, migration, promotion, decay, capped injection
- Updated detect-feedback.sh to include stage:active and last_referenced_session:0 on all new explicit feedback entries
- All lifecycle transitions logged to changelog.jsonl for audit trail

## Task Commits

Each task was committed atomically:

1. **Task 1: Create lifecycle helper library and update detect-feedback.sh** - `3c1d32e` (feat)
2. **Task 2: Integrate lifecycle pipeline into inject-context.sh** - `54b725c` (feat)

## Files Created/Modified
- `scripts/lib/lifecycle.sh` - Lifecycle helper library with 7 functions: init_lifecycle, increment_session, migrate_conventions, promote_candidates, decay_conventions, get_active_conventions, log_changelog
- `scripts/inject-context.sh` - SessionStart hook with full lifecycle pipeline: session counter, migration, promotion, decay, active-only injection with 50-convention cap, last_referenced_session tracking, review-pending status count
- `scripts/detect-feedback.sh` - Explicit feedback entries now include stage:active and last_referenced_session:0 fields

## Decisions Made
- Explicit feedback entries receive `stage: "active"` immediately since user approval is implicit (LIFE-06 research note)
- `last_referenced_session` set to current `session_count` during migration to prevent immediate decay of existing Phase 2/4 entries
- Candidates also migrated with `stage: "observation"` for lifecycle consistency
- Conventions evicted beyond the 50-cap are logged to changelog.jsonl with reason "exceeded 50-convention cap"

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Lifecycle state machine is operational and ready for /ac-review and /ac-status skills (Plan 06-02)
- PreCompact context preservation hook (Plan 06-03) can build on lifecycle.json backup/restore
- All lifecycle transitions are logged to changelog.jsonl for /ac-status reporting

## Self-Check: PASSED

All files verified present, all commits verified in git history.

---
*Phase: 06-convention-lifecycle-review*
*Completed: 2026-02-25*
