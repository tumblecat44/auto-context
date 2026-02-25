---
name: ac-status
description: Show auto-context pipeline status including observation counts, candidates, conventions, anti-patterns, reward signals, and lifecycle statistics.
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
- `anti-patterns.json` -- anti-pattern entries with source and stage fields
- `lifecycle.json` -- session counter and metadata
- `config.json` -- token budget configuration
- `rewards.json` -- per-session reward signal history

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

# Anti-pattern breakdown by source (treat missing .source as "explicit" for Phase 4 entries)
jq '[.[] | select((.source // "explicit") == "explicit")] | length' .auto-context/anti-patterns.json
jq '[.[] | select(.source == "correction")] | length' .auto-context/anti-patterns.json
jq '[.[] | select(.source == "error")] | length' .auto-context/anti-patterns.json
jq '[.[] | select(.stage == "active")] | length' .auto-context/anti-patterns.json
jq '[.[] | select(.stage == "observation")] | length' .auto-context/anti-patterns.json

# Reward signal data
jq 'length' .auto-context/rewards.json
jq 'if length > 0 then ([.[].reward_score] | add / length * 100 | floor / 100) else null end' .auto-context/rewards.json
jq 'if length >= 5 then [-5:] | [.[].reward_score | . * 100 | floor / 100] else [.[].reward_score | . * 100 | floor / 100] end' .auto-context/rewards.json
jq 'if length > 0 then {implicit_pos: ([.[].implicit_positive] | add // 0), implicit_neg: ([.[].implicit_negative] | add // 0), explicit_pos: ([.[].explicit_positive] | add // 0), explicit_neg: ([.[].explicit_negative] | add // 0)} else null end' .auto-context/rewards.json

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
### Anti-Patterns ({active_ap_count} active, {observation_ap_count} pending)
- From explicit feedback: {explicit_ap_count}
- From correction detection: {correction_ap_count}
- From error tracking: {error_ap_count}
- Active (in CLAUDE.md): {active_ap_count}
- Observation (gathering data): {observation_ap_count}
```

### Reward Signals

If `rewards.json` is missing or empty (length == 0):

```
### Reward Signals
- Reward tracking: no data yet (accumulates over sessions)
```

If `rewards.json` has data:

```
### Reward Signals ({sessions_tracked} sessions)
- Average reward score: {avg_score} (1.0 = perfect, 0.0 = all corrections)
- Implicit signals: {implicit_pos} positive / {implicit_neg} negative
- Explicit signals: {explicit_pos} positive / {explicit_neg} negative
- Recent trend (last 5): {score1}, {score2}, ...
  Trend: {trend}
```

For the trend determination:
1. Take the recent scores array (last 5 or fewer)
2. Compare the first and last values
3. If last - first > 0.1: "improving"
4. If first - last > 0.1: "declining"
5. Otherwise: "stable"

```
### Observation Stats
- Total observations across all candidates: {sum_observations}
- Unique sessions with extractions: {unique_session_count}

### Recent Activity
```

Read the last 5 lines of `.auto-context/changelog.jsonl`. Format each line as:

```
- [{timestamp}] {action}: {text} ({reason})
```

If no changelog exists or is empty: **"No lifecycle activity recorded yet."**
