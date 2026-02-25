# Phase 8: Path-Scoped Rules & Smart Injection - Research

**Researched:** 2026-02-25
**Domain:** Path-scoped convention detection, `.claude/rules/` auto-generation with YAML frontmatter, confidence-weighted injection prioritization, file co-change relationship tracking from git history and session observations
**Confidence:** HIGH

## Summary

Phase 8 is the capstone phase of auto-context, adding three interconnected capabilities: (1) detecting which conventions apply only to specific file paths/modules and delivering them via Claude Code's native `.claude/rules/` path-scoped mechanism; (2) prioritizing conventions by confidence score within the CLAUDE.md token budget so the highest-value conventions always appear; and (3) tracking file co-change relationships from both session observations and git history to build a file relationship map.

The core architecture change is splitting the injection pipeline into two output channels. Currently, all active conventions are injected into the CLAUDE.md marker section up to the 1000-token budget. Phase 8 adds a secondary channel: conventions that are path-specific (i.e., their evidence references files exclusively within a particular directory subtree) are written to `.claude/rules/auto-context-*.md` files with `paths:` YAML frontmatter. This means path-scoped conventions are loaded on-demand by Claude Code when working with matching files, rather than consuming the global CLAUDE.md token budget. High-confidence conventions that overflow the CLAUDE.md budget are also spilled to `.claude/rules/` files as a spillover mechanism. The remaining CLAUDE.md budget is used for the highest-confidence universal conventions, prioritized by confidence score descending.

File co-change tracking operates at two levels: git history analysis (deterministic, run during bootstrap or on-demand) which uses `git log --name-only` to identify files that frequently change together in the same commits; and session observation analysis (incremental, run at Stop hook) which tracks files modified together in coding sessions. Both feed into `.auto-context/file-relations.json`, a relationship map that the path-scoped detection logic can use to identify module boundaries and related file clusters.

**Primary recommendation:** Extend `inject-context.sh` to sort conventions by confidence, write overflow to `.claude/rules/auto-context-*.md` files, and add path-detection logic based on convention evidence file paths. Add a `scripts/lib/file-relations.sh` library for git-based co-change extraction. Extend the Stop hook agent to also track session-level file co-change pairs.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PATH-01 | Detect module-specific conventions (patterns that apply only to certain file paths) | Conventions have an `observed_in` array (bootstrap source) or `evidence` array with `file` fields (extraction source). A convention is path-specific if ALL evidence files share a common directory prefix that is NOT the project root. Detection logic: for each convention, extract unique directory prefixes from evidence files; if all share a common prefix (e.g., `src/api/`), the convention is path-scoped to that prefix. |
| PATH-02 | Auto-generate `.claude/rules/auto-context-*.md` files with `paths:` frontmatter | Claude Code's `.claude/rules/` directory supports YAML frontmatter with `paths:` field accepting glob patterns (e.g., `"src/api/**/*"`). Auto-context generates files like `.claude/rules/auto-context-api.md` with frontmatter `paths: ["src/api/**/*"]` containing the conventions scoped to that path. File naming uses the deepest shared directory name. Official docs confirm glob patterns, brace expansion, and recursive discovery. |
| PATH-03 | Path-scoped rules loaded on-demand by Claude Code (not at session start) | Per official Claude Code documentation: "Rules without a `paths` field are loaded unconditionally. Rules with `paths` only apply when Claude is working with files matching the specified patterns." NOTE: There is a known bug (#16299, reported Jan 2026) where path-scoped rules may still load globally. This is a Claude Code platform issue, not something auto-context can fix. Our implementation is correct per the spec. |
| INJT-02 | Prioritize conventions by confidence score within token budget | Current `get_active_conventions` in `lifecycle.sh` already sorts by `-.confidence`. The injection pipeline in `inject-context.sh` already calls this function. Phase 8 enhancement: after sorting by confidence, explicitly build the CLAUDE.md content by appending conventions one-by-one until the token budget is reached, rather than building all content then truncating. This ensures the highest-confidence conventions are always included and lower-confidence ones are cleanly cut. |
| INJT-03 | Overflow high-confidence conventions to `.claude/rules/auto-context-*.md` with path-scoped frontmatter | When the CLAUDE.md token budget is reached, remaining active conventions are not simply discarded. Instead, they are written to `.claude/rules/auto-context-overflow.md` (without `paths:` frontmatter, making them globally loaded) or to path-scoped rule files if they have path-specific evidence. This creates a two-tier injection: highest-confidence in CLAUDE.md (always loaded), overflow in `.claude/rules/` (loaded by Claude Code's rule system). |
| BOOT-04 | Track file co-change relationships from session observations and git history | Git history analysis: `git log --name-only --pretty=format:"COMMIT:%H" -100` provides per-commit file lists. For each commit, generate all file pairs and increment a co-change counter. Session observations: the Stop hook agent already reads `session-log.jsonl` which contains `file_write` and `file_edit` events with file paths. Files modified in the same session are co-change pairs. Both sources merge into `file-relations.json`. |
| BOOT-05 | Generate file relationship map in `.auto-context/file-relations.json` | The file-relations.json schema stores file pairs with co-change counts, source (git/session), and last-seen timestamps. A shell script `scripts/lib/file-relations.sh` provides `update_file_relations(store_dir)` that reads git history and writes/merges the relationship map. The Stop hook agent appends session-level co-changes. |
</phase_requirements>

## Standard Stack

### Core

| Library/Tool | Version | Purpose | Why Standard |
|-------------|---------|---------|--------------|
| Bash | 3.2+ (macOS) / 5.x (Linux) | Shell scripts for injection modification, file-relations extraction, rule file generation | Consistent with Phases 1-7; all command hooks are shell scripts |
| jq | 1.6+ | JSON manipulation for confidence sorting, file-relations map building, convention path analysis | Already required by all phases; handles sorting, filtering, grouping |
| git | 2.x+ | Git history analysis for file co-change tracking | Already present in project; `git log --name-only` for commit file lists |
| Stop hook agent (extract-patterns.md) | Current | Extended to track session-level file co-changes alongside existing extraction | Already runs at session end reading session-log.jsonl |

### Supporting

| Library/Tool | Version | Purpose | When to Use |
|-------------|---------|---------|-------------|
| mkdir -p | POSIX | Create `.claude/rules/` directory if it does not exist | First time path-scoped rules are generated |
| date | POSIX | ISO 8601 timestamps for file-relations entries | Every co-change update |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|-----------|-----------|----------|
| Shell script for git co-change analysis | Agent-based git analysis | Git log parsing is deterministic string processing. Shell + jq is faster and more reliable than LLM reasoning for this. Use shell. |
| Per-convention `.claude/rules/` files | Single overflow file | Per-convention files proliferate too many small files. Better to group by path prefix: one rule file per module/directory. |
| Generating rule files at SessionStart | Generating at Stop hook | SessionStart must be fast (inject context). Rule file generation involves path analysis and file I/O. Run at Stop hook alongside extraction, or as a post-injection step that does not block the hook response. |
| Rebuilding file-relations from scratch every session | Incremental merge | Full git history scan is slow for large repos. Scan git history once (at /ac-init or first session), then incrementally add session observations. |

**Installation:**
```bash
# No new dependencies -- Bash, jq, and git already required by Phases 1-7
```

## Architecture Patterns

### Recommended Project Structure (Phase 8 additions)

```
auto-context/
├── hooks/
│   └── hooks.json                    # NO CHANGES (existing hooks sufficient)
├── scripts/
│   ├── inject-context.sh             # MODIFY: confidence-sorted injection, overflow to .claude/rules/
│   ├── lib/
│   │   ├── markers.sh                # EXISTING (Phase 1)
│   │   ├── tokens.sh                 # EXISTING (Phase 1)
│   │   ├── lifecycle.sh              # EXISTING (Phase 6)
│   │   └── file-relations.sh         # NEW: git co-change extraction, file-relations.json management
│   └── ...                           # EXISTING scripts unchanged
├── agents/
│   └── extract-patterns.md           # MODIFY: add session file co-change tracking section
├── skills/
│   └── ...                           # EXISTING skills unchanged
└── .auto-context/                    # Runtime data store (in user's project)
    ├── conventions.json              # EXISTING
    ├── anti-patterns.json            # EXISTING
    ├── file-relations.json           # NEW: file co-change relationship map
    └── ...                           # EXISTING files unchanged

# Generated in user's project at runtime:
.claude/
└── rules/
    ├── auto-context-api.md           # GENERATED: path-scoped rules for src/api/
    ├── auto-context-components.md    # GENERATED: path-scoped rules for src/components/
    └── auto-context-overflow.md      # GENERATED: overflow conventions (global, no paths:)
```

### Pattern 1: Confidence-Sorted Injection with Budget Cutoff

**What:** Instead of building all convention text then truncating, build line-by-line from highest confidence, stopping when the budget is reached.
**When to use:** In `inject-context.sh` during SessionStart.

**Algorithm:**
1. Get active conventions sorted by confidence descending (already done by `get_active_conventions`)
2. Initialize accumulated token count = 0
3. For each convention in sorted order:
   a. Estimate tokens for `"- " + convention.text + "\n"`
   b. If accumulated + estimated <= convention budget: add to CLAUDE.md content, increment accumulated
   c. If over budget: add to overflow list
4. Build overflow file(s) from overflow list

**Example:**
```bash
# Pseudocode for line-by-line budget building
CONV_LINES=""
OVERFLOW_CONVS="[]"
ACCUMULATED=0
HEADER_TOKENS=$(estimate_tokens "## Project Conventions (Auto-Context)\n\n")
ACCUMULATED=$HEADER_TOKENS

while IFS= read -r conv_text; do
  LINE="- ${conv_text}"
  LINE_TOKENS=$(estimate_tokens "$LINE")
  NEW_TOTAL=$((ACCUMULATED + LINE_TOKENS + 1))  # +1 for newline
  if [ "$NEW_TOTAL" -le "$CONV_BUDGET" ]; then
    CONV_LINES="${CONV_LINES}${LINE}\n"
    ACCUMULATED=$NEW_TOTAL
  else
    # Add to overflow (collect for .claude/rules/ generation)
    OVERFLOW_CONVS=$(echo "$OVERFLOW_CONVS" | jq --arg t "$conv_text" '. + [$t]')
  fi
done < <(echo "$ACTIVE_CONVS" | jq -r '.[].text')
```

### Pattern 2: Path-Scoped Convention Detection

**What:** Determine whether a convention applies to a specific module/directory based on its evidence file paths.
**When to use:** When deciding whether a convention goes to CLAUDE.md (global) or `.claude/rules/` (path-scoped).

**Algorithm:**
1. For each convention, extract file paths from `evidence[].file` or `observed_in[]`
2. Compute the common directory prefix of all evidence files
3. If the common prefix is a specific subdirectory (not `.` or `src/` alone for monolithic projects), the convention is path-scoped
4. Group path-scoped conventions by their common prefix

**Heuristic for "specific enough" prefix:**
- Must be at least 2 levels deep (e.g., `src/api/` not just `src/`)
- OR must be a recognized module boundary (a directory containing its own config files, package.json, etc.)
- For simple projects with flat structure, most conventions will be global (this is correct behavior)

**Example:**
```bash
# Extract common prefix from evidence files
# Convention A has evidence: ["src/api/routes.ts", "src/api/middleware.ts"]
# -> common prefix: "src/api/" -> path-scoped to "src/api/**/*"

# Convention B has evidence: ["src/app.ts", "src/utils/helpers.ts", "tests/app.test.ts"]
# -> common prefix: "" (root) -> global convention
```

### Pattern 3: Rule File Generation

**What:** Generate `.claude/rules/auto-context-*.md` files with proper YAML frontmatter.
**When to use:** After path-scoped detection, during the injection pipeline.

**File format:**
```markdown
---
paths:
  - "src/api/**/*"
---

# Auto-Context: API Conventions

- All API endpoints must validate input before processing
- Use async error handler wrapper for all route handlers

_Auto-generated by auto-context plugin. Do not edit manually._
```

**Naming convention:** `auto-context-{directory-name}.md`
- `src/api/` -> `auto-context-api.md`
- `src/components/` -> `auto-context-components.md`
- Overflow (global, no paths) -> `auto-context-overflow.md`

**Cleanup:** Before generating new rule files, remove ALL existing `auto-context-*.md` files in `.claude/rules/` to prevent stale rules from persisting.

### Pattern 4: File Co-Change Tracking from Git History

**What:** Analyze git commit history to find files that frequently change together.
**When to use:** During `/ac-init` bootstrap or as a standalone analysis step.

**Algorithm:**
```bash
# Extract file lists per commit (last 100 commits)
git log --name-only --pretty=format:"COMMIT" -100 2>/dev/null | \
  awk '/^COMMIT$/{if(NR>1) print "---"; next} NF>0{print}' | \
  # Process commit blocks to extract file pairs
```

For each commit:
1. Collect the list of changed files
2. Filter to tracked source files (exclude binary, config noise)
3. Generate all unique pairs (file_a, file_b) where file_a < file_b (canonical ordering)
4. Increment the co-change count for each pair

**file-relations.json schema:**
```json
{
  "version": 1,
  "updated_at": "2026-02-25T10:00:00Z",
  "pairs": [
    {
      "files": ["src/api/routes.ts", "src/api/middleware.ts"],
      "count": 12,
      "sources": ["git", "session"],
      "last_seen": "2026-02-25T10:00:00Z"
    },
    {
      "files": ["src/hooks/useAuth.ts", "src/context/AuthContext.tsx"],
      "count": 8,
      "sources": ["git"],
      "last_seen": "2026-02-25T10:00:00Z"
    }
  ]
}
```

### Pattern 5: Session-Level File Co-Change Tracking

**What:** The Stop hook agent records which files were modified together in the same session.
**When to use:** At session end, alongside pattern extraction and reward computation.

**Algorithm (in extraction agent):**
1. Collect all unique file paths from `file_write` and `file_edit` events in session log
2. Generate all unique pairs (same canonical ordering as git analysis)
3. Read existing `file-relations.json`
4. For each pair:
   - If pair exists: increment count, add "session" to sources, update last_seen
   - If pair is new: create with count=1, sources=["session"]
5. Write updated file-relations.json atomically

### Anti-Patterns to Avoid

- **Generating too many rule files:** Do not create one rule file per convention. Group by shared directory prefix. Aim for 1-5 rule files maximum. Too many files create noise in `.claude/rules/`.
- **Using non-quoted glob patterns in YAML frontmatter:** YAML treats `*` and `{` as special characters. All glob patterns MUST be quoted strings in the `paths:` array. E.g., `"src/api/**/*"` not `src/api/**/*`.
- **Treating every evidence file as a path scope:** A convention with evidence from `src/api/routes.ts` and `src/app.ts` is NOT path-scoped to `src/api/`. ALL evidence must share the prefix.
- **Running git history analysis at every SessionStart:** Git log parsing of 100 commits is fast (~200ms) but unnecessary every session. Run once at `/ac-init` or when the user requests it, then incrementally update from session observations.
- **Removing user-created rule files:** Only clean up files matching `auto-context-*.md` pattern in `.claude/rules/`. Never touch files that do not start with `auto-context-`.
- **Putting path-scoped conventions in BOTH CLAUDE.md and .claude/rules/:** A convention must appear in exactly one place. If it is path-scoped and written to a rule file, remove it from the CLAUDE.md injection list.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Common directory prefix detection | Custom path parsing with string splitting | jq + shell `dirname` and iterative prefix matching | Path handling has edge cases (trailing slashes, `.` vs empty). Use standard tools. |
| Git log parsing | Custom line-by-line git output parser | `git log --name-only --pretty=format:COMMIT -100` with awk block processing | Git's output format is well-defined. awk handles commit boundary detection cleanly. |
| YAML frontmatter generation | Hand-building YAML strings with printf | `cat << 'HEREDOC'` with fixed template | YAML indentation is whitespace-sensitive. Templates are more reliable than dynamic string building. |
| Token budget line-by-line accounting | Manual character math | Reuse existing `estimate_tokens` from `lib/tokens.sh` per line | Already implemented and tested. Consistent with Phases 1-7 approach. |
| File pair generation | Nested loops with deduplication logic | Canonical ordering (file_a < file_b) with jq combinations | Canonical ordering naturally deduplicates and makes lookup O(1). |

**Key insight:** Phase 8 adds intelligence to the OUTPUT side of the injection pipeline (prioritizing and routing conventions to the right delivery channel) and intelligence to the INPUT side (file co-change tracking provides evidence for path-scoping). The hook infrastructure is complete; this phase is about smarter data processing and rule file generation.

## Common Pitfalls

### Pitfall 1: Path-Scoped Rules Bug in Claude Code

**What goes wrong:** Rules with `paths:` frontmatter load globally at session start instead of on-demand.
**Why it happens:** Known Claude Code bug (#16299, reported Jan 2026, still open as of Feb 2026). Path-scoped rules load into context at session start regardless of the paths specified.
**How to avoid:** This is a platform issue that auto-context cannot fix. Our implementation is correct per the official specification. When the bug is fixed, path-scoped delivery will work as intended. In the meantime, the behavior is equivalent to all rules loading globally, which is still correct (just not as efficient with context tokens as intended). Document this limitation in the generated rule files.
**Warning signs:** All auto-context rules appearing in `/memory` output even when not working with matching files.

### Pitfall 2: Stale Rule Files After Convention Changes

**What goes wrong:** Path-scoped rule files in `.claude/rules/` contain conventions that have since been decayed, rejected, or modified.
**Why it happens:** Rule files are generated once but conventions change over sessions (decay, new promotions, confidence changes).
**How to avoid:** Regenerate ALL `auto-context-*.md` rule files at every SessionStart injection. The cleanup-then-regenerate approach ensures consistency: (1) remove all `auto-context-*.md` files, (2) run path-scoped detection on current active conventions, (3) write fresh rule files. This is safe because these files are auto-generated and ephemeral.
**Warning signs:** `.claude/rules/` containing conventions that are no longer in `conventions.json` as active.

### Pitfall 3: Conventions Appearing in Both CLAUDE.md and .claude/rules/

**What goes wrong:** A path-scoped convention is injected into CLAUDE.md AND written to a rule file, wasting context tokens.
**Why it happens:** The injection logic does not track which conventions were routed to rule files.
**How to avoid:** Process in clear phases: (1) detect path-scoped conventions and remove them from the CLAUDE.md injection list, (2) generate rule files for path-scoped conventions, (3) inject remaining conventions into CLAUDE.md with confidence-sorted budget. Each convention appears in exactly one place.
**Warning signs:** Duplicate convention text appearing in both CLAUDE.md and a rule file.

### Pitfall 4: Over-Scoping Conventions to Narrow Paths

**What goes wrong:** A convention like "use camelCase for variables" gets scoped to `src/api/` because all its evidence happens to be from that directory, even though it is actually a project-wide convention.
**Why it happens:** Evidence is sampled, not exhaustive. A convention observed in 3 files within `src/api/` might apply project-wide but only has evidence from one area.
**How to avoid:** Apply a minimum evidence threshold for path-scoping: a convention needs evidence from at least 3 files AND all evidence must share the prefix for it to be considered path-specific. Below 3 evidence files, treat as global. Also, bootstrap conventions (from `/ac-init`) that describe project-wide patterns should never be path-scoped regardless of evidence.
**Warning signs:** General coding conventions appearing only in path-scoped rule files, not in CLAUDE.md.

### Pitfall 5: File-Relations.json Growing Unbounded

**What goes wrong:** Over many sessions, file-relations.json accumulates thousands of file pairs, many of which are stale.
**Why it happens:** Files get renamed, deleted, or moved, but their old relationships persist.
**How to avoid:** Apply a relevance threshold: only store pairs with count >= 2. Periodically prune pairs where both files no longer exist in the working tree. Cap the total number of pairs (e.g., 500 most-frequent). The git-based scan naturally limits to recent history (last 100 commits).
**Warning signs:** file-relations.json exceeding 100KB; jq operations on it becoming noticeably slow.

### Pitfall 6: Git History Analysis Failing on Non-Git Projects

**What goes wrong:** The file-relations extraction script fails or crashes when the project is not a git repository.
**Why it happens:** `git log` exits non-zero when not in a git repo.
**How to avoid:** Guard all git commands with a check: `git rev-parse --is-inside-work-tree 2>/dev/null || return 0`. If not a git repo, skip git-based co-change analysis entirely. Session-based tracking still works independently.
**Warning signs:** Error output from git commands during SessionStart; file-relations.json never populated.

## Code Examples

### file-relations.json Schema

```json
{
  "version": 1,
  "updated_at": "2026-02-25T10:00:00Z",
  "git_commits_analyzed": 100,
  "pairs": [
    {
      "files": ["src/api/routes.ts", "src/api/middleware.ts"],
      "count": 12,
      "sources": ["git", "session"],
      "last_seen": "2026-02-25T10:00:00Z"
    }
  ]
}
```

### .claude/rules/auto-context-*.md File Format

```markdown
---
paths:
  - "src/api/**/*"
---

# Auto-Context: src/api Conventions

- All API endpoints must validate input before processing
- Use async error handler wrapper for all route handlers
- Return standardized error response format: {error: string, status: number}

_Auto-generated by auto-context plugin. Regenerated each session._
```

### Git Co-Change Extraction Script (scripts/lib/file-relations.sh)

```bash
#!/usr/bin/env bash
# File co-change relationship tracking for auto-context

# extract_git_cochanges(store_dir, max_commits)
# Analyze git log and write co-change pairs to file-relations.json
extract_git_cochanges() {
  local store_dir="$1" max_commits="${2:-100}"

  # Guard: must be a git repo
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Extract per-commit file lists
  # Output format: blocks of filenames separated by "---"
  local commit_files
  commit_files=$(git log --name-only --pretty=format:"---" -"$max_commits" 2>/dev/null | \
    awk '/^---$/{if(block) print block; block=""; next} NF>0{block = block ? block "\t" $0 : $0} END{if(block) print block}')

  # Build pairs JSON using jq
  local pairs_json="[]"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    # Split tab-separated files into array, generate pairs
    local file_pairs
    file_pairs=$(echo "$line" | jq -R 'split("\t") | [combinations(2)] | map(select(.[0] < .[1])) | map({files: ., count: 1})' 2>/dev/null || echo "[]")
    pairs_json=$(echo "$pairs_json" "$file_pairs" | jq -s '.[0] + .[1]')
  done <<< "$commit_files"

  # Aggregate: merge duplicate pairs, sum counts
  local aggregated
  aggregated=$(echo "$pairs_json" | jq --arg ts "$ts" '
    group_by(.files) |
    map({
      files: .[0].files,
      count: ([.[].count] | add),
      sources: ["git"],
      last_seen: $ts
    }) |
    sort_by(-.count) |
    .[:500]
  ')

  # Write to file-relations.json (merge with existing session data)
  local relations_file="$store_dir/file-relations.json"
  if [ -f "$relations_file" ] && [ -s "$relations_file" ]; then
    # Merge: keep session-sourced pairs, replace git-sourced
    local existing_session
    existing_session=$(jq '[.pairs[] | select(.sources | index("session"))]' "$relations_file" 2>/dev/null || echo "[]")
    jq -nc --argjson git "$aggregated" --argjson session "$existing_session" --arg ts "$ts" --argjson mc "$max_commits" '
    {
      version: 1,
      updated_at: $ts,
      git_commits_analyzed: $mc,
      pairs: ($git + $session | group_by(.files) | map({
        files: .[0].files,
        count: ([.[].count] | add),
        sources: ([.[].sources[]] | unique),
        last_seen: $ts
      }) | sort_by(-.count) | .[:500])
    }' > "$relations_file.tmp" && mv "$relations_file.tmp" "$relations_file"
  else
    jq -nc --argjson pairs "$aggregated" --arg ts "$ts" --argjson mc "$max_commits" '
    {
      version: 1,
      updated_at: $ts,
      git_commits_analyzed: $mc,
      pairs: $pairs
    }' > "$relations_file"
  fi
}
```

### Path-Scoped Convention Detection Logic

```bash
# detect_path_scope(convention_json) -> glob pattern or empty string
# Returns the path glob if convention is path-scoped, empty if global
detect_path_scope() {
  local conv_json="$1"

  # Extract evidence file paths
  local files
  files=$(echo "$conv_json" | jq -r '
    [(.evidence // [])[] | .file // empty] +
    [(.observed_in // [])[] | . // empty] |
    unique | .[]
  ' 2>/dev/null)

  # Need at least 3 evidence files to consider path-scoping
  local file_count
  file_count=$(echo "$files" | grep -c . 2>/dev/null || echo 0)
  [ "$file_count" -lt 3 ] && return 0

  # Skip bootstrap conventions (project-wide by nature)
  local source
  source=$(echo "$conv_json" | jq -r '.source // ""')
  [ "$source" = "bootstrap" ] && return 0

  # Find common directory prefix
  local common_prefix=""
  while IFS= read -r file_path; do
    [ -z "$file_path" ] && continue
    local dir
    dir=$(dirname "$file_path")
    if [ -z "$common_prefix" ]; then
      common_prefix="$dir"
    else
      # Iteratively shorten prefix until it matches
      while [ "$common_prefix" != "." ] && [ "${dir#$common_prefix}" = "$dir" ]; do
        common_prefix=$(dirname "$common_prefix")
      done
    fi
  done <<< "$files"

  # Must be at least 2 levels deep (not root or single top-level dir)
  if [ -z "$common_prefix" ] || [ "$common_prefix" = "." ] || [ "$common_prefix" = "./" ]; then
    return 0
  fi
  local depth
  depth=$(echo "$common_prefix" | tr '/' '\n' | grep -c . 2>/dev/null || echo 0)
  [ "$depth" -lt 2 ] && return 0

  # Return glob pattern
  echo "${common_prefix}/**/*"
}
```

### Modified inject-context.sh Overflow Logic (Pseudocode)

```bash
# --- Phase 8: Smart Injection with Overflow ---

# Step 1: Get all active conventions sorted by confidence
ACTIVE_CONVS=$(get_active_conventions "$STORE_DIR" 50)
CONV_COUNT=$(echo "$ACTIVE_CONVS" | jq 'length')

# Step 2: Separate path-scoped vs global conventions
PATH_SCOPED="[]"
GLOBAL_CONVS="[]"
for i in $(seq 0 $((CONV_COUNT - 1))); do
  CONV=$(echo "$ACTIVE_CONVS" | jq ".[$i]")
  SCOPE=$(detect_path_scope "$CONV")
  if [ -n "$SCOPE" ]; then
    PATH_SCOPED=$(echo "$PATH_SCOPED" | jq --arg scope "$SCOPE" --argjson conv "$CONV" '. + [$conv + {path_scope: $scope}]')
  else
    GLOBAL_CONVS=$(echo "$GLOBAL_CONVS" | jq --argjson conv "$CONV" '. + [$conv]')
  fi
done

# Step 3: Write path-scoped conventions to .claude/rules/ files
RULES_DIR="${CWD}/.claude/rules"
# Clean up old auto-context rules
rm -f "$RULES_DIR"/auto-context-*.md 2>/dev/null || true

if [ "$(echo "$PATH_SCOPED" | jq 'length')" -gt 0 ]; then
  mkdir -p "$RULES_DIR"
  # Group by path_scope, generate one file per scope
  echo "$PATH_SCOPED" | jq -r '[group_by(.path_scope)[] | {scope: .[0].path_scope, convs: [.[].text]}] | .[]' | ...
  # (Generate files with YAML frontmatter + convention list)
fi

# Step 4: Build CLAUDE.md content from global conventions, line-by-line with budget
# (confidence-sorted, stop when budget reached, overflow to auto-context-overflow.md)

# Step 5: Write overflow file if any global conventions exceeded budget
if [ "$(echo "$OVERFLOW" | jq 'length')" -gt 0 ]; then
  mkdir -p "$RULES_DIR"
  # Write auto-context-overflow.md (no paths: frontmatter = global)
fi
```

### Extraction Agent Extension (Session Co-Change Tracking)

```markdown
## File Co-Change Tracking (Phase 8)

After correction detection and reward computation, track file relationships.

### Session Co-Change Pairs

1. Collect all unique file paths from `file_write` and `file_edit` events
2. Sort the file list alphabetically
3. Generate all unique pairs where file_a < file_b (canonical ordering)
4. Read existing `.auto-context/file-relations.json` (or create with `{"version":1,"pairs":[]}`)
5. For each pair:
   a. If pair exists in file-relations.json: increment count, ensure "session" in sources, update last_seen
   b. If pair is new: add with count=1, sources=["session"], last_seen=current timestamp
6. Write updated file-relations.json atomically (read -> merge -> write)
7. Cap total pairs at 500 (keep highest count)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|-------------|-----------------|--------------|--------|
| All conventions in CLAUDE.md (Phase 6) | Confidence-sorted injection with overflow to `.claude/rules/` | Phase 8 | Higher-confidence conventions always visible; overflow preserved in rule files |
| All conventions global scope | Path-scoped detection routes module-specific conventions to rule files | Phase 8 | Reduces CLAUDE.md bloat; conventions loaded on-demand for matching files |
| Simple truncation when over budget | Line-by-line budget building with clean cutoff | Phase 8 | No mid-convention truncation; clean prioritization by confidence |
| No file relationship tracking | Git + session co-change analysis | Phase 8 | Enables path-scoped detection; provides module boundary information |

**Deprecated/outdated:**
- The current `enforce_budget` truncation approach in `inject-context.sh` will be replaced with line-by-line budget building for conventions (anti-patterns still use `enforce_budget` for their 200-token sub-budget).
- There is a known Claude Code bug (#16299) where `paths:` frontmatter in rules does not actually scope loading. Per official documentation, path-scoped loading IS the intended behavior. Our implementation follows the spec.

## Open Questions

1. **Should file-relations.json extraction run at /ac-init or at SessionStart?**
   - What we know: Git history analysis of 100 commits takes ~200-500ms. SessionStart should be fast. /ac-init is a user-triggered command that can take longer.
   - What's unclear: Whether users will run /ac-init before their first real session, or whether file-relations should bootstrap automatically.
   - Recommendation: Run git co-change extraction at /ac-init (explicit user trigger). At SessionStart, only check if file-relations.json exists; if not, run a lightweight extraction (last 50 commits). Session-level co-changes are tracked incrementally by the Stop hook agent.

2. **How many .claude/rules/auto-context-*.md files should be generated?**
   - What we know: Too many rule files clutter the rules directory. Too few means overly broad path scoping.
   - What's unclear: The optimal number for typical projects.
   - Recommendation: Cap at 5 path-scoped rule files + 1 overflow file = 6 maximum. If more than 5 path prefixes are detected, merge the least-populated groups into the overflow file.

3. **Should the overflow file use paths: frontmatter or be global?**
   - What we know: Overflow conventions are high-confidence but did not fit in CLAUDE.md. They are not path-specific.
   - What's unclear: Whether a global rule file is the right delivery mechanism or if these should simply be lost.
   - Recommendation: Write as a global rule file (no `paths:` frontmatter). This ensures high-confidence conventions are always available to Claude even when they exceed the CLAUDE.md budget. Note: given the known Claude Code bug, all rule files currently load globally anyway, so the distinction is academic until the bug is fixed.

4. **What happens to .claude/rules/ if the user uninstalls the plugin?**
   - What we know: Auto-generated rule files will persist in `.claude/rules/` after uninstall.
   - What's unclear: Whether this is a problem or expected behavior.
   - Recommendation: Add cleanup of `auto-context-*.md` files to the `/ac-reset` skill. Document that uninstalling the plugin does not automatically remove generated rule files.

## Sources

### Primary (HIGH confidence)
- Existing codebase: `scripts/inject-context.sh` (current injection pipeline with token budget), `scripts/lib/lifecycle.sh` (get_active_conventions with confidence sorting), `scripts/lib/tokens.sh` (estimate_tokens and enforce_budget), `agents/extract-patterns.md` (extraction agent prompt), `scripts/observe-tool.sh` (session log event format with file paths), `hooks/hooks.json` (complete hook configuration)
- [Claude Code official docs: Manage Claude's memory](https://code.claude.com/docs/en/memory) -- `.claude/rules/` directory documentation, `paths:` YAML frontmatter syntax, glob pattern support, loading behavior
- `.planning/REQUIREMENTS.md` -- Full requirement definitions for PATH-01 through PATH-03, INJT-02, INJT-03, BOOT-04, BOOT-05
- `.planning/ROADMAP.md` -- Phase 8 success criteria and plan breakdown

### Secondary (MEDIUM confidence)
- [Claude Code Rules Directory: Modular Instructions That Scale](https://claudefa.st/blog/guide/mechanics/rules-directory) -- Detailed path-scoped rules format examples, loading priority information
- [Claude Code Gets Path-Specific Rules](https://paddo.dev/blog/claude-rules-path-specific-native/) -- Practical syntax examples, comparison with Cursor format
- [Creating Claude Rules (Plugin Registry)](https://claude-plugins.dev/skills/@pr-pm/prpm/creating-claude-rules) -- Plugin perspective on rule file generation
- [Git documentation](https://git-scm.com/docs/git-log) -- `git log --name-only` format for co-change analysis

### Tertiary (LOW confidence)
- [Claude Code Bug #16299: Path-scoped rules load globally](https://github.com/anthropics/claude-code/issues/16299) -- Known platform limitation. Bug report is well-documented but resolution timeline unknown. Our implementation follows the spec regardless.
- [Reorganize code with git (co-change analysis concept)](https://understandlegacycode.com/blog/reorganize-code-with-git/) -- Conceptual validation of co-change coupling analysis from git history. No specific implementation details, but validates the approach.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Same Bash+jq+git stack as all previous phases. No new dependencies. Pure extension of existing injection pipeline and extraction agent.
- Architecture: HIGH - Injection pipeline modification follows established patterns from Phases 1, 6, and 7. Rule file format verified against official Claude Code documentation. Git log parsing is standard and well-documented.
- Pitfalls: HIGH - The Claude Code bug (#16299) is the main platform risk but does not break our implementation (graceful degradation to global loading). Stale rule file management is straightforward with cleanup-then-regenerate pattern. Path-scoping false positives are mitigated by minimum evidence threshold.
- Code examples: MEDIUM - Rule file format is verified against official docs. Git co-change extraction is standard shell scripting but the jq combinations approach for pair generation needs validation during implementation (jq `combinations(2)` may have edge cases with large file lists).

**Research date:** 2026-02-25
**Valid until:** 2026-03-25 (stable domain; 30-day validity appropriate. Monitor Claude Code bug #16299 for resolution.)
