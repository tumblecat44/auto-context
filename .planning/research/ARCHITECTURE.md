# Architecture Patterns

**Domain:** Context engineering automation plugin for Claude Code
**Researched:** 2026-02-24
**Confidence:** MEDIUM-HIGH (official docs verified, some design choices based on synthesis)

## Critical Finding: SessionEnd Does NOT Support Agent Hooks

**The existing plan (auto-context.plan.md Section 6.8) uses `type: "agent"` for the SessionEnd hook handler.** This is invalid. Per official Claude Code docs, SessionEnd only supports `type: "command"` hooks.

Events supporting agent/prompt hooks: PermissionRequest, PostToolUse, PostToolUseFailure, PreToolUse, Stop, SubagentStop, TaskCompleted, UserPromptSubmit.

Events supporting ONLY command hooks: ConfigChange, Notification, PreCompact, **SessionEnd**, SessionStart, SubagentStart, TeammateIdle, WorktreeCreate, WorktreeRemove.

**Impact:** The core pattern extraction step -- spawning a sub-agent at SessionEnd to analyze session-log.json -- cannot use an agent hook handler. This requires a fundamental architecture redesign for that component.

**Confidence:** HIGH -- directly from official docs at https://code.claude.com/docs/en/hooks

---

## Recommended Architecture

### Architecture Overview

The system uses a **two-speed observation-extraction pipeline** built on Claude Code's plugin infrastructure. Fast command hooks capture lightweight signals in real-time (<100ms), while heavier analysis runs either via the Stop hook (which supports agent handlers) or through an explicit skill invocation.

```
User Session
    |
    v
+-------------------+     +-------------------+     +-------------------+
| OBSERVATION LAYER |     | EXTRACTION LAYER  |     | INJECTION LAYER   |
| (Command Hooks)   | --> | (Stop Hook Agent  | --> | (SessionStart +   |
| <100ms each       |     |  + Skills)        |     |  Skills)          |
+-------------------+     +-------------------+     +-------------------+
| SessionStart      |     | Stop (agent)      |     | SessionStart      |
| PostToolUse       |     | /ac-extract skill |     |   inject-context  |
| UserPromptSubmit  |     | /ac-review skill  |     | CLAUDE.md markers |
| PreCompact        |     +-------------------+     +-------------------+
+-------------------+              |                         |
         |                         v                         |
         |              +-------------------+                |
         +----------->  | .auto-context/    | <--------------+
                        | (JSON data store) |
                        +-------------------+
                                 |
                                 v
                        +-------------------+
                        | CLAUDE.md         |
                        | (marker sections) |
                        +-------------------+
```

### Revised Hook Architecture

The key design change from the existing plan: replace SessionEnd agent hook with Stop agent hook for pattern extraction.

| Hook Event | Handler Type | Handler | Purpose |
|------------|-------------|---------|---------|
| **SessionStart** | command | `inject-context.sh` | Read conventions.json, update CLAUDE.md marker section, run lifecycle decay checks |
| **PostToolUse** (Write\|Edit) | command | `observe-tool.sh` | Log file modifications to session-log.json, track file co-edit pairs |
| **PostToolUse** (Bash) | command | `observe-tool.sh` | Log commands/errors to session-log.json |
| **UserPromptSubmit** | command | `detect-feedback.sh` | Pattern-match explicit user feedback ("remember this", "don't do this") |
| **Stop** | agent | (inline prompt) | Analyze session-log.json, extract patterns, update candidates.json. This is the correct hook for agent-type analysis |
| **Stop** | command | `track-reward.sh` | Analyze Write-then-Edit pairs for reward signals |
| **PreCompact** | command | `compact-context.sh` | Back up critical context before compaction |
| **SessionEnd** | command | `cleanup-session.sh` | Clean up session-log buffer, rotate logs (lightweight only) |

**Why Stop instead of SessionEnd for extraction:**
- Stop supports agent/prompt hook types; SessionEnd does not
- Stop fires when Claude finishes responding, before session terminates
- Stop provides `last_assistant_message` in input for analysis
- Stop can be blocked (`decision: "block"`) to force continuation if extraction needs more work
- Multiple hooks can run on the same event -- both the agent extraction and command reward tracking run on Stop

**Confidence:** HIGH -- verified against official docs

### Component Boundaries

| Component | Responsibility | Communicates With | Handler Type |
|-----------|---------------|-------------------|-------------|
| **Observation Pipeline** | Capture raw signals: file changes, commands, errors, user feedback | Writes to `.auto-context/session-log.json` | command hooks |
| **Pattern Extractor** | Analyze session data, identify recurring patterns, detect anti-patterns | Reads session-log.json, writes candidates.json, anti-patterns.json | Stop agent hook + /ac-extract skill |
| **Lifecycle Manager** | Promote candidates to conventions, decay stale conventions | Reads/writes candidates.json, conventions.json | command hook (SessionStart) |
| **Context Injector** | Generate and update CLAUDE.md marker sections from conventions | Reads conventions.json, writes CLAUDE.md | command hook (SessionStart) |
| **Reward Tracker** | Measure context effectiveness via Write-Edit pair analysis | Reads session-log.json, writes rewards.json | command hook (Stop) |
| **Skills Interface** | User-facing controls: init, status, review, extract, reset | Reads/writes all .auto-context/ files | Skills (SKILL.md) |
| **Data Store** | Persist observations, candidates, conventions, anti-patterns | All components read/write | JSON files in .auto-context/ |

### Data Flow

**Real-time observation flow (every tool use):**
```
Claude uses Write/Edit/Bash tool
  --> PostToolUse fires
  --> observe-tool.sh receives JSON on stdin (tool_name, tool_input, tool_response)
  --> Extracts relevant signal (file path, content type, error message)
  --> Appends structured entry to .auto-context/session-log.json
  --> Exit 0 (no blocking, <100ms)
```

**Explicit feedback flow (every user prompt):**
```
User types "remember: always use pnpm not npm"
  --> UserPromptSubmit fires
  --> detect-feedback.sh receives {prompt} on stdin
  --> Pattern matches against feedback triggers ("remember", "don't", "always", "never")
  --> On match: directly writes to conventions.json or anti-patterns.json
  --> Returns additionalContext to confirm capture
  --> Exit 0
```

**Pattern extraction flow (when Claude stops):**
```
Claude finishes responding (Stop event)
  --> Stop agent hook fires
  --> Subagent spawned with prompt:
      "Read .auto-context/session-log.json. Analyze for:
       1. Repeated file modification patterns (>2 occurrences)
       2. Naming conventions used consistently
       3. Error patterns that were corrected
       4. File co-edit relationships
       Update .auto-context/candidates.json with new patterns.
       Follow thresholds in .auto-context/config.json."
  --> Subagent reads session-log, uses Read/Grep/Glob
  --> Writes analysis results to candidates.json
  --> Returns summary
```

**Reward tracking flow (when Claude stops):**
```
Claude finishes responding (Stop event)
  --> track-reward.sh fires (command hook, parallel with agent hook)
  --> Reads session-log.json
  --> Identifies Write-then-Edit sequences (Claude wrote, user corrected)
  --> Calculates reward: +1 for accepted writes, -1 for corrected writes
  --> Updates rewards.json with per-convention scores
  --> Exit 0
```

**Context injection flow (session start):**
```
New session begins
  --> SessionStart fires
  --> manage-lifecycle.sh runs:
      - Check candidates meeting promotion threshold (3+ observations)
      - Promote qualifying candidates to conventions.json
      - Check conventions for decay (5+ sessions without reference)
      - Mark decayed conventions for removal
  --> inject-context.sh runs:
      - Read conventions.json
      - Read anti-patterns.json
      - Generate markdown from templates
      - Update CLAUDE.md between <!-- auto-context:start --> and <!-- auto-context:end --> markers
  --> Exit 0 with additionalContext (optional session-specific hints)
```

---

## Multi-Level Context Structure

Claude Code supports CLAUDE.md at multiple levels. Auto-Context should leverage this hierarchy rather than dumping everything into root CLAUDE.md.

### Context Levels

| Level | File | Content Type | When Loaded |
|-------|------|-------------|-------------|
| **Root** | `./CLAUDE.md` | Project-wide conventions, tech stack, build commands, anti-patterns | Always (session start) |
| **Directory** | `./src/api/CLAUDE.md` | Module-specific patterns (e.g., "API endpoints use this error format") | On-demand (when Claude reads files in that directory) |
| **Rules** | `./.claude/rules/*.md` | Modular topic-specific rules with optional path scoping | Session start (unconditional) or on-demand (path-scoped) |
| **Auto Memory** | `~/.claude/projects/<project>/memory/` | Claude's own notes, persists across sessions | First 200 lines of MEMORY.md at session start |

### Recommended Auto-Context Generation Strategy

**Phase 1 (MVP):** Write only to root CLAUDE.md marker section. Simple, proven, low risk.

**Phase 2 (Module awareness):** Generate directory-level CLAUDE.md files when file-relations.json shows strong module boundaries. For example, if files in `src/api/` are always edited together and have distinct conventions from `src/ui/`, generate `src/api/CLAUDE.md` with API-specific conventions.

**Phase 3 (Rules integration):** Generate `.claude/rules/auto-context-*.md` files with path-scoped frontmatter for fine-grained context. This avoids polluting the main CLAUDE.md and leverages Claude Code's native conditional loading.

```yaml
# .claude/rules/auto-context-api.md
---
paths:
  - "src/api/**/*.ts"
---

# API Conventions (Auto-Context)
- Error responses use { error: string, code: number } format
- All endpoints validate input with zod schemas
```

**Phase 4 (Dynamic injection):** Use SessionStart hook's `additionalContext` output to inject session-specific context without writing to files. Good for transient context like "last session was debugging auth module, relevant conventions: ..."

**Confidence:** HIGH for multi-level CLAUDE.md hierarchy (from official docs). MEDIUM for the generation strategy (design synthesis).

---

## Feedback/Learning Loop Architecture

The learning loop is the core differentiator. It follows a simplified reinforcement learning model:

```
                    +-----------+
              +---->| OBSERVE   |----+
              |     +-----------+    |
              |          |           |
              |          v           |
              |     +-----------+    |
              |     | EXTRACT   |    |
              |     +-----------+    |
              |          |           |
              |          v           |
              |     +-----------+    |
              |     | EVALUATE  |<---+  (reward signals)
              |     +-----------+
              |          |
              |          v
              |     +-----------+
              +-----| INJECT    |
                    +-----------+
                         |
                         v
                    +-----------+
                    | CLAUDE.md |
                    +-----------+
```

### State-Action-Reward Model

| Component | RL Analog | Implementation |
|-----------|-----------|---------------|
| State | Current context + accumulated conventions | conventions.json + session-log.json |
| Action | Which conventions to inject into CLAUDE.md | inject-context.sh selection logic |
| Reward | User corrections (or lack thereof) | track-reward.sh Write-Edit analysis |
| Policy | Convention confidence scores | confidence field in conventions.json |

### Lifecycle State Machine

```
[Raw Signal] ---(3+ occurrences)---> [Candidate]
[Candidate]  ---(auto/manual approve)---> [Convention]
[Candidate]  ---(user reject via /ac-review)---> [Discarded]
[Convention] ---(5+ sessions unreferenced)---> [Decayed]
[Convention] ---(negative reward signal)---> [Demoted to Candidate]
[Decayed]    ---(referenced again)---> [Convention] (refreshed)
[Decayed]    ---(2+ more sessions)---> [Removed]
```

### Signal Types and Their Weights

| Signal | Source Hook | Weight | Meaning |
|--------|-----------|--------|---------|
| File modification pattern | PostToolUse (Write\|Edit) | Low | Observed behavior, needs repetition |
| Command pattern | PostToolUse (Bash) | Low | Build/test/lint command usage |
| Error-correction pair | PostToolUse + Stop | Medium | Claude made mistake, user corrected |
| Explicit positive ("remember X") | UserPromptSubmit | High | Direct user instruction |
| Explicit negative ("don't do X") | UserPromptSubmit | High | Direct anti-pattern |
| Write accepted (no Edit follow) | Stop | Medium positive | Convention worked |
| Write corrected (Edit follows) | Stop | Medium negative | Convention may be wrong |

---

## Competitor Architecture Analysis: claude-mem

claude-mem takes a fundamentally different approach. Understanding the contrast informs our architecture decisions.

| Aspect | claude-mem | Auto-Context (our approach) |
|--------|-----------|---------------------------|
| **Storage** | SQLite + FTS5 + ChromaDB vectors | JSON files (zero dependency) |
| **Dependencies** | Bun runtime, uv, SQLite3, Chroma | Bash + jq only |
| **Context injection** | MCP tools (search/timeline/get) | CLAUDE.md marker sections |
| **Learning** | Record everything, search later | Extract patterns, inject proactively |
| **Architecture** | Worker HTTP service on port 37777 | Stateless hooks + JSON files |
| **Token efficiency** | Progressive disclosure (~10x savings) | Convention distillation (only proven patterns) |
| **Philosophy** | Memory = search through recordings | Memory = learned conventions |

**Our advantage:** Zero dependency, proactive injection (Claude doesn't need to search), convention distillation (less noise), works with Claude Code's native CLAUDE.md system.

**Their advantage:** Richer retrieval, semantic search, full session replay, more detailed memory.

**Confidence:** MEDIUM (based on GitHub README analysis, not code review)

---

## Plugin Directory Structure (Revised)

Based on official docs verification, the correct plugin structure. Key change: `.claude-plugin/` NOT `plugins/` for the manifest directory.

```
auto-context/                          # Plugin root (= git repo root)
+-- .claude-plugin/
|   +-- plugin.json                    # Plugin manifest (ONLY file in this dir)
+-- skills/
|   +-- ac-init/
|   |   +-- SKILL.md                   # /ac-init: Project initial scan
|   +-- ac-status/
|   |   +-- SKILL.md                   # /ac-status: Show accumulated context
|   +-- ac-review/
|   |   +-- SKILL.md                   # /ac-review: Approve/reject candidates
|   +-- ac-extract/
|   |   +-- SKILL.md                   # /ac-extract: Manual pattern extraction
|   +-- ac-reset/
|       +-- SKILL.md                   # /ac-reset: Clear all auto-context data
+-- agents/
|   +-- context-extractor.md           # Subagent: pattern analysis specialist
+-- hooks/
|   +-- hooks.json                     # All hook event configurations
+-- scripts/
|   +-- observe-tool.sh                # PostToolUse -> session-log.json
|   +-- detect-feedback.sh             # UserPromptSubmit -> direct convention write
|   +-- inject-context.sh              # SessionStart -> CLAUDE.md update
|   +-- manage-lifecycle.sh            # SessionStart -> promote/decay
|   +-- track-reward.sh                # Stop -> reward signal collection
|   +-- compact-context.sh             # PreCompact -> backup critical context
|   +-- cleanup-session.sh             # SessionEnd -> session buffer cleanup
|   +-- lib/
|       +-- common.sh                  # Shared: JSON read/write, path resolution
|       +-- lifecycle.sh               # Shared: promotion/decay logic
+-- templates/
|   +-- claude-md-section.md           # CLAUDE.md auto-generated section template
+-- README.md
+-- LICENSE
```

**User project data directory:**
```
user-project/
+-- .auto-context/                     # Created and managed by plugin
|   +-- config.json                    # Plugin settings, thresholds
|   +-- session-log.json               # Current session observation buffer
|   +-- candidates.json                # Candidate patterns awaiting promotion
|   +-- conventions.json               # Confirmed conventions (injected into CLAUDE.md)
|   +-- anti-patterns.json             # "Don't do this" rules
|   +-- file-relations.json            # File co-edit relationship map
|   +-- rewards.json                   # Reward signal history
+-- CLAUDE.md                          # Existing content preserved, auto-section in markers
```

---

## Patterns to Follow

### Pattern 1: Dual-Speed Processing
**What:** Separate fast synchronous observation (command hooks, <100ms) from slow asynchronous analysis (agent hooks on Stop, unlimited time).
**When:** Always. Every hook in the observation layer must be a command hook that appends to session-log.json and exits immediately.
**Why:** The 100ms constraint on perceived latency is non-negotiable. Agent hooks on Stop run after Claude finishes responding, so users are already waiting or done.

```bash
#!/bin/bash
# observe-tool.sh - MUST complete in <100ms
set -euo pipefail
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
TIMESTAMP=$(date +%s)

# Append-only, no complex processing
echo "$INPUT" | jq -c "{
  timestamp: $TIMESTAMP,
  tool: \"$TOOL_NAME\",
  file: \"$FILE_PATH\",
  session: .session_id
}" >> "${CLAUDE_PROJECT_DIR}/.auto-context/session-log.json"

exit 0
```

### Pattern 2: Marker-Based CLAUDE.md Sections
**What:** Use HTML comments as markers to delineate auto-managed content from user content.
**When:** Every time auto-context writes to CLAUDE.md.
**Why:** User content must never be touched. The markers create a clear contract.

```markdown
# My Project

(user's own content, never modified)

<!-- auto-context:start -->
## Auto-Context: Project Conventions
<!-- Generated by auto-context plugin. Do not edit manually. -->
<!-- Last updated: 2026-02-24T10:30:00Z -->

### Coding Conventions
- Use TypeScript strict mode
- Prefer named exports over default exports

### Anti-Patterns
- Do NOT use `any` type -- use `unknown` and narrow
- Do NOT commit .env files

### Build Commands
- `pnpm test` -- run test suite
- `pnpm lint` -- run linter
<!-- auto-context:end -->
```

### Pattern 3: Convention Confidence Scoring
**What:** Each convention carries a confidence score that determines whether it gets injected.
**When:** During lifecycle management (SessionStart) and context injection.
**Why:** Prevents low-confidence observations from polluting CLAUDE.md. Only proven patterns get injected.

```json
{
  "id": "conv-001",
  "type": "coding_convention",
  "content": "Use TypeScript strict mode",
  "confidence": 0.85,
  "observations": 12,
  "last_referenced_session": "2026-02-23",
  "reward_history": [1, 1, 1, -1, 1, 1],
  "status": "convention"
}
```

### Pattern 4: Graceful Degradation
**What:** Every hook must handle failure gracefully. Missing files, malformed JSON, or permission errors should log warnings but never crash.
**When:** All scripts.
**Why:** A broken hook breaks the entire Claude Code experience. Better to silently skip than to error out.

```bash
#!/bin/bash
set -euo pipefail

# Ensure .auto-context directory exists
AC_DIR="${CLAUDE_PROJECT_DIR}/.auto-context"
mkdir -p "$AC_DIR"

# Safe JSON read with fallback
SESSION_LOG="$AC_DIR/session-log.json"
if [ ! -f "$SESSION_LOG" ]; then
  echo "[]" > "$SESSION_LOG"
fi
```

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Agent Hook on Command-Only Events
**What:** Using `type: "agent"` or `type: "prompt"` on events that only support `type: "command"` (SessionStart, SessionEnd, PreCompact, etc.)
**Why bad:** The hook will silently fail or be rejected. Pattern extraction never runs.
**Instead:** Use Stop hook (supports all three types) for agent-based analysis. Use skills for on-demand analysis.

### Anti-Pattern 2: Heavy Processing in Observation Hooks
**What:** Running pattern analysis, JSON merging, or file scanning in PostToolUse command hooks.
**Why bad:** Adds latency to every tool call. Claude Code enforces timeout defaults (600s for command, but user-perceived lag is the real constraint).
**Instead:** Append-only in observation hooks. All analysis happens in Stop agent hook or skills.

### Anti-Pattern 3: Context Explosion
**What:** Injecting all accumulated conventions into CLAUDE.md without budget management.
**Why bad:** CLAUDE.md content competes with other context. Too much auto-context crowds out user instructions and file content.
**Instead:** Token budget per section (e.g., max 2000 tokens for auto-context section). Prioritize by confidence score. Move detailed conventions to directory-level CLAUDE.md or .claude/rules/.

### Anti-Pattern 4: Storing Raw Code Snippets
**What:** Saving actual code content from tool observations into .auto-context/ JSON files.
**Why bad:** Privacy concerns, storage bloat, stale data. Code changes constantly.
**Instead:** Store patterns and rules (e.g., "uses 2-space indentation") not examples (e.g., "function foo() { ... }").

---

## Scalability Considerations

| Concern | 1 session | 10 sessions | 100+ sessions |
|---------|-----------|-------------|---------------|
| session-log.json size | ~5KB | Rotated per session | Rotated per session |
| conventions.json | ~1KB (few patterns) | ~5KB (growing) | ~10KB (plateau, decay removes stale) |
| CLAUDE.md auto-section | ~200 tokens | ~500 tokens | ~1500 tokens (budget cap) |
| Pattern extraction time | ~5s (Stop agent) | ~5s (same) | ~5s (analyzes current session only) |
| SessionStart overhead | ~20ms | ~50ms (more conventions to read) | ~80ms (still under 100ms) |

Key scalability decisions:
- **Session log rotation:** Clear session-log.json at SessionEnd (after Stop extraction). Never accumulate across sessions.
- **Convention cap:** Maximum 50 active conventions. Beyond that, lowest-confidence conventions get decayed.
- **Token budget:** Hard limit on auto-context CLAUDE.md section size. Excess overflows to .claude/rules/ files.
- **Storage limit:** Total .auto-context/ directory should stay under 10MB. Periodic cleanup of rewards.json history (keep last 30 sessions).

---

## Suggested Build Order (Dependencies)

The components have strict dependency ordering:

```
Phase 1: Foundation (no dependencies)
  1. Plugin manifest (.claude-plugin/plugin.json)
  2. Data store schema (.auto-context/ JSON structures)
  3. Shared libraries (scripts/lib/common.sh, lifecycle.sh)
  4. inject-context.sh (SessionStart command hook)
  5. /ac-init skill (project bootstrap)

Phase 2: Observation Pipeline (depends on Phase 1)
  6. observe-tool.sh (PostToolUse command hook)
  7. detect-feedback.sh (UserPromptSubmit command hook)
  8. cleanup-session.sh (SessionEnd command hook)
  9. /ac-status skill

Phase 3: Extraction + Learning (depends on Phase 2)
  10. Stop agent hook (pattern extraction prompt)
  11. context-extractor agent definition
  12. track-reward.sh (Stop command hook)
  13. manage-lifecycle.sh (SessionStart command hook)
  14. /ac-review skill
  15. /ac-extract skill

Phase 4: Intelligence + Distribution (depends on Phase 3)
  16. Token budget management for CLAUDE.md sections
  17. Directory-level CLAUDE.md generation
  18. .claude/rules/ integration
  19. compact-context.sh (PreCompact hook)
  20. Marketplace packaging + distribution
```

**Dependency rationale:**
- Phase 1 must complete first because all other phases write to .auto-context/ and read from shared libraries
- Phase 2 observation must work before Phase 3 extraction (extraction needs data to analyze)
- inject-context.sh is in Phase 1 (not Phase 3) because even /ac-init needs to write to CLAUDE.md
- Phase 3 learning loop is the most complex and highest-risk; isolating it allows focused testing
- Phase 4 intelligence can be iteratively improved after the core loop works

---

## Environment Variables Available to Hooks

From official docs, hooks receive these environment variables:

| Variable | Purpose | Available In |
|----------|---------|-------------|
| `CLAUDE_PROJECT_DIR` | Project root directory | All hooks |
| `CLAUDE_PLUGIN_ROOT` | Plugin cache directory (where plugin files are installed) | Plugin hooks |
| `CLAUDE_ENV_FILE` | File path for persisting env vars | SessionStart only |
| `CLAUDE_CODE_REMOTE` | Set to "true" in remote web environments | All hooks |
| `CLAUDE_SESSION_ID` | Current session ID | Skills (via ${CLAUDE_SESSION_ID} substitution) |

**Important:** `CLAUDE_PLUGIN_ROOT` is the cached copy of the plugin, not the original repo. Scripts reference their own files via `${CLAUDE_PLUGIN_ROOT}/scripts/...`.

**Confidence:** HIGH -- from official Claude Code docs

---

## JSON Input Available Per Hook Event

Critical for script design -- what data each hook receives on stdin:

| Hook Event | Key Fields (beyond common) | Usable For |
|------------|--------------------------|------------|
| SessionStart | `source`, `model` | Conditional behavior on new vs resumed sessions |
| PostToolUse | `tool_name`, `tool_input`, `tool_response`, `tool_use_id` | Full tool execution details for logging |
| UserPromptSubmit | `prompt` | User text for feedback pattern matching |
| Stop | `stop_hook_active`, `last_assistant_message` | Claude's final response for analysis |
| PreCompact | `trigger`, `custom_instructions` | Whether auto or manual compaction |
| SessionEnd | `reason` | Why session ended (clear, logout, etc.) |

Common fields on ALL events: `session_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`

**Confidence:** HIGH -- from official Claude Code hooks reference

---

## Sources

- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) -- HIGH confidence (official docs, verified 2026-02-24)
- [Claude Code Plugin Creation Guide](https://code.claude.com/docs/en/plugins) -- HIGH confidence (official docs)
- [Claude Code Skills Reference](https://code.claude.com/docs/en/skills) -- HIGH confidence (official docs)
- [Claude Code Subagents Reference](https://code.claude.com/docs/en/sub-agents) -- HIGH confidence (official docs)
- [Claude Code Memory Reference](https://code.claude.com/docs/en/memory) -- HIGH confidence (official docs)
- [claude-mem Plugin](https://github.com/thedotmack/claude-mem) -- MEDIUM confidence (competitor analysis from README)
- [Advanced Context Engineering for Coding Agents](https://github.com/humanlayer/advanced-context-engineering-for-coding-agents) -- MEDIUM confidence (community pattern guide)
- [Official learning-output-style Plugin](https://github.com/anthropics/claude-code/tree/main/plugins/learning-output-style) -- HIGH confidence (official Anthropic example)
- [Peter Steinberger's AGENTS.MD](https://github.com/steipete/agent-scripts/blob/main/AGENTS.MD) -- MEDIUM confidence (reference implementation)
