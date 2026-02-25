# Phase 7: Anti-Patterns & Reward Signals - Research

**Researched:** 2026-02-25
**Domain:** Implicit correction detection (Write->Edit pair analysis), cross-session error tracking, anti-pattern storage/injection, reward signal computation with explicit/implicit weighting, /ac-status reward display
**Confidence:** HIGH

## Summary

Phase 7 adds two complementary signal systems to auto-context: anti-pattern detection (what Claude should NOT do) and reward signals (measuring convention quality through feedback). These systems depend on the session observation layer (Phase 3) for raw event data and the convention lifecycle (Phase 6) for confidence scoring integration.

Anti-pattern detection operates at three levels: (1) implicit detection of user corrections via Write->Edit sequences on the same file within a session -- where Claude writes something and the user immediately edits it, signaling a correction; (2) cross-session error pattern tracking -- the same bash error occurring 2+ times across different sessions flags a strong negative signal; and (3) explicit "don't do this" feedback, which is already captured by Phase 4's `detect-feedback.sh` but needs to be surfaced in CLAUDE.md injection. The critical insight is that ANTI-03 (explicit anti-patterns) is already partially implemented -- Phase 4 writes anti-patterns to `anti-patterns.json`. Phase 7 adds the implicit detection mechanisms and ensures anti-patterns are injected into CLAUDE.md.

Reward signals combine implicit signals (Write->Edit pair analysis: files that Claude writes and are NOT subsequently edited by the user represent positive implicit feedback) with explicit signals (10x weight per FDBK-03) to produce a composite confidence score for conventions. The reward history is stored in `.auto-context/rewards.json` and displayed via `/ac-status`. The Stop hook agent (Phase 5) is the natural place for Write->Edit pair analysis since it already processes the session log at session end. The existing extraction agent prompt can be extended to also perform correction detection and reward signal computation in the same pass.

**Primary recommendation:** Extend the existing Stop hook extraction agent to also analyze Write->Edit sequences for correction detection and reward signal computation. Add a dedicated `scripts/lib/anti-patterns.sh` library for cross-session error tracking (run at SessionStart). Modify `inject-context.sh` to include anti-patterns in CLAUDE.md injection. Create `rewards.json` for reward history and update `/ac-status` to display signal quality breakdown.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| ANTI-01 | Detect user correction patterns (Write->Edit sequences with semantic change) as negative signals | Session log already captures `file_write` and `file_edit` events with file paths and timestamps. The Stop hook extraction agent can analyze the session log for Write->Edit pairs on the same file path. A Write followed by an Edit on the same file within the same session (especially if the Write was Claude's and the Edit was a user correction) signals a negative pattern. The agent writes detected corrections to `anti-patterns.json`. |
| ANTI-02 | Detect repeated error patterns across sessions (same error 2+ times = strong negative) | Session log captures `bash_error` events with command and error message (truncated to 200 chars). At SessionStart, a shell script can scan the current `anti-patterns.json` for error-sourced entries and match against new session errors. Alternatively, the Stop hook agent can check for recurring error patterns by reading historical error data from `anti-patterns.json`. Cross-session tracking requires persistent storage -- `anti-patterns.json` already exists and stores error patterns with session_id. |
| ANTI-03 | Auto-register anti-patterns from explicit "don't do this" feedback | Already implemented in Phase 4 (`detect-feedback.sh`) -- explicit "don't do this" feedback is written to `anti-patterns.json` with `confidence: 1.0, source: "explicit", stage: "active"`. Phase 7 ensures these are injected into CLAUDE.md alongside conventions. |
| ANTI-04 | Anti-patterns stored in `.auto-context/anti-patterns.json` and injected into CLAUDE.md | `anti-patterns.json` already exists (initialized in Phase 1, written to by Phase 4). Phase 7 modifies `inject-context.sh` to read anti-patterns and include them in the CLAUDE.md marker section as a "Do NOT" list, separate from conventions. Token budget must account for both conventions and anti-patterns. |
| RWRD-01 | Track Write->Edit pair analysis as implicit reward signal at Stop hook | The Stop hook extraction agent analyzes `session-log.jsonl` at session end. Files that were written by Claude and NOT edited afterward represent positive implicit signals (Claude got it right). Files that were written then edited represent negative signals (correction needed). The agent computes per-session reward metrics and writes to `rewards.json`. |
| RWRD-02 | Combine explicit feedback (10x weight) with implicit signals for convention confidence scoring | Explicit feedback events in session log have `event: "explicit_feedback"`. These are weighted 10x versus implicit signals. The reward computation formula: `composite_score = (implicit_signals * 1 + explicit_signals * 10) / (implicit_count + explicit_count * 10)`. This composite score can adjust convention confidence over time. |
| RWRD-03 | Store reward history in `.auto-context/rewards.json` | New JSON file tracking per-session reward summaries: session_id, timestamp, implicit positive/negative counts, explicit positive/negative counts, composite score. Append-style array (or JSONL for consistency with session-log). |
| RWRD-04 | Display signal quality breakdown in /ac-status | Update `/ac-status` SKILL.md to read `rewards.json` and display: total sessions tracked, implicit signal counts (positive/negative), explicit signal counts, average composite score, trend (improving/stable/declining based on last 5 sessions). Replace the current placeholder "Reward tracking: pending Phase 7". |
</phase_requirements>

## Standard Stack

### Core

| Library/Tool | Version | Purpose | Why Standard |
|-------------|---------|---------|--------------|
| Bash | 3.2+ (macOS) / 5.x (Linux) | Anti-pattern tracking shell scripts, injection modifications | Consistent with Phases 1-6; all command hooks are shell scripts |
| jq | 1.6+ | JSON manipulation for anti-pattern storage, reward computation, session log analysis | Already required by all phases; handles atomic JSON updates, array filtering, aggregation |
| Stop hook agent (extract-patterns.md) | Current | Extended to perform Write->Edit pair analysis and reward signal computation | Already runs at session end and reads session-log.jsonl; natural extension point |

### Supporting

| Library/Tool | Version | Purpose | When to Use |
|-------------|---------|---------|-------------|
| date | POSIX | ISO 8601 timestamps for reward entries and anti-pattern timestamps | Every new entry needs a timestamp |
| SKILL.md (ac-status) | Current | Updated to display reward signals and anti-pattern breakdown | User invokes /ac-status |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|-----------|-----------|----------|
| Extending Stop hook agent for Write->Edit analysis | Separate dedicated agent hook | Adding another agent hook increases LLM cost and session-end latency. The existing extraction agent already reads the session log -- adding correction detection is a natural extension. One agent, one pass. |
| Shell script for cross-session error tracking | Agent-based error analysis | Error pattern matching is deterministic (string comparison on error messages). Shell + jq is faster, cheaper, and more predictable than LLM reasoning for this task. |
| JSONL for rewards.json | JSON array for rewards.json | JSON array allows easier aggregation with jq (sort, slice, average). JSONL is better for append-only. Since reward entries are written once per session (not high-frequency), JSON array is acceptable and simpler for /ac-status reads. Use JSON array. |
| Splitting token budget between conventions and anti-patterns | Separate token budgets | Single unified budget (1000 tokens) forces prioritization. Anti-patterns should consume a fixed small allocation (e.g., max 200 tokens) with conventions using the remainder. This avoids complexity of dual budgets. |

**Installation:**
```bash
# No new dependencies -- Bash and jq already required by Phases 1-6
```

## Architecture Patterns

### Recommended Project Structure (Phase 7 additions)

```
auto-context/
├── hooks/
│   └── hooks.json                    # NO CHANGES (Stop hook already registered)
├── scripts/
│   ├── inject-context.sh             # MODIFY: add anti-pattern injection into CLAUDE.md
│   ├── observe-tool.sh               # EXISTING (Phase 3) -- no changes needed
│   ├── cleanup-session.sh            # EXISTING (Phase 5) -- no changes needed
│   ├── detect-feedback.sh            # EXISTING (Phase 4) -- no changes needed
│   ├── preserve-context.sh           # MODIFY: add rewards.json to backup list
│   └── lib/
│       ├── markers.sh                # EXISTING (Phase 1)
│       ├── tokens.sh                 # EXISTING (Phase 1)
│       └── lifecycle.sh              # EXISTING (Phase 6)
├── agents/
│   └── extract-patterns.md           # MODIFY: add correction detection and reward signal sections
├── skills/
│   ├── ac-status/
│   │   └── SKILL.md                  # MODIFY: add reward signal display section
│   └── ...                           # EXISTING skills unchanged
└── .auto-context/                    # Runtime data store (in user's project)
    ├── conventions.json              # EXISTING
    ├── candidates.json               # EXISTING
    ├── anti-patterns.json            # MODIFY: enhanced schema with source tracking
    ├── rewards.json                  # NEW: reward signal history
    ├── config.json                   # EXISTING
    ├── lifecycle.json                # EXISTING
    ├── changelog.jsonl               # EXISTING
    └── session-log.jsonl             # EXISTING
```

### Pattern 1: Write->Edit Correction Detection (Stop Hook Agent)

**What:** The extraction agent analyzes session log for Write->Edit pairs on the same file. A Write followed by an Edit on the same file within the session indicates Claude wrote something that the user (or Claude itself) then corrected.
**When to use:** Runs as part of the Stop hook agent at session end, alongside pattern extraction.

**Algorithm:**
1. Read all `file_write` and `file_edit` events from session-log.jsonl
2. Group by file path
3. For each file that has BOTH a Write event followed by an Edit event:
   - This is a potential correction (negative signal)
   - Record as an anti-pattern candidate with `source: "correction"`, `confidence: 0.5`
4. For each file that has a Write event but NO subsequent Edit:
   - This is a positive implicit signal (Claude got it right first time)
   - Record in reward signals

**Key distinction:** Not all Write->Edit sequences are corrections. Claude itself often writes then edits within its own turn (normal workflow). The agent should focus on patterns where a Write is followed by an Edit that appears in a later turn or has meaningful semantic change. The simplest heuristic: if a file_write and file_edit appear for the same file, check if there were other events (like user prompts or bash commands) between them. If yes, the edit is more likely a user-driven correction.

**Example session log analysis:**
```jsonl
{"ts":"...","event":"file_write","tool":"Write","file":"src/app.ts","session_id":"abc"}
{"ts":"...","event":"bash_command","tool":"Bash","command":"npm test","session_id":"abc"}
{"ts":"...","event":"file_edit","tool":"Edit","file":"src/app.ts","session_id":"abc"}
```
The Write->Bash->Edit sequence on `src/app.ts` suggests: Claude wrote something, tested it, then needed to fix it. This is a correction signal.

```jsonl
{"ts":"...","event":"file_write","tool":"Write","file":"src/new-file.ts","session_id":"abc"}
{"ts":"...","event":"file_write","tool":"Write","file":"src/another.ts","session_id":"abc"}
```
Files written without subsequent edits -- positive implicit signals.

### Pattern 2: Cross-Session Error Tracking

**What:** Track bash errors across sessions and flag recurring patterns as strong negative signals.
**When to use:** The Stop hook agent (or a separate session-end analysis) checks current session errors against historical anti-patterns. SessionStart is also a viable check point.

**Algorithm:**
1. At Stop hook, the agent reads `bash_error` events from session-log.jsonl
2. For each error, normalize the error message (strip paths, line numbers, variable values)
3. Check against existing entries in `anti-patterns.json` with `source: "error"`
4. If a matching error pattern already exists:
   - Increment `occurrences` count
   - If occurrences >= 2 AND from 2+ different sessions: mark as `strong_negative: true`
5. If new error pattern: add to `anti-patterns.json` with `source: "error"`, `occurrences: 1`

**Simplification for v1:** Since the extraction agent already runs at Stop and reads the session log, it can perform error analysis in the same pass. The normalized error key can be a truncated error message (first 100 chars, stripped of path-specific content).

### Pattern 3: Anti-Pattern Injection into CLAUDE.md

**What:** Modify `inject-context.sh` to include anti-patterns in the CLAUDE.md auto-context section.
**When to use:** Every SessionStart, after conventions are injected.

**Layout within marker section:**
```markdown
## Project Conventions (Auto-Context)

- Use async/await instead of .then() chains
- Prefer camelCase for utility function names

## Do NOT (Auto-Context)

- Don't use var; always use const or let
- Don't commit .env files to git

_Auto-generated by auto-context plugin. Do not edit between markers._
```

**Token budget allocation:**
- Total budget: 1000 tokens (from config.json)
- Anti-patterns: up to 200 tokens (hard sub-limit)
- Conventions: remaining budget (800+ tokens)
- If anti-patterns exceed 200 tokens, truncate to most confident ones

### Pattern 4: Reward Signal Computation

**What:** Compute a per-session reward score from implicit and explicit signals.
**When to use:** At Stop hook (session end), after correction detection and pattern extraction.

**Formula:**
```
implicit_positive = count of files written but NOT subsequently edited
implicit_negative = count of files written then edited (corrections)
explicit_positive = count of explicit "remember this" feedback events
explicit_negative = count of explicit "don't do this" feedback events

# Raw scores (explicit weighted 10x per FDBK-03)
weighted_positive = implicit_positive + (explicit_positive * 10)
weighted_negative = implicit_negative + (explicit_negative * 10)

# Session reward score (0.0 to 1.0)
total = weighted_positive + weighted_negative
reward_score = weighted_positive / total  (if total > 0, else 0.5)
```

**Reward entry schema:**
```json
{
  "session_id": "abc123",
  "ts": "2026-02-25T15:00:00Z",
  "implicit_positive": 5,
  "implicit_negative": 2,
  "explicit_positive": 1,
  "explicit_negative": 0,
  "reward_score": 0.88,
  "files_analyzed": 7
}
```

### Pattern 5: Reward-Adjusted Convention Confidence

**What:** Use reward signals to adjust convention confidence scores over time.
**When to use:** When computing the reward score, the agent can optionally update conventions' confidence if specific patterns correlate with reward signals. For v1, this is informational only -- confidence adjustments based on reward signals are tracked but not automatically applied (similar to the review gate philosophy).

**v1 approach:** Store reward data. Display in /ac-status. Do NOT automatically modify convention confidence based on reward signals. Phase 8 (smart injection) may use reward data for prioritization.

### Anti-Patterns to Avoid

- **Treating every Write->Edit as a correction:** Claude frequently writes a file then edits it as part of normal multi-step work. Only flag Write->Edit pairs that have intervening events (user prompts, bash commands, other file operations) as potential corrections. A Write immediately followed by an Edit on the same file in the same tool-use sequence is normal Claude workflow, not a user correction.
- **Duplicating error messages verbatim as anti-patterns:** Error messages contain paths, line numbers, and other session-specific data. Normalize errors before comparison (strip absolute paths, line numbers, timestamps) to detect the PATTERN, not the specific instance.
- **Injecting anti-patterns without confidence filtering:** Not all detected corrections warrant injection into CLAUDE.md. Only anti-patterns with `stage: "active"` and sufficient confidence (explicit: 1.0, or recurring corrections: 0.7+) should be injected.
- **Modifying the observation hook (observe-tool.sh) for Phase 7:** The observation hook must stay under 100ms. All analysis belongs in the Stop hook agent or SessionStart. Never add analysis logic to PostToolUse handlers.
- **Running reward computation in a separate agent hook:** One agent invocation per session is enough. Extend the existing extraction agent to also handle rewards and corrections. Two agent hooks double the LLM cost and session-end latency.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Error message normalization | Custom regex for every error format | Simple truncation + path stripping | Error formats are infinite; simple normalization (strip paths via sed, truncate to 100 chars) catches 80% of recurring patterns without complex parsing |
| Reward score aggregation | Custom shell arithmetic for floating point | jq arithmetic (`add / length`) | Bash cannot do floating-point division natively; jq handles it correctly |
| Anti-pattern deduplication | Custom string matching | jq `select` with text matching | jq's string operations handle JSON-safe comparison correctly |
| Token budget splitting | Manual character counting for each section | Reuse existing `enforce_budget` from `lib/tokens.sh` | Apply budget enforcement separately to conventions and anti-patterns sections |

**Key insight:** Phase 7 adds intelligence to the data layer, not new hooks. The hook infrastructure from Phases 3-6 is complete. Phase 7 extends the Stop hook agent's analysis capabilities and modifies the injection script to include anti-patterns. The new logic is mostly in the agent prompt (LLM reasoning for correction detection) and shell scripts (deterministic reward computation and injection).

## Common Pitfalls

### Pitfall 1: False Positive Corrections from Normal Claude Workflow

**What goes wrong:** Every Write->Edit pair is flagged as a correction, flooding `anti-patterns.json` with false positives.
**Why it happens:** Claude commonly writes a file, then immediately edits it to refine or extend. This is normal workflow, not a user correction.
**How to avoid:** The agent should apply a heuristic: only flag Write->Edit pairs where there is at least one intervening event of a different type (bash_command, explicit_feedback, file_write to a DIFFERENT file) between the Write and Edit on the same file. Direct Write->Edit on the same file with no intervening events is likely Claude's own refinement.
**Warning signs:** anti-patterns.json grows with dozens of low-quality "correction" entries per session; /ac-status shows overwhelming negative signals.

### Pitfall 2: Token Budget Overflow from Anti-Pattern Injection

**What goes wrong:** Adding anti-patterns to CLAUDE.md pushes the total content over the 1000-token budget, causing convention truncation.
**Why it happens:** The current injection logic uses the full budget for conventions. Adding anti-patterns without reserving budget space causes both sections to compete.
**How to avoid:** Allocate a fixed sub-budget for anti-patterns (200 tokens). Build the anti-pattern section first, measure its token usage, then give the remaining budget to conventions. Use the existing `enforce_budget` function from `lib/tokens.sh` for each section.
**Warning signs:** Conventions disappearing from CLAUDE.md after anti-patterns are added; "[truncated]" appearing in the auto-context section.

### Pitfall 3: Cross-Session Error Deduplication Producing False Matches

**What goes wrong:** Different errors with similar messages are treated as the same recurring error.
**Why it happens:** Over-aggressive normalization strips too much context from error messages, making unrelated errors appear identical.
**How to avoid:** Normalize by stripping absolute paths and line numbers, but preserve the error type/category and the core message. Use a similarity threshold rather than exact match. For v1, keep it simple: strip leading path components and trailing line numbers, compare the first 100 characters.
**Warning signs:** A single "generic" error anti-pattern accumulates occurrences from many different actual errors.

### Pitfall 4: Reward Score Dominated by Implicit Signals

**What goes wrong:** In sessions with many file operations but no explicit feedback, the reward score is entirely driven by implicit signals, which are noisy.
**Why it happens:** Implicit signals (Write->Edit analysis) produce many data points per session, while explicit feedback is rare (maybe 0-1 per session).
**How to avoid:** The 10x weighting on explicit signals already addresses this. Additionally, treat sessions with zero explicit feedback as lower-confidence reward signals. The /ac-status display should show implicit vs. explicit contribution separately so users can evaluate signal quality.
**Warning signs:** Reward scores fluctuating wildly between sessions; scores inconsistent with user perception of Claude's quality.

### Pitfall 5: Anti-Pattern Injection Breaking Existing CLAUDE.md Layout

**What goes wrong:** Adding a "Do NOT" section changes the marker section structure, causing existing tests or assertions about CLAUDE.md content to fail.
**Why it happens:** The injection logic in `inject-context.sh` currently produces a single markdown section. Adding anti-patterns requires a second section within the markers.
**How to avoid:** Build the complete content (conventions + anti-patterns) as a single string before calling `inject_content`. The marker system replaces everything between markers, so the internal structure does not matter as long as it is valid markdown. Test with both conventions-only and conventions+anti-patterns scenarios.
**Warning signs:** CLAUDE.md showing only anti-patterns (conventions lost) or only conventions (anti-patterns lost).

### Pitfall 6: Extraction Agent Timeout from Extended Responsibilities

**What goes wrong:** Adding correction detection and reward computation to the extraction agent causes it to exceed the 120-second timeout.
**Why it happens:** The agent now does three tasks: pattern extraction, correction detection, and reward computation. With complex sessions, this may take too long.
**How to avoid:** The correction detection and reward computation are simpler than pattern extraction (they operate on metadata, not code content). Structure the agent prompt so correction/reward analysis happens first (fast, metadata-only), then pattern extraction (slower, requires file reads). If timeout is a concern, increase to 180 seconds. The agent should prioritize completing reward/correction writes before starting extraction.
**Warning signs:** Stop hook timeout errors; rewards.json not being written; partial extraction results.

## Code Examples

### Anti-Pattern Entry Schema (Enhanced for Phase 7)

```json
// anti-patterns.json entry
{
  "text": "Don't use var; always use const or let",
  "confidence": 1.0,
  "source": "explicit",
  "created_at": "2026-02-25T10:00:00Z",
  "session_id": "abc123",
  "stage": "active",
  "last_referenced_session": 0
}
```

New source types added by Phase 7:
```json
// Correction-detected anti-pattern
{
  "text": "Avoid using synchronous fs.readFileSync in API handlers",
  "confidence": 0.5,
  "source": "correction",
  "created_at": "2026-02-25T10:00:00Z",
  "session_id": "abc123",
  "stage": "active",
  "occurrences": 1,
  "last_referenced_session": 0,
  "evidence": [
    {"file": "src/api/handler.ts", "write_ts": "...", "edit_ts": "..."}
  ]
}

// Error-detected anti-pattern
{
  "text": "npm test fails with missing module error in test setup",
  "confidence": 0.3,
  "source": "error",
  "created_at": "2026-02-25T10:00:00Z",
  "session_id": "abc123",
  "stage": "observation",
  "occurrences": 1,
  "sessions_seen": ["abc123"],
  "error_pattern": "Cannot find module",
  "last_referenced_session": 0
}
```

Stage values for anti-patterns:
- `"observation"`: First occurrence of an error-detected anti-pattern (occurrences < 2 or sessions < 2)
- `"active"`: Confirmed anti-pattern -- either explicit (source: "explicit"), or recurring error (2+ occurrences across 2+ sessions), or confirmed correction. Injected into CLAUDE.md.
- `"decayed"`: Not observed in recent sessions (future consideration; not required for v1)

### rewards.json Schema

```json
[
  {
    "session_id": "abc123",
    "ts": "2026-02-25T15:00:00Z",
    "implicit_positive": 5,
    "implicit_negative": 2,
    "explicit_positive": 1,
    "explicit_negative": 0,
    "reward_score": 0.88,
    "files_analyzed": 7,
    "details": {
      "files_written_no_edit": ["src/app.ts", "src/utils.ts", "src/config.ts", "src/index.ts", "README.md"],
      "files_written_then_edited": ["src/api/handler.ts", "src/tests/setup.ts"]
    }
  }
]
```

### Modified inject-context.sh Injection Logic (Pseudocode)

```bash
# --- Anti-Pattern Injection (Phase 7) ---
AP_ACTIVE=$(jq '[.[] | select(.stage == "active")] | sort_by(-.confidence)' "$STORE_DIR/anti-patterns.json" 2>/dev/null || echo "[]")
AP_COUNT=$(echo "$AP_ACTIVE" | jq 'length')

# Build anti-pattern markdown section
AP_CONTENT=""
if [ "$AP_COUNT" -gt 0 ]; then
  AP_CONTENT=$(echo "$AP_ACTIVE" | jq -r '"## Do NOT (Auto-Context)\n\n" + (map("- " + .text) | join("\n"))')
  # Enforce anti-pattern sub-budget (200 tokens)
  AP_CONTENT=$(enforce_budget "$AP_CONTENT" 200)
fi

# Calculate remaining budget for conventions
AP_TOKENS=$(estimate_tokens "$AP_CONTENT")
CONV_BUDGET=$((TOKEN_BUDGET - AP_TOKENS - 50))  # 50 token buffer for footer

# Build convention section (existing logic but with adjusted budget)
CONV_CONTENT=""
if [ "$CONV_COUNT" -gt 0 ]; then
  CONV_CONTENT=$(echo "$ACTIVE_CONVS" | jq -r '"## Project Conventions (Auto-Context)\n\n" + (map("- " + .text) | join("\n"))')
  CONV_CONTENT=$(enforce_budget "$CONV_CONTENT" "$CONV_BUDGET")
fi

# Combine and inject
FULL_CONTENT="${CONV_CONTENT}"
[ -n "$AP_CONTENT" ] && FULL_CONTENT="${FULL_CONTENT}\n\n${AP_CONTENT}"
FULL_CONTENT="${FULL_CONTENT}\n\n_Auto-generated by auto-context plugin. Do not edit between markers._"

inject_content "$CLAUDE_MD" "$FULL_CONTENT"
```

### Extraction Agent Extension (Correction Detection Section)

```markdown
## Correction Detection (Phase 7)

After completing pattern extraction, analyze the session log for correction signals.

### Write->Edit Pair Analysis

1. Collect all `file_write` and `file_edit` events from the session log
2. Group events by file path
3. For each file that has BOTH a `file_write` AND a subsequent `file_edit`:
   a. Check if there are intervening events between the Write and Edit:
      - Other file operations, bash commands, or explicit feedback events
   b. If YES (intervening events exist): this is a potential correction
      - Use the Read tool to examine the file's current state
      - Determine what was likely corrected (naming, logic, approach)
      - Write a concise anti-pattern description to anti-patterns.json
      - Set: source="correction", confidence=0.5, stage="active", occurrences=1
   c. If NO (Write immediately followed by Edit with no gap): likely normal Claude refinement -- skip
4. Files that were written but NEVER edited afterward are positive implicit signals

### Error Pattern Analysis

1. Collect all `bash_error` events from the session log
2. For each error, extract a normalized error key:
   - Strip absolute path prefixes
   - Strip line numbers and column numbers
   - Keep the first 100 characters of the error message
3. Read existing anti-patterns.json and look for entries with source="error"
4. For each error in the current session:
   a. If a matching error pattern exists: increment occurrences, add session_id to sessions_seen
   b. If occurrences >= 2 AND sessions_seen has 2+ unique sessions: set stage="active"
   c. If no match: add new entry with source="error", stage="observation", occurrences=1

### Reward Signal Computation

After correction detection, compute the session reward score:

1. Count implicit signals:
   - implicit_positive = files written but not subsequently edited
   - implicit_negative = files written then edited (corrections detected above)
2. Count explicit signals from session log:
   - explicit_positive = count of explicit_feedback events with type="convention"
   - explicit_negative = count of explicit_feedback events with type="anti-pattern"
3. Compute weighted score:
   - weighted_positive = implicit_positive + (explicit_positive * 10)
   - weighted_negative = implicit_negative + (explicit_negative * 10)
   - total = weighted_positive + weighted_negative
   - reward_score = weighted_positive / total (if total > 0, else 0.5)
4. Write reward entry to rewards.json (read existing array, append new entry, write atomically)
```

### Updated /ac-status Reward Section

```markdown
### Reward Signals
```

Read `.auto-context/rewards.json`. If missing or empty:
```
- Reward tracking: no data yet (accumulates over sessions)
```

If data exists, compute and display:
```bash
# Total sessions tracked
jq 'length' .auto-context/rewards.json

# Average reward score
jq '[.[].reward_score] | add / length' .auto-context/rewards.json

# Recent trend (last 5 sessions)
jq '[-5:] | [.[].reward_score]' .auto-context/rewards.json

# Signal breakdown (totals)
jq '{implicit_pos: [.[].implicit_positive] | add, implicit_neg: [.[].implicit_negative] | add, explicit_pos: [.[].explicit_positive] | add, explicit_neg: [.[].explicit_negative] | add}' .auto-context/rewards.json
```

Format as:
```
### Reward Signals ({sessions_tracked} sessions)
- Average reward score: {avg_score} (1.0 = perfect, 0.0 = all corrections)
- Implicit signals: {impl_pos} positive / {impl_neg} negative
- Explicit signals: {expl_pos} positive / {expl_neg} negative
- Recent trend (last 5): {score1}, {score2}, {score3}, {score4}, {score5}
  {trend_emoji: improving/stable/declining}
```

### Modified preserve-context.sh (Add rewards.json)

```bash
# Back up critical data files (add rewards.json to list)
for f in conventions.json candidates.json anti-patterns.json lifecycle.json rewards.json; do
  [ -f "$STORE_DIR/$f" ] && cp "$STORE_DIR/$f" "$BACKUP_DIR/$f" 2>/dev/null || true
done
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|-------------|-----------------|--------------|--------|
| Anti-patterns only from explicit feedback (Phase 4) | Three sources: explicit, correction detection, error tracking | Phase 7 | Broader anti-pattern coverage; implicit signals complement explicit |
| No reward signals | Per-session reward score from implicit + explicit signals | Phase 7 | Enables confidence calibration and quality trending |
| CLAUDE.md injection: conventions only | Conventions + anti-patterns in marker section | Phase 7 | Claude sees both "do" and "don't" guidance |
| /ac-status reward section: placeholder | Live reward data with trend display | Phase 7 | Users can see signal quality and trends |
| Extraction agent: pattern extraction only | Pattern extraction + correction detection + reward computation | Phase 7 | Single agent pass at session end handles all analysis |

**Deprecated/outdated:**
- The placeholder text "Reward tracking: pending Phase 7" in /ac-status SKILL.md will be replaced with live reward data display logic.

## Open Questions

1. **Should correction-detected anti-patterns go through a review gate like extraction conventions?**
   - What we know: Explicit anti-patterns (from Phase 4) bypass review because the user already stated them. Correction-detected anti-patterns are implicit and may have false positives.
   - What's unclear: Whether false positive rate is high enough to warrant a review gate, or if the confidence threshold (0.5 for corrections, elevated to 0.7 on recurrence) is sufficient filtering.
   - Recommendation: For v1, correction-detected anti-patterns with confidence < 0.7 should NOT be injected into CLAUDE.md but should be stored and visible in /ac-status. Only explicit anti-patterns (confidence 1.0) and recurring corrections/errors that reach confidence 0.7+ get injected. This is conservative and avoids flooding CLAUDE.md with false negatives.

2. **Should rewards.json be a JSON array or JSONL?**
   - What we know: The extraction agent writes reward entries. The /ac-status skill reads and aggregates them. Session-log uses JSONL for O(1) appends. Conventions/candidates use JSON arrays for jq filtering.
   - What's unclear: Whether the append pattern (agent writes one entry per session) or the read pattern (ac-status aggregates all entries) is the priority.
   - Recommendation: Use JSON array. Rewards are written once per session (low frequency), and ac-status needs to aggregate across all sessions (jq operations on arrays are simpler than JSONL aggregation). The agent reads the existing array, appends, and writes atomically (same pattern as conventions.json).

3. **How should the extraction agent handle sessions with no file writes?**
   - What we know: Some sessions may be entirely conversational (no tool use) or bash-only (no file writes/edits). The extraction agent already handles sparse sessions with the minimum 3-event threshold.
   - What's unclear: Whether to write a reward entry for sessions with no implicit signals.
   - Recommendation: Write a reward entry even for zero-signal sessions (all counts set to 0, reward_score = 0.5 as neutral default). This keeps the session count accurate and avoids gaps in the reward history.

4. **What is the right confidence progression for error-detected anti-patterns?**
   - What we know: Explicit anti-patterns get confidence 1.0. Extraction candidates start at 0.3. Bootstrap conventions are 0.6-0.9.
   - What's unclear: The exact confidence values for the error detection progression.
   - Recommendation: First occurrence: 0.3 (observation stage). Second occurrence from same session: 0.4. Second occurrence from different session: 0.6 (strong negative per ANTI-02). Third+ cross-session occurrence: 0.7 (active, eligible for injection). This mirrors the extraction lifecycle but for negative signals.

## Sources

### Primary (HIGH confidence)
- Existing codebase: `scripts/observe-tool.sh` (session log event format: `file_write`, `file_edit`, `bash_error`, `bash_command` with timestamps and file paths), `scripts/detect-feedback.sh` (explicit anti-pattern detection already writing to `anti-patterns.json`), `scripts/inject-context.sh` (current injection logic, token budget enforcement), `scripts/lib/lifecycle.sh` (lifecycle helper functions), `agents/extract-patterns.md` (current extraction agent prompt structure), `skills/ac-status/SKILL.md` (current status display with reward placeholder), `hooks/hooks.json` (complete hook configuration)
- `.planning/REQUIREMENTS.md` -- Full requirement definitions for ANTI-01 through ANTI-04, RWRD-01 through RWRD-04, FDBK-03 (10x weighting)
- `.planning/ROADMAP.md` -- Phase 7 success criteria and plan breakdown
- Phase 3 Research (`.planning/phases/03-session-observation/03-RESEARCH.md`) -- Session log event schemas, PostToolUse input fields, observation patterns
- Phase 6 Research (`.planning/phases/06-convention-lifecycle-review/06-RESEARCH.md`) -- Convention lifecycle patterns, anti-pattern storage, changelog patterns, PreCompact backup

### Secondary (MEDIUM confidence)
- `.planning/STATE.md` -- Accumulated project decisions from Phases 1-6, including anti-pattern count display decision, session counter patterns, jq atomic write patterns
- Recommender system literature on [implicit vs explicit feedback weighting](https://apxml.com/courses/building-ml-recommendation-system/chapter-1-foundations-of-recommendation-systems/implicit-vs-explicit-feedback) -- Validated the 10x weighting approach for explicit signals (consistent with FDBK-03 requirement)

### Tertiary (LOW confidence)
- None. All critical claims verified against existing codebase and official requirements.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Same Bash+jq stack as all previous phases. No new dependencies. Extension of existing Stop hook agent, not new hooks.
- Architecture: HIGH - Session log event format verified from existing `observe-tool.sh`. Anti-pattern storage format verified from existing `detect-feedback.sh`. Injection logic verified from existing `inject-context.sh`. All patterns extend verified Phase 3/4/5/6 implementations.
- Pitfalls: HIGH - False positive correction detection is the primary risk; mitigation strategy (intervening event heuristic) is well-defined. Token budget competition is addressable with sub-budget allocation. Agent timeout risk is mitigable by prioritizing reward/correction work before extraction.
- Code examples: HIGH - All schemas extend existing verified data structures. Injection patterns follow established `inject-context.sh` idioms. Agent prompt extension follows established `extract-patterns.md` patterns.

**Research date:** 2026-02-25
**Valid until:** 2026-03-25 (no external dependencies to go stale; 30-day validity appropriate)
