# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-24)

**Core value:** Use Claude Code normally, and your project context improves automatically.
**Current focus:** Phase 7: Anti-Pattern Detection & Reward Signals

## Current Position

Phase: 7 of 8 (Anti-Pattern Detection & Reward Signals) -- PENDING
Plan: 1 of 3 in current phase
Status: Phase 6 Complete, ready for Phase 7
Last activity: 2026-02-25 -- Completed 06-03 PreCompact context preservation (1 task, 3 files)

Progress: [########..] 81%

## Performance Metrics

**Velocity:**
- Total plans completed: 13
- Average duration: 2.5min
- Total execution time: 0.55 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| Phase 01 P01 | 2min | 2 tasks | 8 files |
| Phase 01 P02 | 5min | 2 tasks | 3 files |
| Phase 02 P01 | 4min | 2 tasks | 2 files |
| Phase 02 P02 | 3min | 2 tasks | 1 file (+1 deleted) |
| Phase 03 P01 | 3min | 2 tasks | 2 files |
| Phase 03 P02 | 3min | 2 tasks | 3 files |
| Phase 04 P01 | 3min | 2 tasks | 2 files |
| Phase 04 P02 | 2min | 1 task | 1 file |
| Phase 05 P01 | 2min | 1 task | 1 file |
| Phase 05 P02 | 2min | 2 tasks | 2 files |
| Phase 06 P01 | 2min | 2 tasks | 3 files |
| Phase 06 P02 | 2min | 2 tasks | 2 files |
| Phase 06 P03 | 1min | 1 task | 3 files |

**Recent Trend:**
- Last 5 plans: 2min, 2min, 2min, 2min, 1min
- Trend: stable/improving

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: 8 phases derived from 50 requirements (comprehensive depth)
- [Roadmap]: Token budget (INJT-01) and JSONL format (OBSV-04) placed in Phase 1 as survival constraints
- [Roadmap]: Stop hook (not SessionEnd) for pattern extraction agent -- SessionEnd does not support agent handlers
- [Roadmap]: Mandatory user review gate (LIFE-06) required before any convention reaches CLAUDE.md
- [Phase 01]: Conservative chars_per_token=3.0 (not 3.5) for safety with non-English content
- [Phase 01]: Combined data store init and hook logic in single inject-context.sh
- [Phase 01]: JSONL append via echo >> for O(1) session logging
- [Phase 01]: grep -F (fixed string) for marker matching -- avoids HTML comment regex issues
- [Phase 01]: Content passed to awk via temp file for multiline safety across awk versions
- [Phase 01]: tr -d sanitization for grep -c output on macOS
- [Phase 02]: SKILL.md as prompt-driven scanning -- leverages Claude reasoning for pattern detection
- [Phase 02]: discover-commands.sh handles deterministic extraction, SKILL.md handles pattern recognition
- [Phase 02]: Bootstrap conventions scored 0.6-0.9 with source: "bootstrap" for later lifecycle management
- [Phase 02]: Merge strategy: preserve non-bootstrap conventions, replace bootstrap ones on re-run
- [Phase 03]: Single jq extraction via @tsv for performance (one process spawn vs four)
- [Phase 03]: PostToolUseFailure check before case statement for cleaner flow
- [Phase 03]: Safety net mkdir/touch in observe-tool.sh in case SessionStart didn't run
- [Phase 03]: Stale log detection via jq select with head -1 | wc -c for efficiency
- [Phase 04]: Colon-based extraction for trigger phrases (macOS sed compat, avoids //I flag)
- [Phase 04]: PROMPT_LOWER for English pattern matching, original PROMPT for Korean (grep -qF)
- [Phase 04]: jq -nc for session log JSONL (proper JSON escaping vs manual string construction)
- [Phase 04]: Anti-pattern count in status line only when > 0 (clean default output)
- [Phase 05]: Single agent hook (not command+agent) for simplicity -- pre-check logic in agent prompt
- [Phase 05]: ${CLAUDE_PLUGIN_ROOT} for primary path with fallback resolution and inline minimal instructions
- [Phase 05]: Confidence 0.3 for extraction candidates (below bootstrap 0.6+ and explicit 1.0)
- [Phase 05]: Archive session-log.jsonl to .prev before SessionEnd truncation (race condition safety)
- [Phase 06]: Explicit feedback gets stage:active immediately (user-approved by definition)
- [Phase 06]: last_referenced_session set to current session_count on migration (prevents immediate decay)
- [Phase 06]: Candidates migrated with stage:observation for lifecycle consistency
- [Phase 06]: Evicted conventions (beyond 50 cap) logged to changelog.jsonl for audit
- [Phase 06]: Promoted extraction conventions get confidence 0.7 (above bootstrap 0.6, below explicit 1.0)
- [Phase 06]: One candidate at a time with immediate disk write to prevent context compaction data loss
- [Phase 06]: last_referenced_session from lifecycle.json on approval prevents immediate decay
- [Phase 06]: ac-status is strictly read-only -- never modifies data files
- [Phase 06]: PreCompact only supports type:command hooks (agent/prompt silently fail)
- [Phase 06]: Backup dir cleaned up after restore check (one-time safety net per compaction)
- [Phase 06]: jq empty for lightweight JSON validation in restore logic
- [Phase 06]: Restore block placed before lifecycle init so recovered lifecycle.json is available

### Pending Todos

None yet.

### Blockers/Concerns

None yet.

## Session Continuity

Last session: 2026-02-25
Stopped at: Completed 06-03-PLAN.md (PreCompact Context Preservation) -- Phase 6 Complete
Resume file: None
