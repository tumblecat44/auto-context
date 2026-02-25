# Auto-Context

Auto-Context is a Claude Code plugin that automatically accumulates and refines project context as you code. Instead of manually maintaining CLAUDE.md, it observes your sessions, extracts coding patterns, detects anti-patterns from corrections, and progressively updates CLAUDE.md so Claude gets smarter about your project over time.

Think of it as Peter Steinberger's hand-crafted "organizational scar tissue" approach — but automated.

## How it works

It starts the moment you open a Claude Code session. Auto-Context injects your project's accumulated conventions into CLAUDE.md — conventions it learned from watching you work.

As you code, it quietly observes. Every file you write, every edit you make, every command you run gets logged. When you correct Claude ("don't use semicolons", "always use named exports"), it captures that immediately with maximum confidence.

When your session ends, a pattern extraction agent analyzes the session log. It looks for intentional coding patterns — consistent naming, import styles, error handling — and separates them from incidental noise. Patterns that show up 3+ times across 2+ sessions get promoted to candidates.

But nothing reaches your CLAUDE.md without your say-so. You run `/ac-review`, see each candidate with its evidence, and approve, reject, or edit. Only then does it become an active convention.

Conventions that stop being relevant decay automatically. The system tracks which conventions Claude actually references, and quietly removes stale ones after 5 sessions of disuse.

The result: your CLAUDE.md stays current, relevant, and growing — without you ever having to maintain it.

## Installation

### Claude Code (via Plugin Marketplace)

First, add the marketplace:

```
/plugin marketplace add tumblecat44/auto-context
```

Then install the plugin:

```
/plugin install auto-context@tumblecat44-auto-context
```

You can also open the interactive plugin manager with `/plugin`, navigate to the **Marketplaces** tab to add the marketplace, then switch to **Discover** to install.

### Verify Installation

Start a new Claude Code session. You should see "Auto-Context: injecting conventions..." in the status line. Then run:

```
/ac-status
```

If it says "Auto-context is not initialized", run `/ac-init` to bootstrap.

### Updating

```
/plugin update auto-context@tumblecat44-auto-context
```

## The Core Workflow

**`/ac-init`** — Scans your project structure, tech stack, config files, and git history. Generates initial conventions with conservative confidence scores (0.6–0.9). This is your starting point — it already catches more than Claude Code's built-in `/init`.

**Session hooks** — Once initialized, everything is automatic. Seven hooks fire at different points in your session:

| Event | What happens |
|-------|-------------|
| Session start | Injects active conventions into CLAUDE.md |
| Your message | Detects "remember this" / "don't do this" feedback |
| Tool use | Logs file writes, edits, and bash commands |
| Tool failure | Tracks error patterns |
| Session stop | Runs pattern extraction agent |
| Pre-compact | Backs up context before compression |
| Session end | Rotates session log |

**`/ac-review`** — The review gate. Candidates that have enough evidence get promoted to `review_pending`. You see each one with its confidence score, observation count, and file-level evidence. Approve, reject, or edit. Each decision persists immediately — no batch, no risk of losing work to context compaction.

**`/ac-status`** — Dashboard showing active conventions, pending candidates, anti-patterns, reward signals, and trend analysis. Read-only.

**`/ac-reset`** — Nuclear option. Clears all auto-context data and removes the auto-generated section from CLAUDE.md.

## What's Inside

### Hooks

- **inject-context.sh** — SessionStart: confidence-sorted injection within a 1000-token budget
- **detect-feedback.sh** — UserPromptSubmit: captures explicit "remember" / "don't do" patterns (English and Korean)
- **observe-tool.sh** — PostToolUse/Failure: JSONL session logging at <100ms
- **preserve-context.sh** — PreCompact: safety-net backup before context compression
- **cleanup-session.sh** — SessionEnd: log rotation

### Agent

- **extract-patterns.md** — Stop hook agent that analyzes session logs, performs Write→Edit correction detection, computes reward signals, tracks file co-change relationships, and generates candidates with evidence citations

### Skills

| Skill | Purpose |
|-------|---------|
| `/ac-init` | Deep project scan and bootstrap |
| `/ac-status` | Pipeline status dashboard |
| `/ac-review` | Convention review gate |
| `/ac-reset` | Clear all data |

### Library Modules

- **markers.sh** — CLAUDE.md marker section management
- **tokens.sh** — Token budget enforcement
- **lifecycle.sh** — Convention lifecycle state machine (observe → candidate → convention → decay)
- **path-rules.sh** — Path-scoped rule generation for overflow conventions
- **file-relations.sh** — File co-change tracking from git history

## The Convention Lifecycle

```
Observation  →  Candidate  →  Convention  →  Decay
(3+ obs,        (user        (active in      (unused 5+
 2+ sessions)    approves)    CLAUDE.md)      sessions)
```

1. **Observation** — Pattern detected by the extraction agent. Confidence 0.3.
2. **Candidate** — Promoted after 3+ observations across 2+ sessions. Enters `review_pending`.
3. **Convention** — User-approved via `/ac-review`. Confidence bumped to 0.7. Injected into CLAUDE.md.
4. **Decay** — Convention unreferenced for 5+ sessions. Removed from injection automatically.

Explicit feedback ("remember: always use named exports") skips the pipeline entirely — written directly as active conventions with confidence 1.0.

## Data Store

All data lives in `.auto-context/` in your project root:

| File | Purpose |
|------|---------|
| `conventions.json` | Active conventions for CLAUDE.md injection |
| `candidates.json` | Patterns awaiting promotion and review |
| `anti-patterns.json` | "Don't do this" rules |
| `rewards.json` | Per-session reward signal history |
| `session-log.jsonl` | Current session events (cleared each session) |
| `lifecycle.json` | Session counter and promotion tracking |
| `config.json` | Token budget and settings |
| `changelog.jsonl` | Audit trail of all lifecycle transitions |

Everything is JSON. Human-readable. Git-committable.

## Philosophy

- **Zero-config** — Install and code. No setup required beyond `/ac-init`.
- **Non-invasive** — Your CLAUDE.md content is never touched. Auto-context lives in clearly marked sections.
- **Human-in-the-loop** — Nothing reaches CLAUDE.md without your explicit approval.
- **Performance-first** — All command hooks execute in <100ms. You never notice them.
- **Zero dependencies** — Bash + jq. No Node.js, no Python, no external APIs.
- **Local and private** — All processing happens on your machine. No data leaves your project.
- **Self-correcting** — Conventions decay when unused. Anti-patterns form when Claude gets corrected. The system improves as you code.

## Requirements

- Claude Code 1.0.33+
- Bash 3.2+
- jq 1.6+

## Contributing

Contributions welcome. The codebase is intentionally simple — bash scripts, markdown skills, and JSON storage.

1. Fork the repository
2. Create a branch for your change
3. Submit a PR

## License

MIT License — see [LICENSE](LICENSE) file for details.

## Support

- Issues: https://github.com/tumblecat44/auto-context/issues
