# 07-01 Summary: Anti-pattern detection engine, CLAUDE.md injection pipeline, and reward signal storage

## What Changed

### agents/extract-patterns.md
- Added "Correction Detection (Phase 7)" section with Write->Edit pair analysis and intervening event heuristic
- Added "Error Pattern Analysis" subsection for cross-session error tracking with normalization
- Added "Reward Signal Computation (Phase 7)" section with 10x explicit weighting formula
- Restructured so correction/reward work runs FIRST (metadata-only, fast), then pattern extraction (slower)
- Moved "Final Instructions" to end of file, updated timeout reference to 180 seconds
- All existing Pattern Analysis, Classification, Evidence, Deduplication, and Output Format sections preserved unchanged

### scripts/inject-context.sh
- Added rewards.json initialization (`echo '[]'` if missing)
- Added rewards.json to context restoration backup loop
- Replaced single-section convention injection with dual-section injection (conventions + anti-patterns)
- Anti-pattern section built from `stage: "active"` entries with 200-token sub-budget
- Convention budget dynamically reduced by anti-pattern token usage
- Empty anti-pattern case handled (no empty "Do NOT" heading)
- `printf '%b'` used for newline interpretation in combined content

### scripts/preserve-context.sh
- Added rewards.json to PreCompact backup loop

### hooks/hooks.json
- Updated Stop hook agent timeout from 120 to 180 seconds

## Verification Results

- All three Phase 7 sections present in extraction agent: PASS
- rewards.json initialization and restore in inject-context.sh: PASS
- "Do NOT" anti-pattern section building in inject-context.sh: PASS
- rewards.json backup in preserve-context.sh: PASS
- Stop hook timeout = 180: PASS
- Shell syntax validation (bash -n): PASS
