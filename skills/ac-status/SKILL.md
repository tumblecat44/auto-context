---
name: ac-status
description: Show auto-context pipeline status including observation counts, candidates, conventions, anti-patterns, and lifecycle statistics.
disable-model-invocation: true
---

# Auto-Context: Pipeline Status

Display the full auto-context pipeline status dashboard. This is a **read-only** skill -- never modify any data files.

**Important rules:**
- Use `jq` for all JSON reading and counting.
- Handle missing fields with jq `//` alternative operator.
- If any jq command fails (corrupted JSON), show "Error reading {file}" instead of crashing.
- Never write to or modify any data files.

---

## Step 1: Read Pipeline Data

Read the following files from `.auto-context/` in the project root:
- `conventions.json` -- convention entries with stage field
- `candidates.json` -- candidate entries with stage and observations
- `anti-patterns.json` -- anti-pattern entries
- `lifecycle.json` -- session counter and metadata
- `config.json` -- token budget configuration

If the `.auto-context/` directory does not exist, tell the user:

> Auto-context is not initialized. Run `/ac-init` first.

And stop.

Handle missing individual files gracefully (treat as empty arrays or default objects).

---

## Step 2: Gather Counts

Use these jq commands to gather counts:

```bash
# Session info
jq -r '.session_count // 0' .auto-context/lifecycle.json
jq -r '.token_budget // 1000' .auto-context/config.json

# Convention counts by stage
jq '[.[] | select(.stage == "active")] | length' .auto-context/conventions.json
jq '[.[] | select(.stage == "decayed")] | length' .auto-context/conventions.json

# Candidate counts by stage
jq '[.[] | select((.stage // "observation") == "observation")] | length' .auto-context/candidates.json
jq '[.[] | select(.stage == "review_pending")] | length' .auto-context/candidates.json
jq 'length' .auto-context/candidates.json

# Anti-patterns
jq 'length' .auto-context/anti-patterns.json

# Observation stats
jq '[.[].observations // 0] | add // 0' .auto-context/candidates.json
jq '[.[].session_id] | unique | length' .auto-context/candidates.json

# Recent changelog (last 5 entries)
tail -5 .auto-context/changelog.jsonl
```

---

## Step 3: Format Status Dashboard

Present the dashboard using this format:

```
## Auto-Context Pipeline Status

### Session Info
- **Session count:** {session_count}
- **Token budget:** {token_budget} tokens

### Conventions ({active_count} active)
- Active (in CLAUDE.md): {active_count}
- Decayed: {decayed_count}
- Convention cap: {active_count}/50

### Candidates ({total_candidates} total)
- Observations (gathering data): {observation_count}
- Ready for review: {review_pending_count}
```

If `review_pending_count > 0`, add: **"Run `/ac-review` to review pending candidates."**

```
### Anti-Patterns
- Total: {anti_pattern_count}

### Observation Stats
- Total observations across all candidates: {sum_observations}
- Unique sessions with extractions: {unique_session_count}

### Reward Signals
- Reward tracking: pending Phase 7

### Recent Activity
```

Read the last 5 lines of `.auto-context/changelog.jsonl`. Format each line as:

```
- [{timestamp}] {action}: {text} ({reason})
```

If no changelog exists or is empty: **"No lifecycle activity recorded yet."**
