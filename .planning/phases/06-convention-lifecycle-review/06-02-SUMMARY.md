---
phase: 06-convention-lifecycle-review
plan: 02
subsystem: lifecycle
tags: [skills, review-gate, dashboard, jq, jsonl, conventions, candidates]

# Dependency graph
requires:
  - phase: 06-convention-lifecycle-review
    provides: "Lifecycle state machine with session counter, promotion, decay, and changelog"
  - phase: 05-pattern-extraction
    provides: "Candidate conventions from session log analysis"
  - phase: 04-explicit-feedback
    provides: "Explicit feedback entries in conventions.json and anti-patterns.json"
provides:
  - "Mandatory review gate skill (/ac-review) for convention approval (LIFE-06)"
  - "Pipeline status dashboard skill (/ac-status) for full visibility"
  - "approve/reject/edit workflow with immediate disk persistence per decision"
  - "Changelog audit logging for all review decisions"
  - "Convention promotion with confidence 0.7 and last_referenced_session tracking"
affects: [06-03-PLAN, 07-anti-patterns-reward, 08-path-scoped-rules]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "SKILL.md prompt-driven skills with disable-model-invocation: true for user-initiated-only operations"
    - "One-at-a-time candidate presentation with immediate disk write (prevents context compaction data loss)"
    - "Atomic JSON operations via jq + tmp + mv pattern in skill instructions"
    - "Read-only dashboard skill pattern for pipeline visibility"

key-files:
  created:
    - skills/ac-review/SKILL.md
    - skills/ac-status/SKILL.md
  modified: []

key-decisions:
  - "Promoted extraction conventions get confidence 0.7 (above bootstrap 0.6, below explicit 1.0)"
  - "One candidate at a time with immediate disk write to prevent context compaction data loss"
  - "last_referenced_session set from lifecycle.json session_count on approval to prevent immediate decay"
  - "ac-status is strictly read-only -- never modifies data files"

patterns-established:
  - "Review gate pattern: present candidate -> user decides -> write to disk -> next candidate"
  - "Status dashboard pattern: read all data files -> aggregate counts by stage -> format markdown"
  - "Both user-facing skills use disable-model-invocation: true to ensure user-initiated operation only"

requirements-completed: [LIFE-06, TRNS-01, TRNS-02]

# Metrics
duration: 2min
completed: 2026-02-25
---

# Phase 6 Plan 02: /ac-review and /ac-status Skills Summary

**Mandatory review gate (/ac-review) with approve/reject/edit workflow and pipeline status dashboard (/ac-status) showing conventions, candidates, and changelog activity**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-25T01:07:49Z
- **Completed:** 2026-02-25T01:10:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Created /ac-review skill enforcing the mandatory user review gate (LIFE-06) -- no extraction-sourced convention reaches CLAUDE.md without explicit approval
- Created /ac-status skill providing full pipeline visibility with convention/candidate counts by stage, anti-pattern counts, observation stats, and recent changelog activity
- Both skills follow the established SKILL.md pattern with disable-model-invocation: true for user-initiated-only operation

## Task Commits

Each task was committed atomically:

1. **Task 1: Create /ac-review skill for mandatory convention approval** - `39c1ea7` (feat)
2. **Task 2: Create /ac-status skill for pipeline visibility** - `39c1ea7` (feat)

Note: Both tasks were committed together in `39c1ea7` as they are tightly coupled skill definitions.

## Files Created/Modified
- `skills/ac-review/SKILL.md` - Mandatory review gate skill: reads review_pending candidates, presents one at a time with evidence (text, confidence, observations, sessions_seen), supports approve (confidence 0.7, reads session_count for last_referenced_session), reject, and edit actions, writes each decision to disk immediately, logs to changelog.jsonl
- `skills/ac-status/SKILL.md` - Pipeline status dashboard skill: shows session info, conventions by stage (active/decayed) with 50-cap usage, candidates by stage (observation/review_pending), anti-pattern count, observation stats, recent changelog activity, and Phase 7 reward placeholder

## Decisions Made
- Promoted extraction conventions receive confidence 0.7 (above bootstrap 0.6 midpoint, below explicit 1.0) to reflect reviewed-but-automated origin
- Candidates presented one at a time with immediate disk write after each decision to prevent context compaction data loss (research Pitfall 5)
- last_referenced_session set from lifecycle.json session_count on approval to prevent immediate decay of newly approved conventions (research Pitfall 3)
- ac-status is strictly read-only to ensure no accidental data mutation during status checks

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Review gate and status dashboard are operational, completing the user-facing lifecycle tools
- Plan 06-03 (PreCompact context preservation) can proceed independently
- Phase 7 reward signal tracking has placeholder in /ac-status ready for integration

## Self-Check: PASSED

All files verified present, all commits verified in git history.

---
*Phase: 06-convention-lifecycle-review*
*Completed: 2026-02-25*
