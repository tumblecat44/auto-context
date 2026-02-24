# Auto-Context

## What This Is

Claude Code plugin that automatically accumulates and refines project context as you code. Instead of manually maintaining CLAUDE.md, Auto-Context observes your sessions, extracts coding patterns and conventions, and progressively updates CLAUDE.md so Claude gets smarter about your project over time. Think of it as Peter Steinberger's hand-crafted "organizational scar tissue" — but automated.

## Core Value

**Use Claude Code normally, and your project context improves automatically.** Zero manual maintenance of CLAUDE.md. The plugin observes, learns, and updates — the user just codes.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

(None yet — ship to validate)

### Active

<!-- Current scope. Building toward these. -->

- [ ] Plugin manifest (plugin.json) with hooks, skills, agents registration
- [ ] Session observation via plugin hooks (file changes, tool usage, errors)
- [ ] Pattern extraction from session data (coding conventions, naming, structure)
- [ ] Context lifecycle: Observation → Candidate → Convention → Decay
- [ ] CLAUDE.md auto-generation with marker-separated sections
- [ ] Initial project scan skill (/ac-init) for bootstrapping context
- [ ] Status/review skills (/ac-status, /ac-review) for transparency
- [ ] Anti-pattern detection (user corrections → "don't do this" rules)
- [ ] Explicit feedback capture ("remember this", "don't do this")
- [ ] Closed-loop auto-discovery (build/test/lint commands from package.json, Makefile)

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- IDE plugins (VS Code, Cursor) — Claude Code plugin only, keep scope tight
- Cloud sync / team sharing — local-first for v1, team features later
- Other AI coding tools (Copilot, Cursor) — Claude Code exclusive
- External API calls — plugin uses built-in agent/prompt handlers, no API keys needed
- Parallel agent orchestration — separate concern (VibeTunnel territory)

## Context

**Existing design:** A detailed plan document exists at `docs/01-plan/features/auto-context.plan.md` covering architecture (hooks.json, scripts, agents, skills), data flow, lifecycle mechanics, marketplace strategy, and phased rollout. This is the starting point, not final design.

**Key knowledge gap — Context engineering beyond root CLAUDE.md:**
The plan currently focuses on auto-generating/maintaining a single root CLAUDE.md. But context engineering has multiple layers:
- Directory-level CLAUDE.md files (module-specific instructions)
- Dynamic context injection (situational, not static)
- File relationship maps ("edit X → also check Y")
- Tool usage instructions (closed loops for build/test/debug)
- Sub-agent strategy (parallel work area separation)

Research is needed to understand which of these matter most and how to implement them.

**North star (directional, needs research to sharpen):**
- Coding productivity up — Claude output quality improves over time
- Mistake prevention — anti-pattern DB stops repeated errors
- Intent context maintained — project "why" and "how" survives across sessions, compactions, and convention drift

**Pain points driving this (all felt acutely):**
- Same mistakes repeated → user must correct every time
- New session = re-explain project background/conventions
- CLAUDE.md maintenance is tedious → gets neglected
- Claude ignores project conventions even when told

**Distribution:** Claude Code Plugin via marketplace (GitHub-based, then official)

**First user:** Creator (dogfooding) → Claude Code power users → newcomers

## Constraints

- **Runtime**: Plugin hooks (command type) must execute < 100ms — no user-perceived delay
- **Dependencies**: Bash + jq only — zero external dependencies for shell scripts
- **Storage**: All project data in `.auto-context/` directory, < 10MB per project
- **Non-invasive**: Existing CLAUDE.md content must never be touched — auto-content lives in marker sections only
- **Plugin spec**: Must conform to Claude Code plugin manifest spec (plugin.json, hooks.json)

## Key Decisions

<!-- Decisions that constrain future work. Add throughout project lifecycle. -->

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Claude Code Plugin (not npm CLI) | `claude plugin install` UX, hooks auto-registration, marketplace discovery | — Pending |
| Bash + jq for scripts | Zero dependency, POSIX compatible, fast for command handlers | — Pending |
| Agent handler for pattern extraction | Uses Claude's built-in sub-agent — no external API needed | — Pending |
| JSON files for storage | Human-readable, git-committable, zero dependency | — Pending |
| Marker sections in CLAUDE.md | Clean separation of user vs auto content | — Pending |
| Research context engineering deeply before finalizing north star | Knowledge gap on what's beyond root CLAUDE.md optimization | — Pending |

---
*Last updated: 2026-02-24 after project initialization*
