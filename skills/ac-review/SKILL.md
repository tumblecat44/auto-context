---
name: ac-review
description: Review pending convention candidates. Approve, reject, or edit each candidate before it reaches CLAUDE.md.
disable-model-invocation: true
---

# Auto-Context: Convention Review

Review candidates that have been promoted to `review_pending` status. No convention reaches CLAUDE.md without explicit user approval through this skill.

**Important rules:**
- ALWAYS write each decision to disk immediately after the user responds. Never batch decisions.
- Use `jq` for all JSON operations (atomic writes with tmp+mv pattern).
- Use `jq -nc` for JSONL changelog entries.
- Present one candidate at a time so each decision is persisted before the next.

---

## Step 1: Read Pending Candidates

Read `.auto-context/candidates.json` in the project root.

Filter for entries where `stage == "review_pending"`:

```bash
jq '[.[] | select(.stage == "review_pending")]' .auto-context/candidates.json
```

If no `review_pending` candidates found, tell the user:

> No candidates pending review. Candidates need 3+ observations across 2+ sessions to qualify. Run `/ac-status` to see the current pipeline.

And stop.

If candidates exist, display: **"Found N candidates ready for review."**

---

## Step 2: Present Each Candidate

For each `review_pending` candidate, present in this format:

```
### Candidate N of M

**Convention:** {text}
**Confidence:** {confidence}
**Observations:** {observations} across {sessions_seen length} sessions
**First seen:** {created_at}
**Evidence:**
- `{file}:{line}` -- {snippet}
  (for each item in evidence array)

**Action:** approve / reject / edit
```

Wait for the user's response after each candidate. Do NOT present the next candidate until the current one is processed and written to disk.

---

## Step 3: Process User Decision

### On "approve":

1. Read current `.auto-context/conventions.json`
2. Read `session_count` from `.auto-context/lifecycle.json`:
   ```bash
   jq -r '.session_count // 0' .auto-context/lifecycle.json
   ```
   If lifecycle.json is missing or corrupt, use `0` as fallback.
3. Create a new convention entry:
   - `text`: candidate's text (unchanged)
   - `confidence`: `0.7` (promoted extraction confidence)
   - `source`: `"extraction"` (preserve original source)
   - `stage`: `"active"`
   - `created_at`: candidate's created_at (preserve original)
   - `approved_at`: current ISO 8601 timestamp
   - `session_id`: candidate's session_id (preserve original)
   - `last_referenced_session`: session_count from lifecycle.json
   - `observations`: candidate's observations count
   - `sessions_seen`: candidate's sessions_seen array
4. Append to `conventions.json` atomically (jq + tmp + mv)
5. Remove the candidate from `candidates.json` atomically (filter by text match)
6. Log to `.auto-context/changelog.jsonl`:
   ```bash
   jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg text "{text}" \
     '{ts:$ts, action:"approved", text:$text, reason:"user approved via /ac-review", from_stage:"review_pending", to_stage:"active"}' \
     >> .auto-context/changelog.jsonl
   ```
7. Confirm: **"Approved: {text}"**

### On "reject":

1. Remove the candidate from `.auto-context/candidates.json` atomically
2. Log to `.auto-context/changelog.jsonl` with `action: "rejected"`, `reason: "user rejected via /ac-review"`, `from_stage: "review_pending"`, `to_stage: "rejected"`
3. Confirm: **"Rejected: {text}"**

### On "edit":

1. Ask the user for the modified convention text
2. Follow the same approve flow but use the user's edited text
3. Log to changelog.jsonl with `action: "approved_edited"` and include both original and modified text in the reason field
4. Confirm: **"Approved (edited): {new_text}"**

---

## Step 4: Post-Review Summary

After all candidates are reviewed, show a summary:

> **Review complete:** N approved, M rejected, K edited

If any were approved:

> Approved conventions will appear in CLAUDE.md at next session start. Run `/ac-status` to see current pipeline state.
