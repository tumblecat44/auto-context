---
phase: 06-convention-lifecycle-review
verified: 2026-02-25T01:13:04Z
status: passed
score: 5/5 must-haves verified
re_verification: false
---

# Phase 6: Convention Lifecycle & Review Verification Report

**Phase Goal:** Conventions follow a rigorous 4-stage lifecycle and never reach CLAUDE.md without explicit user approval
**Verified:** 2026-02-25T01:13:04Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Conventions progress through Observation -> Candidate (3+ occurrences across 2+ sessions) -> Convention -> Decay lifecycle | VERIFIED | `promote_candidates()` in lifecycle.sh filters for `stage=="observation" AND observations>=3 AND sessions_seen.length>=2`, sets `stage="review_pending"`; `decay_conventions()` sets `stage="decayed"` after `session_count - last_referenced_session >= 5` |
| 2 | No convention reaches CLAUDE.md without user approval via /ac-review | VERIFIED | `get_active_conventions()` filters by `stage=="active"` only; extraction-sourced conventions go through `stage="review_pending"` gate enforced by /ac-review SKILL.md; `disable-model-invocation: true` prevents auto-invocation |
| 3 | Conventions decay after 5+ sessions without reference and are removed from CLAUDE.md injection | VERIFIED | `decay_conventions()` at line 157: `($sc - (.last_referenced_session // 0)) >= 5` marks `stage="decayed"`; `get_active_conventions()` at line 192 filters `select(.stage == "active")` only, excluding decayed entries |
| 4 | Maximum 50 active conventions enforced (lowest-confidence evicted when exceeded) | VERIFIED | `get_active_conventions()` calls `sort_by(-.confidence)` then `.[:$mc]` (max 50); entries beyond cap logged to changelog.jsonl with reason "exceeded 50-convention cap (lowest confidence)" |
| 5 | /ac-status shows observation counts, candidates, conventions, anti-patterns, and reward trends | VERIFIED | ac-status/SKILL.md reads all 5 data files; displays: session_count, active/decayed convention counts with 50-cap usage, observation/review_pending candidate counts, anti-pattern total, total observations sum, unique sessions, recent changelog activity. Reward trends: placeholder "pending Phase 7" (by design — Phase 7 owns reward signals) |

**Score: 5/5 truths verified**

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `scripts/lib/lifecycle.sh` | Lifecycle helper functions for promotion, decay, migration, cap enforcement, changelog logging | VERIFIED | 213 lines; all 7 functions present: `init_lifecycle`, `increment_session`, `migrate_conventions`, `promote_candidates`, `decay_conventions`, `get_active_conventions`, `log_changelog`. Passes `bash -n`. |
| `scripts/inject-context.sh` | SessionStart pipeline with lifecycle logic | VERIFIED | Sources `lifecycle.sh` (line 14); full pipeline: BACKUP_DIR restore (line 33) -> `init_lifecycle` (line 48) -> `increment_session` (line 68) -> `migrate_conventions` (line 71) -> `promote_candidates` (line 74) -> `decay_conventions` (line 77) -> `get_active_conventions 50` (line 84) -> `last_referenced_session` update (line 90) -> inject. REVIEW_COUNT status line at line 119. Passes `bash -n`. |
| `scripts/detect-feedback.sh` | Explicit feedback with lifecycle stage fields | VERIFIED | Line 79: jq call includes `"stage": "active"` and `"last_referenced_session": 0` in all new explicit feedback entries. Passes `bash -n`. |
| `skills/ac-review/SKILL.md` | Mandatory review gate skill for convention approval | VERIFIED | `disable-model-invocation: true` in frontmatter. Reads candidates.json filtered by `stage=="review_pending"`. Presents one-at-a-time with text/confidence/observations/sessions_seen/evidence. Supports approve (confidence 0.7, reads lifecycle.json session_count), reject, edit. Each decision written immediately. Logs to changelog.jsonl. |
| `skills/ac-status/SKILL.md` | Pipeline status dashboard skill | VERIFIED | `disable-model-invocation: true` in frontmatter. Reads conventions.json, candidates.json, anti-patterns.json, lifecycle.json, config.json. Displays counts by stage, convention cap usage, observation stats, recent changelog. Read-only. |
| `scripts/preserve-context.sh` | PreCompact backup handler | VERIFIED | Copies conventions.json, candidates.json, anti-patterns.json, lifecycle.json to `.auto-context/backup/`. Guards on `[ -d "$STORE_DIR" ]`. Exits 0 always. Executable bit set. Passes `bash -n`. |
| `hooks/hooks.json` | PreCompact hook registration | VERIFIED | 7 hook events: SessionStart, UserPromptSubmit, PostToolUse, PostToolUseFailure, PreCompact, Stop, SessionEnd. PreCompact entry: `type: "command"`, command: `${CLAUDE_PLUGIN_ROOT}/scripts/preserve-context.sh`. Valid JSON. |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `scripts/inject-context.sh` | `scripts/lib/lifecycle.sh` | `source` statement | WIRED | Line 14: `source "${SCRIPT_DIR}/lib/lifecycle.sh"` |
| `scripts/inject-context.sh` | `.auto-context/lifecycle.json` | session counter read/write via `increment_session` | WIRED | `increment_session "$STORE_DIR" "$SESSION_ID"` (line 68); lifecycle.json read/written inside function |
| `scripts/inject-context.sh` | `.auto-context/changelog.jsonl` | lifecycle transition logging via library functions | WIRED | `promote_candidates`, `decay_conventions`, `get_active_conventions` all call `log_changelog` which appends to `changelog.jsonl` |
| `scripts/inject-context.sh` | `.auto-context/conventions.json` | stage==active filter and cap enforcement | WIRED | `get_active_conventions` (line 84) filters `select(.stage == "active")`; `last_referenced_session` update (line 90) writes back to conventions.json atomically |
| `skills/ac-review/SKILL.md` | `.auto-context/candidates.json` | Read + jq filter for stage==review_pending | WIRED | Line 26: `jq '[.[] | select(.stage == "review_pending")]' .auto-context/candidates.json`; line 83: atomic removal of approved candidate |
| `skills/ac-review/SKILL.md` | `.auto-context/conventions.json` | Write approved entries with stage:active | WIRED | Lines 65, 82: reads then appends approved entry with `stage: "active"` to conventions.json |
| `skills/ac-review/SKILL.md` | `.auto-context/changelog.jsonl` | Log each approve/reject decision | WIRED | Lines 84-88: jq -nc append to changelog.jsonl for approve; line 95: logged for reject |
| `skills/ac-status/SKILL.md` | `.auto-context/lifecycle.json` | Read session counter and lifecycle metadata | WIRED | Line 44: `jq -r '.session_count // 0' .auto-context/lifecycle.json` |
| `hooks/hooks.json` | `scripts/preserve-context.sh` | PreCompact command hook entry | WIRED | Line 50: `"command": "${CLAUDE_PLUGIN_ROOT}/scripts/preserve-context.sh"` |
| `scripts/preserve-context.sh` | `.auto-context/backup/` | cp of critical JSON files | WIRED | Lines 12, 20-21: BACKUP_DIR set, cp loop for 4 files |
| `scripts/inject-context.sh` | `.auto-context/backup/` | restore check on SessionStart | WIRED | Lines 33-44: BACKUP_DIR check, jq empty validation, cp restore, rm -rf cleanup |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| LIFE-01 | 06-01-PLAN | 4-stage lifecycle: Observation -> Candidate (3+ occurrences across 2+ sessions) -> Convention -> Decay | SATISFIED | `promote_candidates()` implements observation->review_pending transition; `decay_conventions()` implements active->decayed; injection filters by stage==active |
| LIFE-02 | 06-01-PLAN | Candidates require observations from 2+ independent sessions before promotion | SATISFIED | `promote_candidates()` line: `((.sessions_seen // []) | length) >= 2` |
| LIFE-03 | 06-01-PLAN | Conventions decay after 5+ sessions without reference | SATISFIED | `decay_conventions()`: `($sc - (.last_referenced_session // 0)) >= 5` |
| LIFE-04 | 06-01-PLAN | Decayed conventions removed from CLAUDE.md injection | SATISFIED | `get_active_conventions()` filters `select(.stage == "active")` only; inject-context.sh uses this filtered list |
| LIFE-05 | 06-01-PLAN | Maximum 50 active conventions (lowest-confidence evicted when exceeded) | SATISFIED | `get_active_conventions()` `sort_by(-.confidence)` then `.[:$mc]` (max 50) |
| LIFE-06 | 06-02-PLAN | Mandatory user review gate via /ac-review before any convention reaches CLAUDE.md | SATISFIED | ac-review/SKILL.md with `disable-model-invocation: true`; extraction-sourced conventions land at `stage="review_pending"` via `promote_candidates()`, never `stage="active"` directly; only /ac-review can approve to active |
| TRNS-01 | 06-02-PLAN | /ac-status shows observation count, candidates, conventions, anti-patterns, reward trends | SATISFIED | ac-status/SKILL.md shows all elements; reward trends has Phase 7 placeholder by design (Phase 7 owns reward signals per ROADMAP) |
| TRNS-02 | 06-02-PLAN | /ac-review displays candidate list with approve/reject/edit per item | SATISFIED | ac-review/SKILL.md presents each review_pending candidate one-at-a-time with approve/reject/edit handling |
| TRNS-05 | 06-01-PLAN | Log convention changes with reason | SATISFIED | `log_changelog()` appends to changelog.jsonl for all transitions: promoted, decayed, evicted, approved, rejected |
| PRSC-01 | 06-03-PLAN | PreCompact hook backs up critical context data before context compression | SATISFIED | preserve-context.sh registered as PreCompact command hook in hooks.json; backs up 4 critical files |
| PRSC-02 | 06-03-PLAN | SessionStart hook restores context from backup if needed | SATISFIED | inject-context.sh lines 32-45: checks BACKUP_DIR, validates with `jq empty`, restores empty/corrupted files, cleans up |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `skills/ac-status/SKILL.md` | 101 | `- Reward tracking: pending Phase 7` | Info | Expected placeholder — reward signals are Phase 7 scope per ROADMAP. TRNS-01 requirement is satisfied for Phase 6 elements (observation counts, candidates, conventions, anti-patterns are all shown). |

No blocker or warning anti-patterns found.

---

### Human Verification Required

#### 1. /ac-review One-at-a-Time Enforcement

**Test:** Run `/ac-review` with multiple review_pending candidates in candidates.json.
**Expected:** Claude presents exactly one candidate, waits for user response, writes decision to disk, then presents the next. Does not batch-display all candidates at once.
**Why human:** The SKILL.md instructions are correct, but actual Claude behavior in following them cannot be verified programmatically. Context compaction risk (Pitfall 5) only manifests at runtime.

#### 2. CLAUDE.md Injection Gate Under Live Conditions

**Test:** Simulate a candidate with 3+ observations across 2+ sessions. Verify it remains at `review_pending` stage and does NOT appear in CLAUDE.md after a SessionStart without running /ac-review.
**Expected:** Candidate stays in candidates.json at stage=review_pending; CLAUDE.md only shows stage==active conventions.
**Why human:** The injection pipeline logic is correct in code, but end-to-end gate verification requires a live session start with real data.

#### 3. Session Counter Deduplication (Resume/Compact Detection)

**Test:** Start a session, then do a context compact or resume within the same session. Verify session_count in lifecycle.json is NOT incremented on the resume/compact.
**Expected:** `last_session_id` matches current `session_id`, so `increment_session` returns early without incrementing.
**Why human:** Requires triggering actual context compaction/resume, which cannot be simulated programmatically.

---

### Gaps Summary

No gaps found. All 5 observable truths verified, all 7 artifacts exist and are substantive and wired, all 11 key links confirmed wired, all 11 requirement IDs fully satisfied.

The one notable item (TRNS-01 "reward trends" showing a placeholder) is by design: reward signals are Phase 7 scope. The Phase 6 portion of TRNS-01 (observation counts, candidates, conventions, anti-patterns) is fully implemented.

---

_Verified: 2026-02-25T01:13:04Z_
_Verifier: Claude (gsd-verifier)_
