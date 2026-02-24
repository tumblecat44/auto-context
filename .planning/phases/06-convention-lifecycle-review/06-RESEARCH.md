# Phase 6: Convention Lifecycle & Review - Research

**Researched:** 2026-02-25
**Domain:** Convention state machine (4-stage lifecycle), promotion/decay logic, mandatory user review gate, /ac-review and /ac-status skills, PreCompact context preservation, session-count tracking
**Confidence:** HIGH

## Summary

Phase 6 is the governance layer of auto-context. It takes the raw candidates produced by Phase 5 (extraction agent) and Phase 4 (explicit feedback), and subjects them to a rigorous 4-stage lifecycle: Observation -> Candidate -> Convention -> Decay. The core principle is that no convention reaches CLAUDE.md without explicit user approval via `/ac-review`. This phase also introduces `/ac-status` for full visibility into the pipeline, and context preservation hooks (PreCompact) to protect critical data during context compaction.

The implementation is primarily shell scripting (consistent with Phases 1-5), two new skills (/ac-review and /ac-status), and modifications to the existing SessionStart injection script (`inject-context.sh`). The lifecycle state machine is driven by JSON data in `.auto-context/conventions.json` and `.auto-context/candidates.json`. Promotion logic runs at session start (checking candidate thresholds), decay logic also runs at session start (checking conventions against session counts), and the cap of 50 active conventions is enforced during injection. The `/ac-review` skill is the mandatory gate -- it presents candidates to the user and writes approved conventions to `conventions.json`.

The critical technical considerations are: (1) tracking session counts for cross-session requirements (LIFE-02 requires 2+ sessions for promotion, LIFE-03 requires 5+ sessions without reference for decay), (2) the PreCompact hook only supports `type: "command"` (no agent/prompt), so context preservation must be a shell script, and (3) the /ac-review skill must be `disable-model-invocation: true` since convention approval is a user-controlled action that should never auto-trigger.

**Primary recommendation:** Add a `lifecycle.json` metadata file to `.auto-context/` to track session counts and last-seen timestamps. Modify `inject-context.sh` to increment session counter, run promotion checks (candidates with 3+ observations across 2+ sessions), run decay checks (conventions not referenced in 5+ sessions), and enforce the 50-convention cap. Create `/ac-review` as an interactive skill that reads candidates and guides the user through approve/reject/edit decisions. Create `/ac-status` as a read-only skill that formats pipeline statistics. Add a PreCompact command hook to back up critical JSON state.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| LIFE-01 | 4-stage lifecycle: Observation -> Candidate (3+ occurrences across 2+ sessions) -> Convention -> Decay | Lifecycle state machine implemented via `stage` field on each entry. Candidates track `observations` count and `sessions_seen` array (already present from Phase 5 extraction agent schema). Promotion threshold: observations >= 3 AND length(sessions_seen) >= 2. SessionStart injection script checks thresholds and moves qualified candidates to a "pending review" state. Decay stage entered when session_count - last_referenced_session >= 5. |
| LIFE-02 | Candidates require observations from 2+ independent sessions before promotion | The `sessions_seen` array on candidate entries (established in Phase 5) tracks unique session IDs. Promotion check: `jq 'select(.sessions_seen \| length >= 2)'`. The extraction agent already appends session IDs to this array on each observation. No new tracking needed beyond what Phase 5 provides. |
| LIFE-03 | Conventions decay after 5+ sessions without reference | Requires a `last_referenced_session` counter on each convention. At SessionStart, increment a global session counter in `lifecycle.json`. When injecting conventions into CLAUDE.md, record the current session number as `last_referenced_session` for each injected convention. At next injection, check: if (current_session - last_referenced_session) >= 5, mark convention as decayed. |
| LIFE-04 | Decayed conventions removed from CLAUDE.md injection | The `inject-context.sh` script already filters conventions for injection. Add a filter: exclude entries where `stage == "decayed"`. Decayed conventions remain in `conventions.json` for auditability but are not included in the CLAUDE.md content. |
| LIFE-05 | Maximum 50 active conventions (lowest-confidence evicted when exceeded) | During injection in `inject-context.sh`, sort active conventions by confidence descending, take first 50. Evicted conventions remain in storage but are not injected. The `confidence` field already exists on all convention entries (bootstrap: 0.6-0.9, explicit: 1.0, promoted extraction: configurable). |
| LIFE-06 | Mandatory user review gate via /ac-review before any convention reaches CLAUDE.md in v1 | The `/ac-review` skill is `disable-model-invocation: true` (user must explicitly invoke). Candidates meeting promotion thresholds are marked `stage: "review_pending"` but NOT moved to conventions.json until approved via `/ac-review`. The injection script ONLY reads from conventions.json, so unapproved candidates never reach CLAUDE.md. |
| TRNS-01 | /ac-status shows observation count, candidates, conventions, anti-patterns, reward trends | `/ac-status` skill reads all JSON data files and formats statistics. Observation counts from candidates (sum of `observations` fields), candidate count, convention count by stage, anti-pattern count. Reward trends deferred to Phase 7 (RWRD-03/04) -- show placeholder "reward tracking: pending Phase 7". |
| TRNS-02 | /ac-review displays candidate list with approve/reject/edit per item | `/ac-review` skill reads candidates.json, filters for `stage: "review_pending"` (or candidates meeting promotion thresholds), formats each with text, confidence, evidence, sessions_seen. Instructs Claude to present each candidate and ask user to approve/reject/edit. Approved items written to conventions.json with `stage: "active"`. |
| TRNS-05 | Log convention changes with reason | All promotion, decay, and review actions logged to `.auto-context/changelog.jsonl` in JSONL format. Each entry: `{ts, action, convention_text, reason, details}`. Example: `{"action": "promoted", "convention_text": "use async/await", "reason": "observed 5x across 3 sessions, approved via /ac-review"}`. |
| PRSC-01 | PreCompact hook backs up critical context data before context compression | PreCompact hook (type: "command") runs a script that copies key JSON files to `.auto-context/backup/` before compaction. Files to back up: conventions.json, candidates.json, anti-patterns.json, lifecycle.json. PreCompact only supports command hooks (verified from official docs). |
| PRSC-02 | SessionStart hook restores context from backup if needed | Modify `inject-context.sh` to check for `.auto-context/backup/` directory. If primary data files are empty/corrupted but backup exists, restore from backup. Then clean up the backup directory. This handles the case where compaction somehow corrupts in-memory state that was about to be written. |
</phase_requirements>

## Standard Stack

### Core

| Library/Tool | Version | Purpose | Why Standard |
|-------------|---------|---------|--------------|
| Bash | 3.2+ (macOS) / 5.x (Linux) | Shell scripts for lifecycle logic, PreCompact hook, injection modifications | Consistent with Phases 1-5; all hooks are command-type shell scripts |
| jq | 1.6+ | JSON manipulation for lifecycle state transitions, candidate filtering, convention sorting | Already required by all previous phases; handles atomic JSON updates, array filtering, sorting |
| SKILL.md (Claude Code Skills) | Current | /ac-review and /ac-status skill definitions | Official Claude Code skill system; plugin skills use `plugin-name:skill-name` namespace; YAML frontmatter for invocation control |

### Supporting

| Library/Tool | Version | Purpose | When to Use |
|-------------|---------|---------|-------------|
| date | POSIX | ISO 8601 timestamps for changelog entries and lifecycle transitions | Every state transition needs a timestamp |
| cp | POSIX | File backup for PreCompact context preservation | PreCompact hook copies JSON files to backup directory |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|-----------|-----------|----------|
| Shell script lifecycle logic | Agent hook for lifecycle decisions | Agent hooks add LLM cost and latency. Lifecycle logic is deterministic (threshold comparisons, counter arithmetic) -- no LLM reasoning needed. Shell scripts are faster, cheaper, and predictable. |
| `lifecycle.json` for session tracking | Session counter in `config.json` | Separate file keeps lifecycle metadata isolated from user-facing config. Avoids accidentally exposing internal counters if user reads config.json. |
| JSONL changelog for TRNS-05 | Appending to conventions.json history | Separate changelog file keeps the audit trail independent of the convention data. JSONL format is consistent with session-log.jsonl (O(1) appends). |
| jq for 50-convention cap enforcement | Sort in shell with awk | jq `sort_by` is more reliable for numeric sorting on the `confidence` field. Shell-based numeric sorting is fragile with floating point values. |

**Installation:**
```bash
# No new dependencies -- Bash and jq already required by Phases 1-5
# Skills are just SKILL.md files in the plugin skills/ directory
```

## Architecture Patterns

### Recommended Project Structure (Phase 6 additions)

```
auto-context/
├── hooks/
│   └── hooks.json                    # MODIFY: add PreCompact hook entry
├── scripts/
│   ├── inject-context.sh             # MODIFY: add lifecycle logic (promotion, decay, cap, restore)
│   ├── observe-tool.sh               # EXISTING (Phase 3)
│   ├── cleanup-session.sh            # EXISTING (Phase 5)
│   ├── detect-feedback.sh            # EXISTING (Phase 4)
│   ├── preserve-context.sh           # NEW: PreCompact hook handler
│   └── lib/
│       ├── markers.sh                # EXISTING (Phase 1)
│       ├── tokens.sh                 # EXISTING (Phase 1)
│       └── lifecycle.sh              # NEW: lifecycle helper functions
├── agents/
│   └── extract-patterns.md           # EXISTING (Phase 5)
├── skills/
│   ├── ac-init/                      # EXISTING (Phase 2)
│   ├── ac-reset/                     # EXISTING (Phase 2)
│   ├── ac-review/                    # NEW: mandatory review gate skill
│   │   └── SKILL.md
│   └── ac-status/                    # NEW: pipeline status skill
│       └── SKILL.md
└── .auto-context/                    # Runtime data store (in user's project)
    ├── conventions.json              # MODIFY: add stage, last_referenced_session fields
    ├── candidates.json               # MODIFY: add stage field
    ├── anti-patterns.json            # EXISTING
    ├── config.json                   # EXISTING
    ├── lifecycle.json                # NEW: session counter, global metadata
    ├── changelog.jsonl               # NEW: audit trail of all convention changes
    ├── session-log.jsonl             # EXISTING
    └── backup/                       # NEW: PreCompact backup directory
        ├── conventions.json
        ├── candidates.json
        ├── anti-patterns.json
        └── lifecycle.json
```

### Pattern 1: Convention Lifecycle State Machine

**What:** A 4-stage lifecycle tracked via a `stage` field on each convention/candidate entry.
**When to use:** Every convention and candidate entry must have a `stage` field.

```
Stages and transitions:

  [observation]  ──(3+ occurrences, 2+ sessions)──>  [review_pending]
                                                           │
                                            /ac-review     │
                                      ┌── approve ──>  [active]
                                      │                    │
                                      ├── reject ──>  [rejected] (removed)
                                      │                    │
                                      └── edit ──>    [active] (modified text)
                                                           │
                                          (5+ sessions     │
                                           no reference)   │
                                                           v
                                                       [decayed]
```

Stage values:
- `"observation"`: Initial state for extraction candidates (observations < 3 or sessions_seen < 2). Phase 5 candidates start here.
- `"review_pending"`: Meets promotion thresholds but awaiting user approval via /ac-review. Promotion script sets this state.
- `"active"`: User-approved convention. Injected into CLAUDE.md. Only conventions with this stage reach CLAUDE.md.
- `"decayed"`: Convention not referenced in 5+ sessions. Removed from CLAUDE.md injection.
- `"rejected"`: User rejected via /ac-review. Removed from candidates. Optional: keep in changelog for audit.

**Special cases:**
- Explicit feedback conventions (source: "explicit", confidence: 1.0) from Phase 4 are written directly to `conventions.json` with `stage: "active"` because the user explicitly stated the convention. No review gate needed for explicit feedback -- the user already approved it by stating it.
- Bootstrap conventions (source: "bootstrap") from Phase 2 also go directly to `stage: "active"` since they were generated at user request via /ac-init.
- Only extraction-sourced candidates (source: "extraction", confidence: 0.3) go through the full observation -> review_pending -> active pipeline.

### Pattern 2: Session Counter for Cross-Session Tracking

**What:** A monotonically increasing session counter stored in `lifecycle.json`, incremented at each SessionStart.
**When to use:** Session counting is needed for LIFE-02 (2+ sessions for promotion) and LIFE-03 (5+ sessions for decay).

```json
{
  "session_count": 42,
  "last_promotion_check": 41,
  "last_decay_check": 41,
  "created_at": "2026-02-25T10:00:00Z"
}
```

The session counter serves two purposes:
1. **Decay tracking (LIFE-03):** Each active convention has a `last_referenced_session` field. At SessionStart, if `session_count - last_referenced_session >= 5`, mark as decayed.
2. **Promotion frequency:** The `last_promotion_check` prevents redundant promotion checks within the same session (edge case: multiple SessionStart events from resume/compact).

### Pattern 3: Promotion Logic at SessionStart

**What:** During SessionStart, check candidates for promotion eligibility and mark qualified ones as `review_pending`.
**When to use:** Runs as part of `inject-context.sh` after data store initialization, before injection.

```bash
# Pseudocode for promotion check in inject-context.sh
# Read candidates.json
# Filter for: stage == "observation" AND observations >= 3 AND sessions_seen length >= 2
# For each qualifying candidate: update stage to "review_pending"
# Log promotion to changelog.jsonl
```

jq implementation:
```bash
# Promote eligible candidates to review_pending
jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
  [.[] | if .stage == "observation" and .observations >= 3 and (.sessions_seen | length) >= 2
         then .stage = "review_pending" | .promoted_at = $ts
         else . end]
' "$STORE_DIR/candidates.json" > "$STORE_DIR/candidates.json.tmp" \
  && mv "$STORE_DIR/candidates.json.tmp" "$STORE_DIR/candidates.json"
```

### Pattern 4: Decay Logic at SessionStart

**What:** Check active conventions for decay eligibility based on session count since last reference.
**When to use:** Runs at SessionStart after session counter increment.

```bash
# Pseudocode for decay check
SESSION_COUNT=$(jq -r '.session_count' "$STORE_DIR/lifecycle.json")
# For each convention where stage == "active":
#   if (SESSION_COUNT - last_referenced_session) >= 5:
#     set stage = "decayed"
#     log to changelog.jsonl
```

jq implementation:
```bash
SESSION_COUNT=$(jq -r '.session_count' "$STORE_DIR/lifecycle.json")
jq --argjson sc "$SESSION_COUNT" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
  [.[] | if .stage == "active" and (.last_referenced_session // 0) > 0 and ($sc - (.last_referenced_session // 0)) >= 5
         then .stage = "decayed" | .decayed_at = $ts
         else . end]
' "$STORE_DIR/conventions.json" > "$STORE_DIR/conventions.json.tmp" \
  && mv "$STORE_DIR/conventions.json.tmp" "$STORE_DIR/conventions.json"
```

### Pattern 5: Convention Cap Enforcement During Injection

**What:** When building CLAUDE.md content, take at most 50 active conventions sorted by confidence descending.
**When to use:** During the injection step in `inject-context.sh`, after promotion and decay checks.

```bash
# Filter active conventions, sort by confidence desc, limit to 50
ACTIVE_CONVS=$(jq '[.[] | select(.stage == "active")] | sort_by(-.confidence) | .[0:50]' "$CONVENTIONS_FILE")
```

Conventions beyond the top 50 remain in `conventions.json` with `stage: "active"` but are not injected. If a higher-confidence convention decays, a previously-evicted one re-enters the injection set automatically at the next session.

### Pattern 6: /ac-review Interactive Skill

**What:** A skill that presents review-pending candidates to the user for approve/reject/edit decisions.
**When to use:** User invokes `/ac-review` manually. This is the mandatory gate for LIFE-06.

SKILL.md frontmatter:
```yaml
---
name: ac-review
description: Review pending convention candidates. Approve, reject, or edit each candidate before it reaches CLAUDE.md.
disable-model-invocation: true
---
```

The skill instructs Claude to:
1. Read `.auto-context/candidates.json`
2. Filter for `stage: "review_pending"` entries
3. Present each candidate with its text, confidence, evidence citations, observation count, and sessions_seen
4. For each: ask the user to approve, reject, or edit
5. Approved: move to `conventions.json` with `stage: "active"`, `source: "extraction"`, assign appropriate confidence (e.g., 0.7 for multi-session confirmed)
6. Rejected: remove from candidates.json (optionally log to changelog)
7. Edited: user modifies the text, then approve as modified
8. After review: trigger injection to update CLAUDE.md immediately

### Pattern 7: PreCompact Context Preservation

**What:** A command hook on PreCompact that backs up JSON data files before context compaction.
**When to use:** Fires before every compaction event (manual or auto).

```json
// Addition to hooks.json
"PreCompact": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/scripts/preserve-context.sh"
      }
    ]
  }
]
```

The script:
```bash
#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd')

STORE_DIR="${CWD}/.auto-context"
BACKUP_DIR="${STORE_DIR}/backup"

# Only back up if store exists
[ -d "$STORE_DIR" ] || exit 0

mkdir -p "$BACKUP_DIR"

# Back up critical data files
for f in conventions.json candidates.json anti-patterns.json lifecycle.json; do
  [ -f "$STORE_DIR/$f" ] && cp "$STORE_DIR/$f" "$BACKUP_DIR/$f" 2>/dev/null || true
done

exit 0
```

**Critical constraint:** PreCompact only supports `type: "command"` hooks. No agent or prompt hooks. No decision control -- the hook cannot block compaction. Source: [Claude Code hooks reference](https://code.claude.com/docs/en/hooks).

### Anti-Patterns to Avoid

- **Auto-promoting candidates without user review:** LIFE-06 is explicit -- v1 requires mandatory user approval. Never move candidates to conventions.json with `stage: "active"` without the user having invoked /ac-review and explicitly approved. The "review_pending" intermediate state enforces this gate.
- **Running lifecycle logic in a separate hook instead of SessionStart:** Adding another hook event increases complexity and ordering concerns. The lifecycle logic (promotion/decay/cap) is fast (jq operations on small JSON files) and belongs in the existing SessionStart flow in `inject-context.sh`.
- **Using agent hooks for PreCompact:** PreCompact only supports `type: "command"`. Attempting agent or prompt hooks will silently fail.
- **Tracking session counts via file modification dates:** File modification dates are unreliable (backups, restores, git operations can change them). Use an explicit counter in lifecycle.json.
- **Storing lifecycle state in conventions.json only:** The session counter needs to be global (not per-convention). A separate lifecycle.json avoids polluting the convention data structure with global metadata.
- **Making /ac-review auto-invocable:** The skill MUST have `disable-model-invocation: true`. If Claude can auto-invoke it, conventions could be approved without the user's explicit intent, violating LIFE-06.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON array sorting by confidence | Shell sort with awk on JSON | `jq 'sort_by(-.confidence)'` | jq handles floating-point sorting correctly; shell sorting of JSON is fragile |
| Atomic JSON file updates | Manual string concatenation | `jq ... > tmp && mv tmp original` | jq ensures valid JSON; mv is atomic on POSIX filesystems |
| Session ID uniqueness tracking | Custom dedup logic | `jq '.sessions_seen \| unique \| length'` | jq's `unique` handles dedup correctly |
| Timestamp generation | Custom date formatting | `date -u +%Y-%m-%dT%H:%M:%SZ` | POSIX-compliant; consistent with all previous phases |
| Interactive review UI | Custom shell prompts (read -p) | Claude Code skill (SKILL.md) | Skills leverage Claude's conversation interface for natural language interaction; no need for shell-based prompts |

**Key insight:** Phase 6 is governance, not intelligence. The lifecycle logic is deterministic (numeric comparisons, threshold checks, sorting). Unlike Phase 5 which needed LLM reasoning for pattern classification, Phase 6 uses shell scripts and jq for all state transitions. The only LLM involvement is in the /ac-review skill where Claude presents candidates and interprets user approve/reject/edit responses.

## Common Pitfalls

### Pitfall 1: Backward Compatibility with Existing Convention Entries

**What goes wrong:** Existing conventions from Phase 2 (bootstrap) and Phase 4 (explicit feedback) lack the new `stage` and `last_referenced_session` fields, causing jq filters to fail or produce unexpected results.
**Why it happens:** Phase 6 adds new fields to the convention schema that previous phases did not create.
**How to avoid:** On first run of the updated `inject-context.sh`, migrate existing entries: add `"stage": "active"` and `"last_referenced_session": 0` to any convention entry that lacks these fields. Use jq's `//` (alternative operator) defensively: `.stage // "active"` and `.last_referenced_session // 0`.
**Warning signs:** Empty CLAUDE.md injection after update; jq errors in SessionStart hook output.

### Pitfall 2: Race Between Extraction Agent and Promotion Check

**What goes wrong:** The extraction agent (Stop hook, Phase 5) writes to candidates.json while the SessionStart promotion check is reading it, causing JSON corruption.
**Why it happens:** Stop fires during the agentic loop, SessionStart fires at session beginning. In normal flow they don't overlap. But on session resume (matcher: "resume"), SessionStart fires while a previous session's Stop hook might still be running.
**How to avoid:** Use atomic file operations consistently (jq + tmp + mv pattern). The mv operation is atomic on POSIX filesystems -- a concurrent reader sees either the old or new file, never a partial write. Both the extraction agent and the promotion logic already use this pattern.
**Warning signs:** JSON parse errors in inject-context.sh; candidates.json containing malformed JSON.

### Pitfall 3: Decay Triggering Too Aggressively on New Conventions

**What goes wrong:** A convention is approved via /ac-review but immediately starts the 5-session decay countdown because `last_referenced_session` was set to the session when the candidate was first observed, not when it was approved.
**Why it happens:** The `last_referenced_session` field is set during injection, but if a convention is approved mid-session (via /ac-review) and injection already ran for that session, the convention won't be injected (and thus referenced) until the next session.
**How to avoid:** When a convention is approved via /ac-review, set `last_referenced_session` to the current session count. The /ac-review skill should trigger an injection update after approval, which also updates last_referenced_session. Alternatively, set `last_referenced_session` to current session count at approval time.
**Warning signs:** Recently-approved conventions showing as "decayed" in /ac-status after only a few sessions.

### Pitfall 4: Session Counter Not Incrementing on Resume/Compact

**What goes wrong:** The session counter only increments on fresh session start, but SessionStart also fires on resume and compact events (with different matchers). If the counter doesn't increment on resume, the decay timer stalls.
**Why it happens:** SessionStart fires with matchers: `startup`, `resume`, `clear`, `compact`. Each firing represents continued user activity but may not be a "new session" in the lifecycle sense.
**How to avoid:** Only increment the session counter on `startup` matcher (fresh session). Resume and compact represent the same session. To distinguish, check the `session_id` -- if it matches the last recorded session_id, don't increment.
**Warning signs:** Session counter grows unexpectedly fast (multiple increments per actual session); decay triggers after only 2-3 actual sessions instead of 5.

### Pitfall 5: /ac-review Skill Losing Review State on Long Candidate Lists

**What goes wrong:** User is reviewing 10+ candidates via /ac-review, context window fills up, Claude compacts, and the review state (which candidates were already approved/rejected) is lost.
**Why it happens:** Claude's conversation context is volatile. If the review takes many turns and the context window fills, compaction may lose intermediate decisions.
**How to avoid:** Write each decision to disk immediately (not batched at end). After each approve/reject/edit, update candidates.json and conventions.json atomically. This way, if compaction occurs mid-review, the already-processed candidates are persisted. The skill instructions should mandate "write each decision to disk before proceeding to the next candidate."
**Warning signs:** Approved conventions disappear after context compaction during a long review session; duplicate approvals.

### Pitfall 6: Convention Cap Eviction Without User Awareness

**What goes wrong:** The 50-convention cap silently evicts low-confidence conventions. User doesn't know why a convention disappeared from CLAUDE.md.
**Why it happens:** The cap enforcement happens during injection without notification.
**How to avoid:** Log evictions to changelog.jsonl with reason "evicted: convention cap exceeded, lowest confidence". The /ac-status skill should display how many conventions are active vs. how many are at the cap. If at cap, show which conventions were evicted.
**Warning signs:** User notices a convention they approved is no longer in CLAUDE.md; confusion about missing conventions.

## Code Examples

### Convention Entry Schema (Phase 6 extended)

```json
// conventions.json entry with Phase 6 lifecycle fields
{
  "text": "Use async/await instead of .then() chains",
  "confidence": 0.8,
  "source": "extraction",
  "stage": "active",
  "created_at": "2026-02-25T10:00:00Z",
  "approved_at": "2026-02-25T14:30:00Z",
  "session_id": "abc123",
  "last_referenced_session": 42,
  "observations": 5,
  "sessions_seen": ["abc123", "def456", "ghi789"]
}
```

New fields added by Phase 6:
- `stage`: "observation" | "review_pending" | "active" | "decayed" | "rejected"
- `last_referenced_session`: integer session counter value when last injected into CLAUDE.md
- `approved_at`: ISO 8601 timestamp of user approval (set by /ac-review)

### Candidate Entry Schema (Phase 6 extended)

```json
// candidates.json entry with Phase 6 stage field
{
  "text": "Use camelCase for utility function names",
  "classification": "intentional",
  "confidence": 0.3,
  "source": "extraction",
  "stage": "observation",
  "created_at": "2026-02-25T10:00:00Z",
  "session_id": "abc123",
  "observations": 4,
  "sessions_seen": ["abc123", "def456", "ghi789", "jkl012"],
  "evidence": [
    {"file": "src/utils/formatDate.ts", "line": 5, "snippet": "export function formatDate(date: Date): string {"},
    {"file": "src/utils/parseUrl.ts", "line": 3, "snippet": "export function parseUrl(raw: string): URL {"}
  ]
}
```

### lifecycle.json Schema

```json
{
  "session_count": 42,
  "last_session_id": "abc123",
  "last_promotion_check": 42,
  "last_decay_check": 42,
  "created_at": "2026-02-25T10:00:00Z",
  "updated_at": "2026-02-25T14:30:00Z"
}
```

### changelog.jsonl Entry Format

```jsonl
{"ts":"2026-02-25T14:30:00Z","action":"promoted","text":"Use camelCase for utility function names","reason":"3+ observations across 2+ sessions (4 obs, 3 sessions)","from_stage":"observation","to_stage":"review_pending"}
{"ts":"2026-02-25T14:35:00Z","action":"approved","text":"Use camelCase for utility function names","reason":"user approved via /ac-review","from_stage":"review_pending","to_stage":"active"}
{"ts":"2026-02-28T10:00:00Z","action":"decayed","text":"Use semicolons in JS","reason":"not referenced in 5+ sessions (last: session 37, current: 42)","from_stage":"active","to_stage":"decayed"}
{"ts":"2026-02-28T10:00:00Z","action":"evicted","text":"Prefer arrow functions","reason":"convention cap exceeded (51/50), lowest confidence (0.55)","stage":"active"}
```

### PreCompact Hook Configuration

```json
// Source: https://code.claude.com/docs/en/hooks (PreCompact section)
// PreCompact only supports type: "command" -- no agent or prompt hooks
// PreCompact has no decision control -- cannot block compaction
"PreCompact": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/scripts/preserve-context.sh"
      }
    ]
  }
]
```

### PreCompact Hook Input

```json
// Source: https://code.claude.com/docs/en/hooks (PreCompact input)
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../.claude/projects/.../00893aaf.jsonl",
  "cwd": "/Users/...",
  "permission_mode": "default",
  "hook_event_name": "PreCompact",
  "trigger": "manual",
  "custom_instructions": ""
}
```

### /ac-review SKILL.md Structure

```yaml
---
name: ac-review
description: Review pending convention candidates. Approve, reject, or edit each candidate before it reaches CLAUDE.md.
disable-model-invocation: true
---

# Auto-Context: Review Pending Conventions

Review candidates that have met promotion thresholds (3+ observations across 2+ sessions).
...
```

### /ac-status SKILL.md Structure

```yaml
---
name: ac-status
description: Show auto-context pipeline status including observation counts, candidates, conventions, anti-patterns, and lifecycle statistics.
disable-model-invocation: true
---

# Auto-Context: Status Dashboard

Display the current state of the auto-context pipeline.
...
```

### Updated hooks.json After Phase 6

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/inject-context.sh"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/detect-feedback.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/observe-tool.sh"
          }
        ]
      }
    ],
    "PostToolUseFailure": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/observe-tool.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "agent",
            "prompt": "...(existing Phase 5 extraction agent)...",
            "timeout": 120,
            "statusMessage": "Auto-Context: analyzing session for patterns..."
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/preserve-context.sh"
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-session.sh"
          }
        ]
      }
    ]
  }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|-------------|-----------------|--------------|--------|
| Direct write to conventions.json (Phase 4 explicit feedback) | Explicit feedback still direct (user already approved), extraction goes through lifecycle | Phase 6 | Extraction candidates get review gate; explicit feedback remains instant |
| No session counting | lifecycle.json with monotonic session counter | Phase 6 | Enables cross-session tracking for promotion (LIFE-02) and decay (LIFE-03) |
| Inject all conventions to CLAUDE.md | Filter by stage == "active", sort by confidence, cap at 50 | Phase 6 | Only approved, non-decayed conventions injected; cap prevents token budget overrun |
| No context preservation | PreCompact backup of JSON data files | Phase 6 | Protects convention data from context compaction edge cases |

**Deprecated/outdated:**
- Writing extraction candidates directly to conventions.json: Phase 6 introduces the mandatory review gate. Only /ac-review can move candidates to conventions.json with stage: "active".

## Open Questions

1. **Should the `stage` field live on candidates.json entries or only on conventions.json entries?**
   - What we know: Candidates start as "observation", graduate to "review_pending". Conventions are "active" or "decayed". These are different files.
   - What's unclear: Whether to unify the stage field across both files or keep them separate.
   - Recommendation: Use `stage` on both files. Candidates use stages "observation" and "review_pending". When approved via /ac-review, the entry moves from candidates.json to conventions.json with stage "active". This keeps the state machine clear and queryable with simple jq filters.

2. **Should decayed conventions be automatically deleted or just hidden?**
   - What we know: LIFE-04 says "removed from CLAUDE.md injection" not "deleted from storage."
   - What's unclear: Whether to keep decayed conventions indefinitely or prune them after some time.
   - Recommendation: Keep decayed conventions in conventions.json with `stage: "decayed"`. They serve as audit trail and can be re-activated if the pattern re-emerges. The /ac-status skill should show decayed count. Consider a future cleanup mechanism if the file grows too large (v2 concern).

3. **What confidence should a promoted extraction candidate receive?**
   - What we know: Extraction candidates start at 0.3 (Phase 5). Bootstrap conventions are 0.6-0.9. Explicit feedback is 1.0. After meeting promotion thresholds (3+ observations, 2+ sessions), a candidate has stronger evidence than initial extraction but weaker than explicit feedback.
   - What's unclear: The exact confidence value to assign on promotion.
   - Recommendation: Set confidence to 0.7 on promotion to "active" via /ac-review. This places promoted extraction conventions above bootstrap (0.6-0.9 range midpoint) but below explicit feedback (1.0). Users can also edit the text during review, implicitly confirming with high confidence. The /ac-review skill could let users adjust confidence manually if desired (v2 feature).

4. **How should detect-feedback.sh (Phase 4) be updated for the new stage field?**
   - What we know: Phase 4's detect-feedback.sh writes directly to conventions.json with `confidence: 1.0` and `source: "explicit"`. These are user-stated conventions that don't need the review gate.
   - What's unclear: Whether to add `stage: "active"` to Phase 4's output or handle it as a migration in inject-context.sh.
   - Recommendation: Modify detect-feedback.sh to include `"stage": "active"` and `"last_referenced_session": 0` in new entries. Also handle migration of existing entries in inject-context.sh (add defaults for missing fields). This is cleaner than relying solely on migration.

5. **Should /ac-status be disable-model-invocation or auto-invocable?**
   - What we know: /ac-status is a read-only view of pipeline statistics. It has no side effects and is safe to auto-invoke.
   - What's unclear: Whether users would benefit from Claude automatically showing status (e.g., "I notice you have 5 pending candidates for review").
   - Recommendation: Set `disable-model-invocation: true` for now. Status is a user-initiated check, not something Claude should proactively display. The SessionStart status line (Phase 4) already provides passive awareness. Users invoke /ac-status when they want detailed information.

## Sources

### Primary (HIGH confidence)
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) - PreCompact hook input schema (trigger, custom_instructions), handler type support (PreCompact only supports type: "command"), decision control matrix (PreCompact has none), SessionStart matcher values (startup, resume, clear, compact), hook lifecycle ordering
- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills) - SKILL.md frontmatter format (name, description, disable-model-invocation, allowed-tools, context, agent), skill directory structure, $ARGUMENTS substitution, plugin skill namespacing, skill invocation control (disable-model-invocation vs user-invocable)
- Existing codebase: `hooks/hooks.json`, `scripts/inject-context.sh`, `scripts/detect-feedback.sh`, `scripts/cleanup-session.sh`, `agents/extract-patterns.md`, `skills/ac-init/SKILL.md`, `skills/ac-reset/SKILL.md` - Verified current data schemas, hook patterns, skill patterns, conventions.json format, candidates.json format

### Secondary (MEDIUM confidence)
- Phase 5 Research (`.planning/phases/05-pattern-extraction/05-RESEARCH.md`) - Candidate JSON schema (observations, sessions_seen, evidence, classification fields), extraction agent architecture, Stop hook patterns
- Phase 5 Plan 02 (`.planning/phases/05-pattern-extraction/05-02-PLAN.md`) - Hook registration patterns, session log archive approach
- `.planning/REQUIREMENTS.md` - Full requirement definitions for LIFE-01 through LIFE-06, TRNS-01, TRNS-02, TRNS-05, PRSC-01, PRSC-02
- `.planning/ROADMAP.md` - Phase 6 success criteria, dependency chain, planned plan breakdown (3 plans)
- `.planning/STATE.md` - Project decisions history, accumulated context from Phases 1-5

### Tertiary (LOW confidence)
- None. All critical claims verified with official docs or existing codebase.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All tools (Bash, jq, Skills) are the same as Phases 1-5. No new dependencies. PreCompact hook type constraint verified from official docs.
- Architecture: HIGH - Lifecycle state machine is straightforward deterministic logic. Data schemas extend existing Phase 5 structures with minimal new fields. Skills follow the exact same pattern as existing ac-init and ac-reset.
- Pitfalls: HIGH - Backward compatibility, race conditions, and decay timing issues identified from analyzing existing code flow. PreCompact constraint verified from official docs. Session counter gotchas identified from SessionStart matcher documentation.
- Code examples: HIGH - JSON schemas extend verified Phase 5 schemas. Hook configuration follows verified patterns from existing hooks.json. SKILL.md patterns based on official documentation.

**Research date:** 2026-02-25
**Valid until:** 2026-03-25 (hook system and skill system are stable; 30-day validity appropriate)
