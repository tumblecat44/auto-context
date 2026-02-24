# Feature Landscape: Auto-Context

**Domain:** Context engineering automation for AI coding agents (Claude Code plugin)
**Researched:** 2026-02-24

---

## Context Engineering Layers (Research Foundation)

Before categorizing features, it is essential to understand the full layer model that exists in the ecosystem today. This research found **seven distinct layers** of context engineering, not just "a CLAUDE.md file."

### Layer 1: Organization/Managed Policy
- **What:** Enterprise-wide rules enforced by IT/DevOps
- **Where:** `/Library/Application Support/ClaudeCode/CLAUDE.md` (macOS)
- **Who uses:** Cursor (Team Rules), Claude Code (Managed Policy), Windsurf (Global Rules)
- **Purpose:** Compliance (HIPAA, SOC 2), company coding standards
- **Relevance to Auto-Context:** LOW -- out of scope for a plugin. Auto-Context works at project level.

### Layer 2: User-Level Preferences
- **What:** Personal defaults across all projects
- **Where:** `~/.claude/CLAUDE.md`, `~/.claude/rules/*.md`
- **Who uses:** Claude Code (User Memory), Cursor (User Rules), Windsurf (Global Rules)
- **Purpose:** Individual style preferences, personal tooling shortcuts
- **Relevance to Auto-Context:** MEDIUM -- could detect personal patterns and suggest user-level rules, but risky scope creep.

### Layer 3: Project-Wide Context (Root CLAUDE.md / AGENTS.md)
- **What:** Team-shared project instructions, architecture, conventions
- **Where:** `./CLAUDE.md`, `./.claude/CLAUDE.md`, `./AGENTS.md`
- **Who uses:** Everyone. This is the universal layer. 60k+ repos have AGENTS.md.
- **Purpose:** Build commands, code style, architecture patterns, testing conventions, security
- **Relevance to Auto-Context:** HIGH -- this is the primary target layer. Steinberger's ~150-line AGENTS.MD lives here.

### Layer 4: Path-Scoped / Directory-Level Rules
- **What:** Rules that apply only when touching specific files or directories
- **Where:** `.claude/rules/*.md` (with `paths:` frontmatter), nested `CLAUDE.md` in subdirectories, Cursor `.mdc` files with globs
- **Who uses:** Claude Code (path-scoped rules), Cursor (.mdc files with globs), OpenAI Codex (nested AGENTS.md)
- **Purpose:** Module-specific conventions (API validation rules, frontend patterns, database migration rules)
- **Relevance to Auto-Context:** HIGH -- this is where real differentiation happens. Most users only have a root file and miss this entirely.

### Layer 5: Dynamic/Session Context
- **What:** Context that changes per session or per task
- **Where:** Claude Code auto-memory (`~/.claude/projects/<project>/memory/MEMORY.md`), claude-mem SQLite DB, conversation history
- **Purpose:** Session continuity, debugging insights, architecture notes discovered during work
- **Relevance to Auto-Context:** HIGH -- this is where automatic observation and learning happens. Claude Code already has auto-memory (MEMORY.md with 200-line limit).

### Layer 6: Tool/Closed-Loop Instructions
- **What:** Specific commands for build, test, lint, deploy that the agent can execute without asking
- **Where:** Embedded in CLAUDE.md/AGENTS.md, or in path-scoped rules
- **Who uses:** Steinberger (core principle), Spotify (verify tools), all serious context engineers
- **Purpose:** Agent self-sufficiency -- compile, test, lint, debug without human intervention
- **Relevance to Auto-Context:** HIGH -- auto-discovering these from package.json, Makefile, etc. is a clear win.

### Layer 7: Anti-Pattern / Scar Tissue Database
- **What:** Accumulated "do not do this" rules from past failures
- **Where:** Embedded in CLAUDE.md, or separate anti-patterns file
- **Who uses:** Steinberger (organizational scar tissue), manual practitioners
- **Purpose:** Prevent repeated mistakes across sessions
- **Relevance to Auto-Context:** HIGH -- this is the hardest to maintain manually and the most valuable to automate.

**Key insight:** Claude Code already has built-in auto-memory (Layer 5) as of v2.1.32+. Auto-Context must differentiate by doing what auto-memory cannot: structured convention extraction, path-scoped rule generation, closed-loop discovery, and anti-pattern tracking.

---

## Competitive Landscape

| Tool | What It Does | Layers Covered | Gap Auto-Context Fills |
|------|-------------|----------------|----------------------|
| **Claude Code built-in** | Auto-memory (MEMORY.md), /init bootstrap, path-scoped rules | 2,3,4,5 | No convention extraction, no anti-pattern tracking, no lifecycle management, no file-relationship maps |
| **claude-mem** (949 stars) | Session capture, AI compression, injection of last 10 sessions | 5 | Raw session replay, not structured conventions. No rule generation. No path scoping. |
| **Cursor Rules** | .mdc files with glob scoping, 4 activation modes | 2,3,4 | Manual authoring only. No learning. No auto-generation. |
| **Windsurf Rules** | .windsurfrules with 6000 char limit, 3 activation modes | 2,3 | Manual only. Strict size limits. No path scoping. |
| **AGENTS.md standard** | Universal markdown format, hierarchical nesting | 3,4 | Format standard only, no tooling for generation or maintenance. |
| **Context7** (71K installs) | Real-time library documentation injection | N/A (external docs) | Library docs, not project conventions. |
| **Manual CLAUDE.md** | Human-written project instructions | 3 | Tedious, gets neglected, no feedback loop, no scoping. |

**Competitive position:** No existing tool automates the full loop of Observe -> Extract -> Structure -> Inject -> Measure -> Decay across all relevant layers. claude-mem is closest but operates only on raw session replay (Layer 5), not structured convention extraction (Layers 3, 4, 6, 7).

---

## Table Stakes

Features users expect from a context automation tool. Missing any of these makes the tool feel broken.

| # | Feature | Why Expected | Complexity | Confidence | Notes |
|---|---------|--------------|------------|------------|-------|
| T1 | **Project bootstrap scan** (`/ac-init`) | Steinberger's X-ray scan is the standard. Users expect initial context on install. Claude Code's `/init` already does a basic version. | Med | HIGH | Must surpass `/init` quality: detect stack, commands, architecture patterns, existing conventions |
| T2 | **Session observation** (file changes, tool usage, errors) | Core promise of "automatic" context. Without observation, nothing is automatic. | Med | HIGH | Use PostToolUse, UserPromptSubmit, Stop hooks. Must be < 100ms per hook. |
| T3 | **CLAUDE.md auto-generation** with marker sections | Users expect output in the standard location. Marker sections (`<!-- auto-context:start -->`) protect user content. | Low | HIGH | Non-negotiable: never touch user-written content. |
| T4 | **Closed-loop auto-discovery** | Finding build/test/lint commands from package.json, Makefile, etc. is universally expected. Steinberger lists this as fundamental. | Low | HIGH | Parse package.json scripts, Makefile targets, Cargo.toml, pyproject.toml, go.mod commands |
| T5 | **Explicit feedback capture** ("remember this", "don't do this") | Every context tool supports some form of this. Claude Code auto-memory already does it. Must at minimum match. | Low | HIGH | Pattern match on UserPromptSubmit. Must be more reliable than auto-memory's probabilistic approach. |
| T6 | **Status/transparency** (`/ac-status`) | Users need to see what has been learned. Black-box automation erodes trust. | Low | HIGH | Show observation count, candidates, conventions, anti-patterns, reward trends |
| T7 | **Safe CLAUDE.md coexistence** | Existing CLAUDE.md must be preserved. Plan already addresses this with marker sections. Every user will have existing content. | Low | HIGH | Marker-based separation is the right approach. Also must handle `.claude/CLAUDE.md` path. |
| T8 | **Convention review** (`/ac-review`) | Users must be able to approve/reject auto-detected patterns before they become conventions. Trust requires human oversight. | Med | HIGH | Show candidate list, allow approve/reject/edit. This is the safety valve. |
| T9 | **Zero-config operation** | Install and forget. No configuration files to set up. Plugin hooks register automatically. | Low | HIGH | plugin.json + hooks.json handle this. No user config needed. |

---

## Differentiators

Features that set Auto-Context apart from manual maintenance and competing tools. Not expected, but provide clear competitive advantage.

| # | Feature | Value Proposition | Complexity | Confidence | Notes |
|---|---------|-------------------|------------|------------|-------|
| D1 | **Convention lifecycle** (Observation -> Candidate -> Convention -> Decay) | No other tool has a lifecycle for context items. Prevents stale rules accumulating. Steinberger does this manually ("Less is More"). | High | MEDIUM | Core differentiator. 3-observation threshold for candidates, 5-session no-reference for decay. Needs careful tuning. |
| D2 | **Anti-pattern detection** (user corrections -> "don't do this" rules) | The "organizational scar tissue" that Steinberger builds manually. Automates the hardest part of context engineering. | High | MEDIUM | Detect Write->Edit correction patterns. Track reward signals. This is genuinely novel. |
| D3 | **Path-scoped rule generation** | Auto-generate `.claude/rules/*.md` files with proper `paths:` frontmatter from observed module-specific patterns. No existing tool does this. | High | MEDIUM | Requires detecting that certain conventions apply only to certain file patterns. Very powerful if done well. |
| D4 | **File relationship mapping** (co-change tracking) | Track which files are always edited together -> module boundary detection. Steinberger uses this for parallel agent work area separation. | Med | MEDIUM | Parse git history + session observations for co-change patterns. Output as relationship map. |
| D5 | **Reward signal / effectiveness measurement** | Measure whether context actually helps: track user correction rates before/after context injection. No other tool quantifies context quality. | High | LOW | Write->Edit pair analysis is a proxy signal. Genuinely novel but hard to calibrate. |
| D6 | **Smart context injection** (token budget management) | Select which conventions to inject based on current task relevance and token budget. Addresses the "lost-in-the-middle" problem (accuracy drops at ~32K tokens). | High | MEDIUM | Windsurf has 12K char limit. Claude Code has no explicit limit but suffers from priority saturation. Budget management is needed. |
| D7 | **PreCompact context preservation** | When Claude Code compacts context, preserve critical learned information. No other tool hooks into compaction. | Med | HIGH | PreCompact hook is available. Backup important context to .auto-context/ before compaction wipes it. |
| D8 | **Convention quality scoring** | Rate each convention by how often it prevents errors vs. how much token budget it consumes. Prune low-value conventions automatically. | High | LOW | Requires reward signal (D5) to be working first. Aspirational but powerful. |

---

## Anti-Features

Features to explicitly NOT build. Each has a reason based on research findings.

| # | Anti-Feature | Why Avoid | What to Do Instead |
|---|-------------|-----------|-------------------|
| A1 | **Full session replay** (claude-mem approach) | claude-mem already does this and has 949+ stars. Raw session replay is noisy -- Steinberger explicitly says "Less is More." Replaying 10 sessions of raw context wastes tokens. | Extract structured conventions from sessions, not raw logs. Quality over quantity. |
| A2 | **IDE integration** (VS Code, Cursor plugins) | Scope creep. Claude Code plugin API is the target. Adding IDE support doubles maintenance for unclear benefit. | Stay Claude Code exclusive. Other tools have their own ecosystems. |
| A3 | **Cloud sync / team sharing** | Adds complexity, privacy concerns, authentication overhead. Local-first is the right v1 approach. | `.auto-context/` is git-committable. Teams share via version control. |
| A4 | **External API calls** | Plugin runs inside Claude Code -- no API keys should be needed. Agent handlers use Claude's built-in sub-agent capability. | Use agent-type hook handlers that leverage Claude's own reasoning. |
| A5 | **Verbose/detailed rule files** | Research shows context window priority saturation is real. Stanford/Berkeley found accuracy drops at ~32K tokens. Steinberger's AGENTS.MD is only ~150 lines -- every token has a purpose. | Terse, telegraph-style rules. "Use pnpm not npm" not "We recommend using pnpm because..." |
| A6 | **AST-based code analysis** | Adds massive dependency weight (parsers for every language). LLM-based pattern extraction via agent handlers is more flexible and language-agnostic. | Use agent-type hook handlers for pattern extraction. Claude already understands code structure. |
| A7 | **Background daemon/server** | No persistent processes. Plugin hooks are event-driven. A daemon adds complexity and resource usage for no benefit. | Event-driven hooks only. SessionStart, PostToolUse, SessionEnd, etc. |
| A8 | **Replacing Claude Code's auto-memory** | Claude Code v2.1.32+ has built-in auto-memory (MEMORY.md). Competing with a built-in feature is a losing strategy. | Complement auto-memory: auto-memory captures session notes; Auto-Context extracts structured conventions and generates rules. Different purposes. |
| A9 | **Complex configuration UI** | Violates zero-config principle. Users install plugins to avoid configuration, not to configure more things. | Sensible defaults with minimal override options in `.auto-context/config.json`. |
| A10 | **Multi-model support** | AGENTS.md is becoming a cross-platform standard, but building for Copilot/Codex/Gemini simultaneously is scope explosion. | Generate standard AGENTS.md format that happens to be compatible, but target Claude Code plugin API exclusively. |

---

## Feature Dependencies

```
T1 (Bootstrap scan) ---------> T3 (CLAUDE.md generation)
                                    |
T2 (Session observation) ------+--> D1 (Convention lifecycle)
    |                          |         |
    +-> T5 (Explicit feedback) |         +--> D2 (Anti-pattern detection)
    |                          |         |
    +-> D4 (File relationships)|         +--> D3 (Path-scoped rules)
                               |
T4 (Closed-loop discovery) ----+
                               |
T6 (Status) <------------------+--- D1 (Lifecycle gives status data)
                               |
T8 (Review) <------------------+--- D1 (Review interface for lifecycle)
                               |
D5 (Reward signal) <-----------+--- T2 (Observation provides Write->Edit pairs)
    |
    +--> D6 (Smart injection) -- needs reward data to prioritize
    |
    +--> D8 (Quality scoring) -- needs reward data to score

D7 (PreCompact preservation) <----- Independent, hooks into compaction event
```

**Critical path:** T2 (observation) -> D1 (lifecycle) -> Everything else. Without observation, nothing works. Without lifecycle, conventions accumulate without bound.

---

## Steinberger's AGENTS.MD: Structural Analysis

Based on direct analysis of the raw file (approximately 150 lines, not 800 as widely cited -- the 800-line figure likely refers to an earlier or different version, or includes his full tool scripts):

### Section Breakdown

| Section | Lines | Content Type | Auto-Context Relevance |
|---------|-------|-------------|----------------------|
| Agent Protocol | ~15 | Workspace paths, repo conventions, deletion safeguards, file limits, commit rules | HIGH -- most of this is discoverable from project structure |
| Screenshots | ~8 | Asset handling, optimization procedures | LOW -- project-specific |
| Important Locations | ~7 | Directory references, credential paths | MEDIUM -- could auto-detect key directories |
| Docs | ~10 | Documentation workflow, model preferences | LOW -- manual preference |
| PR Feedback | ~6 | PR workflow rules | MEDIUM -- discoverable from .github/ config |
| Flow & Runtime | ~4 | Package manager, runtime rules | HIGH -- discoverable from lockfiles |
| Build / Test | ~8 | CI pipeline, release process, environment keys | HIGH -- discoverable from CI config + package.json |
| Git | ~12 | Safety operations, commit conventions, multi-agent coordination | MEDIUM -- partially discoverable from git config |
| Language/Stack Notes | ~4 | Swift/TypeScript specifics | HIGH -- discoverable from project files |
| macOS Permissions | ~2 | Code signing guardrails | LOW -- platform-specific |
| Critical Thinking | ~6 | Problem-solving approach | LOW -- personal philosophy |
| Tools | ~40 | CLI tool catalog with usage | HIGH -- discoverable from PATH, installed tools, MCP config |
| Frontend Aesthetics | ~12 | UI/design principles | LOW -- manual preference |

### Key Patterns in Steinberger's Format
- **Telegraph style:** "noun-phrases ok; drop grammar; min tokens"
- **Imperative voice:** "Never," "Always," "Use X not Y"
- **Inline code blocks:** Commands embedded directly in rules
- **One-line tool docs:** "logs: axiom or vercel cli"
- **Prohibitions first:** Safety guardrails before positive instructions

### What Is Auto-Discoverable vs Manual
- **Auto-discoverable (~60%):** Build commands, test commands, package manager, stack detection, file structure, tool installations, CI config, git conventions
- **Needs human input (~25%):** Design philosophy, architectural preferences, naming rationale, workflow preferences
- **Needs observation over time (~15%):** Anti-patterns, co-change patterns, correction-derived rules

---

## The AGENTS.md Standard (Cross-Platform)

As of 2026, AGENTS.md has emerged as a cross-platform standard with 60K+ repos adopting it. Key facts:

- **Format:** Standard Markdown. No required fields. "Use any headings you like."
- **Supported by:** OpenAI Codex, GitHub Copilot, Claude Code (reads it), Cursor, Factory, Kilo, Builder.io
- **Hierarchy:** Nested AGENTS.md files in subdirectories override parent (same as Claude Code's CLAUDE.md)
- **Scoping:** OpenAI supports `AGENTS.override.md` for temporary overrides

**Implication for Auto-Context:** Generate AGENTS.md-compatible output alongside CLAUDE.md output. This makes Auto-Context's output portable across tools without any additional work.

---

## MVP Recommendation

### Phase 1: Foundation (must ship to be useful at all)
1. **T1** - Bootstrap scan (`/ac-init`) -- surpass Claude Code's `/init`
2. **T4** - Closed-loop discovery (build/test/lint commands)
3. **T3** - CLAUDE.md auto-generation with marker sections
4. **T9** - Zero-config plugin manifest
5. **T7** - Safe CLAUDE.md coexistence

### Phase 2: Observation Engine (the "automatic" in Auto-Context)
6. **T2** - Session observation hooks
7. **T5** - Explicit feedback capture
8. **T6** - Status skill (`/ac-status`)

### Phase 3: Intelligence (where differentiation begins)
9. **D1** - Convention lifecycle (Observation -> Candidate -> Convention -> Decay)
10. **T8** - Convention review (`/ac-review`)
11. **D2** - Anti-pattern detection
12. **D7** - PreCompact preservation

### Phase 4: Advanced Context Engineering
13. **D4** - File relationship mapping
14. **D3** - Path-scoped rule generation
15. **D5** - Reward signal measurement
16. **D6** - Smart context injection (token budget)

### Defer Indefinitely
- **D8** - Convention quality scoring (needs mature reward signals)
- Cross-platform AGENTS.md generation (nice-to-have, not core)

**Rationale:** Phase 1 must deliver immediate value (better than `/init` alone). Phase 2 makes it genuinely automatic. Phase 3 is where no competitor exists. Phase 4 is advanced optimization that requires data from earlier phases.

---

## Sources

### HIGH Confidence (Official Documentation)
- [Claude Code Memory Documentation](https://code.claude.com/docs/en/memory) -- definitive source on all memory layers, auto-memory, MEMORY.md, rules directory
- [Cursor Rules Documentation](https://cursor.com/docs/context/rules) -- official .mdc format, scoping mechanisms
- [AGENTS.md Standard](https://agents.md/) -- official specification
- [OpenAI Codex AGENTS.md Guide](https://developers.openai.com/codex/guides/agents-md/) -- OpenAI's implementation
- [Anthropic Context Engineering Guide](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) -- Anthropic's official patterns

### MEDIUM Confidence (Verified Multiple Sources)
- [Steinberger's AGENTS.MD](https://github.com/steipete/agent-scripts/blob/main/AGENTS.MD) -- actual file analyzed
- [Steinberger: Just Talk To It](https://steipete.me/posts/just-talk-to-it) -- workflow philosophy
- [Steinberger: Optimal AI Dev Workflow](https://steipete.me/posts/2025/optimal-ai-development-workflow) -- specific techniques
- [Martin Fowler: Context Engineering for Coding Agents](https://martinfowler.com/articles/exploring-gen-ai/context-engineering-coding-agents.html) -- layer model
- [Spotify: Context Engineering for Background Agents](https://engineering.atspotify.com/2025/11/context-engineering-background-coding-agents-part-2) -- production patterns
- [claude-mem Plugin](https://github.com/thedotmack/claude-mem) -- competing approach
- [Claude Code Rules Directory Guide](https://claudefa.st/blog/guide/mechanics/rules-directory) -- path-scoped rules deep dive
- [Context Engineering Beyond CLAUDE.md](https://www.pixelmojo.io/blogs/context-engineering-ai-coding-agents-beyond-claude-md) -- four-layer hierarchy model

### LOW Confidence (Single Source / Unverified)
- "800-line AGENTS.MD" claim -- widely cited but actual file is ~150 lines. May refer to a different version or include linked scripts. Flagged for validation.
- Reward signal calibration approach (Write->Edit pair tracking) -- novel approach from the existing plan, not validated in production elsewhere.
- Convention decay timing (5-session no-reference threshold) -- proposed in plan, needs empirical tuning.
