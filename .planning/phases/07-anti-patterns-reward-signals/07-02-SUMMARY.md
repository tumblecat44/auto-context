# 07-02 Summary: Reward signal display and anti-pattern breakdown in /ac-status

## What Changed

### skills/ac-status/SKILL.md
- Added `rewards.json` to the Step 1 file list
- Added jq commands for anti-pattern breakdown by source (explicit, correction, error) and by stage (active, observation)
- Added jq commands for reward signal aggregation (session count, average score, recent trend, signal breakdown)
- Replaced placeholder "Reward tracking: pending Phase 7" with conditional display logic
- Added trend determination logic (improving/stable/declining based on first vs last of recent 5 scores)
- Anti-pattern section now shows source categorization and stage breakdown
- Missing `.source` field treated as "explicit" for backward compatibility with Phase 4 entries
- Reward scores rounded to 2 decimal places using `* 100 | floor / 100` jq pattern
- Skill remains read-only (disable-model-invocation: true preserved)

## Verification Results

- "Reward Signals" section present: PASS
- "rewards.json" referenced: PASS
- "correction" source breakdown present: PASS
- "pending Phase 7" placeholder removed: PASS
- disable-model-invocation: true preserved: PASS
