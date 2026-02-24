# Stack Research: Auto-Context Plugin

**Domain:** Claude Code Plugin (context engineering automation)
**Researched:** 2026-02-24
**Confidence:** HIGH (verified against official Claude Code docs at code.claude.com)

## Claude Code Plugin System -- Verified Spec

This section documents the actual constraints and capabilities of the Claude Code plugin system, verified against official documentation. This is the foundation all technology choices depend on.

### Plugin System Overview

**Confidence: HIGH** -- All details verified from [code.claude.com/docs/en/plugins-reference](https://code.claude.com/docs/en/plugins-reference)

A Claude Code plugin is a self-contained directory with a `.claude-plugin/plugin.json` manifest. It bundles **skills**, **agents**, **hooks**, **MCP servers**, **LSP servers**, and **commands** into one installable unit. Plugin skills are namespaced: `/plugin-name:skill-name`.

**Minimum Claude Code version:** 1.0.33+ (for `/plugin` command support)

**Key environment variables provided by Claude Code to plugins:**
- `${CLAUDE_PLUGIN_ROOT}` -- absolute path to the plugin's cached directory (use in hooks, scripts, MCP configs)
- `$CLAUDE_PROJECT_DIR` -- the user's project root directory
- `$CLAUDE_SESSION_ID` -- current session identifier
- `$CLAUDE_ENV_FILE` -- (SessionStart only) file path for persisting environment variables

**Plugin caching:** Marketplace plugins are copied to `~/.claude/plugins/cache`. Plugins CANNOT reference files outside their directory (path traversal blocked). Symlinks are followed during copy.

### Required Directory Structure

**Confidence: HIGH** -- Verified from official docs

```
auto-context/                           # Plugin root
+-- .claude-plugin/
|   +-- plugin.json                     # Manifest (ONLY file in .claude-plugin/)
+-- skills/                             # Agent Skills (SKILL.md in subdirs)
|   +-- ac-init/
|   |   +-- SKILL.md
|   +-- ac-status/
|   |   +-- SKILL.md
|   +-- ac-review/
|   |   +-- SKILL.md
|   +-- ac-reset/
|       +-- SKILL.md
+-- agents/                             # Subagent definitions (markdown files)
|   +-- context-extractor.md
|   +-- context-injector.md
+-- hooks/
|   +-- hooks.json                      # Hook event configuration
+-- scripts/                            # Shell scripts for command hooks
|   +-- observe-tool.sh
|   +-- detect-feedback.sh
|   +-- inject-context.sh
|   +-- track-reward.sh
|   +-- manage-lifecycle.sh
|   +-- compact-context.sh
|   +-- lib/
|       +-- common.sh
|       +-- lifecycle.sh
+-- settings.json                       # Default plugin settings (optional)
+-- .mcp.json                           # MCP server configs (optional)
+-- .lsp.json                           # LSP server configs (optional)
+-- README.md
+-- LICENSE
```

**CRITICAL RULE:** `commands/`, `agents/`, `skills/`, `hooks/` go at plugin root, NOT inside `.claude-plugin/`. Only `plugin.json` goes in `.claude-plugin/`.

### plugin.json Manifest Schema

**Confidence: HIGH** -- Verified from official docs

```json
{
  "name": "auto-context",
  "version": "0.1.0",
  "description": "Automated context engineering - project context accumulates and refines as you code",
  "author": {
    "name": "dgsw67",
    "url": "https://github.com/dgsw67"
  },
  "repository": "https://github.com/dgsw67/auto-context",
  "license": "MIT",
  "keywords": ["context-engineering", "CLAUDE.md", "automation", "conventions"],
  "skills": "./skills/",
  "agents": "./agents/",
  "hooks": "./hooks/hooks.json"
}
```

**Required fields:** `name` only (the rest is optional but recommended).
**Name rules:** kebab-case, no spaces. Becomes the skill namespace prefix.
**Version:** Semantic versioning. Controls cache update detection -- bump version or users will not see changes.
**Path rules:** All custom paths relative to plugin root, must start with `./`. Custom paths supplement defaults, they do not replace them.

### Hook System Details

**Confidence: HIGH** -- Verified from [code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks)

**16 hook events available:**

| Event | Matcher | Can Block? | Best For |
|-------|---------|-----------|----------|
| `SessionStart` | `startup\|resume\|clear\|compact` | No | Loading context, environment setup |
| `UserPromptSubmit` | (none) | Yes | Detecting explicit feedback, injecting context |
| `PreToolUse` | tool name | Yes | Validating operations before execution |
| `PostToolUse` | tool name (`Write\|Edit\|Bash`) | No | Observing file changes, logging operations |
| `PostToolUseFailure` | tool name | No | Error tracking |
| `PermissionRequest` | tool name | Yes | Auto-approving or denying permissions |
| `Notification` | notification type | No | Side effects only |
| `SubagentStart` | agent type | No | Side effects only |
| `SubagentStop` | agent type | Yes | Verification before subagent completion |
| `Stop` | (none) | Yes | Preventing premature stops, reward tracking |
| `TeammateIdle` | (none) | Yes | Agent team coordination |
| `TaskCompleted` | (none) | Yes | Verification gates |
| `ConfigChange` | config source | Yes | Change validation |
| `PreCompact` | `manual\|auto` | No | Backing up context before compaction |
| `SessionEnd` | reason string | No | Cleanup, batch analysis |
| `WorktreeCreate` / `WorktreeRemove` | (none) | Create: Yes | Worktree management |

**3 handler types:**

| Type | How It Works | Timeout Default | Use Case |
|------|-------------|-----------------|----------|
| `command` | Shell command, receives JSON on stdin, returns via exit code + stdout | 600s | Fast operations (< 100ms target), file I/O, JSON processing |
| `prompt` | Single-turn LLM evaluation, `$ARGUMENTS` placeholder for context | 30s | Simple yes/no decisions |
| `agent` | Spawns a subagent with tools (Read, Grep, Glob, etc.) | 60s | Complex analysis requiring multiple tool calls |

**Command hook I/O:**
- **Input:** JSON on stdin with `session_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`, plus event-specific fields (`tool_name`, `tool_input`, `tool_response`, `prompt`, `source`, etc.)
- **Exit 0:** Success. Stdout parsed for JSON decision fields.
- **Exit 2:** Blocking error. Stderr fed back to Claude as error message.
- **Other exit codes:** Non-blocking error, stderr shown in verbose mode only.

**Matcher patterns:** Regex strings. `Write|Edit` matches either. `mcp__.*` matches MCP tools. Omit or use `"*"` to match all.

**Async hooks:** Set `"async": true` on command hooks to run in background without blocking.

**hooks.json format for plugins:**
```json
{
  "description": "Auto-Context: automated context engineering",
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/observe-tool.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "agent",
            "prompt": "Analyze session data and extract patterns...",
            "timeout": 120
          }
        ]
      }
    ]
  }
}
```

### Skills System Details

**Confidence: HIGH** -- Verified from [code.claude.com/docs/en/skills](https://code.claude.com/docs/en/skills)

Skills are `SKILL.md` files in named subdirectories. They follow the [Agent Skills](https://agentskills.io) open standard.

**SKILL.md format:**
```yaml
---
name: ac-init
description: Initialize auto-context for this project. Scans project structure, tech stack, and conventions.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash
---

# Auto-Context Init

Instructions for the skill go here as markdown...
$ARGUMENTS captures user input after the skill name.
```

**Key frontmatter fields:**

| Field | Required | Purpose |
|-------|----------|---------|
| `name` | No (defaults to dir name) | Display name, becomes `/plugin-name:skill-name` |
| `description` | Recommended | Claude uses this to decide when to auto-invoke |
| `disable-model-invocation` | No | `true` = user-only invocation (for manual skills like `/ac-init`) |
| `user-invocable` | No | `false` = Claude-only (for background knowledge) |
| `allowed-tools` | No | Tool whitelist when skill is active |
| `model` | No | Model to use |
| `context` | No | `fork` = run in subagent context |
| `agent` | No | Which subagent type when `context: fork` |
| `hooks` | No | Hooks scoped to this skill's lifecycle |
| `argument-hint` | No | Autocomplete hint, e.g. `[project-path]` |

**String substitutions:** `$ARGUMENTS`, `$ARGUMENTS[N]`, `$N`, `${CLAUDE_SESSION_ID}`

**Dynamic context injection:** `` !`command` `` syntax executes shell command and injects output.

**Supporting files:** Skills can include reference docs, templates, scripts alongside `SKILL.md`.

**Skill character budget:** 2% of context window (fallback: 16,000 chars). Configurable via `SLASH_COMMAND_TOOL_CHAR_BUDGET`.

### Agent/Subagent System Details

**Confidence: HIGH** -- Verified from [code.claude.com/docs/en/sub-agents](https://code.claude.com/docs/en/sub-agents)

Agents are markdown files with YAML frontmatter in the `agents/` directory.

**Agent markdown format:**
```yaml
---
name: context-extractor
description: Analyzes session observation data and extracts coding patterns, conventions, and anti-patterns. Use after session completion.
tools: Read, Grep, Glob
model: sonnet
---

You are a context extraction specialist. Analyze the session log data
and extract meaningful patterns...
```

**Key frontmatter fields:**

| Field | Required | Purpose |
|-------|----------|---------|
| `name` | Yes | Unique identifier (kebab-case) |
| `description` | Yes | When Claude should delegate to this agent |
| `tools` | No | Tool whitelist (inherits all if omitted) |
| `disallowedTools` | No | Tool denylist |
| `model` | No | `sonnet`, `opus`, `haiku`, or `inherit` |
| `permissionMode` | No | `default`, `acceptEdits`, `dontAsk`, `bypassPermissions`, `plan` |
| `maxTurns` | No | Max agentic turns |
| `skills` | No | Skills to preload into context |
| `mcpServers` | No | MCP servers available to this agent |
| `hooks` | No | Lifecycle hooks scoped to this agent |
| `memory` | No | `user`, `project`, or `local` for persistent memory |
| `background` | No | `true` to always run as background task |
| `isolation` | No | `worktree` for git worktree isolation |

**Built-in agents:** `Explore` (Haiku, read-only), `Plan` (inherits model, read-only), `general-purpose` (inherits model, all tools)

**Key constraint:** Subagents CANNOT spawn other subagents (no nesting).

**Agent invocation from hooks:** Use `type: "agent"` in hooks.json with a `prompt` field. The agent receives the prompt and can use tools to analyze data.

### Marketplace Distribution

**Confidence: HIGH** -- Verified from [code.claude.com/docs/en/plugin-marketplaces](https://code.claude.com/docs/en/plugin-marketplaces)

**marketplace.json format:**
```json
{
  "name": "auto-context-marketplace",
  "owner": {
    "name": "dgsw67",
    "email": "dgsw67@example.com"
  },
  "plugins": [
    {
      "name": "auto-context",
      "source": "./",
      "description": "Automated context engineering plugin",
      "version": "0.1.0"
    }
  ]
}
```

**Plugin source types:** relative path (`"./"`), GitHub (`{ "source": "github", "repo": "owner/repo" }`), git URL, npm, pip.

**Installation scopes:** `user` (default, `~/.claude/settings.json`), `project` (`.claude/settings.json`, version-controllable), `local` (`.claude/settings.local.json`, gitignored).

**Phase 1 strategy:** Self-hosted GitHub marketplace repo, users add with `/plugin marketplace add owner/repo`.
**Phase 2 strategy:** Submit to Anthropic's official marketplace.

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Bash (POSIX) | 3.2+ | Hook command handlers (scripts/) | Zero dependencies. Claude Code runs on any system with bash. Command hooks receive JSON on stdin and must be fast (< 100ms for in-loop hooks). Official Claude Code examples all use bash for hook scripts. |
| jq | 1.6+ | JSON parsing in shell scripts | The only external dependency. Required for parsing hook stdin JSON and manipulating `.auto-context/*.json` files. Every official example uses `jq` for hook I/O. |
| Markdown | -- | Skills (SKILL.md), Agents (*.md) | Native format for Claude Code skills and agents. No alternative exists. |
| JSON | -- | Data storage (.auto-context/*.json), hook I/O, plugin manifest | Human-readable, git-committable, zero dependency. Native format for hook stdin/stdout communication. |

### Development & Quality Tools

| Tool | Purpose | Why |
|------|---------|-----|
| ShellCheck | Static analysis for all bash scripts | Catches common bash pitfalls (quoting, globbing, word splitting). Industry standard for shell script quality. Catches issues that cause `set -euo pipefail` to behave unexpectedly. |
| BATS (bats-core) | Unit testing for bash scripts | The only serious Bash testing framework. TAP-compliant, supports setup/teardown, runs each test in isolation. Active maintained fork at `bats-core/bats-core`. |
| shfmt | Bash formatting | Consistent style across all scripts. Works with CI. |
| `claude --plugin-dir` | Plugin development testing | Official way to test plugins during development. Load plugin without installation. |
| `claude plugin validate .` | Plugin validation | Official validation command. Catches manifest errors, structure issues. |
| `claude --debug` | Plugin debugging | Shows plugin loading details, hook registration, errors. |

### Data Storage (Per-Project)

| File | Purpose | Format |
|------|---------|--------|
| `.auto-context/config.json` | Plugin settings, lifecycle thresholds | JSON |
| `.auto-context/observations.json` | Raw observed signals from current and past sessions | JSON |
| `.auto-context/candidates.json` | Candidate patterns awaiting promotion | JSON |
| `.auto-context/conventions.json` | Confirmed conventions for CLAUDE.md injection | JSON |
| `.auto-context/anti-patterns.json` | "Don't do this" rules from user corrections | JSON |
| `.auto-context/file-relations.json` | Co-edited file groups for dependency mapping | JSON |
| `.auto-context/rewards.json` | Reward signal history (acceptance/rejection rates) | JSON |
| `.auto-context/session-log.json` | Current session observation buffer (cleared per session) | JSON |

**Storage constraint:** < 10MB per project. All data local, no external API calls, no cloud sync.

## Installation

```bash
# For users -- install from marketplace
claude plugin install auto-context@auto-context-marketplace

# For users -- install from directory
claude --plugin-dir ./auto-context

# For developers -- test during development
claude --plugin-dir /path/to/auto-context

# Validate plugin structure
claude plugin validate /path/to/auto-context
```

**No npm install needed.** This is a pure bash+jq plugin. No build step. No compilation.

## Alternatives Considered

| Recommended | Alternative | Why Not |
|-------------|-------------|---------|
| Bash + jq for scripts | Node.js/TypeScript scripts | Adds massive dependency (node runtime). Violates zero-dependency goal. Slower startup for command hooks. Official examples use bash. |
| Bash + jq for scripts | Python scripts | Adds Python dependency. Not guaranteed on all systems. Slower for sub-100ms hooks. |
| JSON files for storage | SQLite | External dependency. Overkill for < 10MB data. Not human-readable. Cannot git-commit easily. |
| JSON files for storage | YAML | Harder to parse from bash (no `jq` equivalent). JSON is the native hook I/O format. |
| SKILL.md for user commands | `commands/*.md` (legacy) | Skills are the current recommended format. Commands are legacy but still work. Skills support frontmatter, subagent execution, and supporting files. |
| `agent` hook handler | Custom Node.js analysis | Agent handlers use Claude's built-in subagent system -- no API key needed, no external calls, access to Read/Grep/Glob tools. Free with Claude Code subscription. |
| Self-hosted marketplace | npm package | Plugin system has its own distribution. npm is not the standard for Claude Code plugins. |
| `set -euo pipefail` | Bare bash | Industry standard for robust shell scripts. Catches unset variables, pipe failures, and command errors. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| TypeScript/Node.js for hook scripts | Dependency overhead, slower cold start, overkill for JSON manipulation | Bash + jq |
| `commands/` directory for new skills | Legacy format, superseded by `skills/` | `skills/skill-name/SKILL.md` |
| Putting components inside `.claude-plugin/` | Official docs explicitly warn against this. Components will not be discovered. | Put `skills/`, `agents/`, `hooks/` at plugin root |
| `prompt` hook handler for SessionEnd analysis | Single-turn, no tool access. Cannot read files or search codebase. | `agent` hook handler for complex analysis tasks |
| Absolute paths in hooks.json | Break after plugin installation (plugin is cached to different location) | `${CLAUDE_PLUGIN_ROOT}/scripts/...` |
| Storing raw code snippets | Privacy concern, storage bloat | Store only patterns, rules, and metadata |
| External API calls (Claude API, OpenAI, etc.) | Plugin system provides built-in agent handlers. API keys add friction and cost. | `agent` type hooks and skills with `context: fork` |
| `git` hooks (pre-commit, etc.) | Different system entirely. Not aware of Claude Code sessions. | Claude Code hooks system |
| Complex MCP servers | Overkill for this use case. MCP is for external tool integration. | Direct file I/O from bash scripts + agent handlers |

## Stack Patterns by Variant

**For fast, in-loop operations (PostToolUse, UserPromptSubmit, PreToolUse):**
- Use `command` type hooks only
- Target < 100ms execution
- Bash + jq for JSON extraction
- Append to session-log.json (no complex processing)
- Use `"async": true` if the operation can be non-blocking

**For complex analysis (SessionEnd, /ac-init skill):**
- Use `agent` type hooks for SessionEnd
- Use skills with `context: fork` + agent for /ac-init
- Agent gets Read, Grep, Glob tools -- can explore the codebase
- No time constraint (runs after session or as explicit user action)
- Model selection: `sonnet` for balance of capability and speed, `haiku` for fast exploration

**For user-facing commands (/ac-status, /ac-review, /ac-reset):**
- Use skills with `disable-model-invocation: true`
- Skills can include dynamic context via `` !`command` `` syntax
- Keep `SKILL.md` under 500 lines, use supporting files for reference docs

**For CLAUDE.md injection (SessionStart):**
- Use `command` type hook
- Read `conventions.json`, generate markdown, write to marker sections
- Must be fast -- runs on EVERY session start (including resume, clear, compact)
- Use `additionalContext` field in JSON output for context injection

## Version Compatibility

| Component | Minimum Version | Notes |
|-----------|-----------------|-------|
| Claude Code | 1.0.33+ | Required for `/plugin` command and plugin system |
| Bash | 3.2+ | macOS ships 3.2, Linux typically 5.x |
| jq | 1.6+ | Available via Homebrew, apt, most package managers |
| BATS (bats-core) | 1.10+ | For development testing only, not a runtime dependency |
| ShellCheck | 0.9+ | For development linting only, not a runtime dependency |

## Key Constraints Summary

1. **Runtime:** Command hooks must be sub-100ms for in-loop events (PostToolUse, UserPromptSubmit). Agent hooks (SessionEnd) have no practical limit.
2. **Dependencies:** Bash + jq ONLY at runtime. No Node.js, no Python, no external APIs.
3. **Storage:** All project data in `.auto-context/`, must stay under 10MB.
4. **Non-invasive:** Never modify user's existing CLAUDE.md content. Auto-generated content lives between `<!-- auto-context:start -->` and `<!-- auto-context:end -->` markers only.
5. **Plugin spec compliance:** Must pass `claude plugin validate .`. Components at root level, not in `.claude-plugin/`.
6. **Path portability:** Use `${CLAUDE_PLUGIN_ROOT}` for all plugin-internal paths. Use `$CLAUDE_PROJECT_DIR` for user project paths.
7. **No subagent nesting:** Subagents cannot spawn subagents. Design accordingly.
8. **Plugin caching:** Installed plugins are cached. Cannot reference files outside plugin directory.
9. **Hooks snapshot:** Hooks are snapshotted at session start. Mid-session changes require review.

## Sources

- [Claude Code Plugins Reference](https://code.claude.com/docs/en/plugins-reference) -- Complete plugin manifest schema, directory structure, environment variables, CLI commands (HIGH confidence)
- [Claude Code Create Plugins](https://code.claude.com/docs/en/plugins) -- Plugin creation guide, quickstart, testing (HIGH confidence)
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) -- All 16 hook events, handler types, JSON I/O schemas, exit codes, matcher patterns (HIGH confidence)
- [Claude Code Skills](https://code.claude.com/docs/en/skills) -- SKILL.md format, frontmatter fields, invocation control, dynamic context, supporting files (HIGH confidence)
- [Claude Code Subagents](https://code.claude.com/docs/en/sub-agents) -- Agent markdown format, frontmatter, built-in agents, model selection, persistent memory (HIGH confidence)
- [Claude Code Plugin Marketplaces](https://code.claude.com/docs/en/plugin-marketplaces) -- marketplace.json format, distribution, installation scopes (HIGH confidence)
- [Anthropic Claude Code GitHub - plugins/](https://github.com/anthropics/claude-code/blob/main/plugins/README.md) -- 13 official example plugins including plugin-dev (HIGH confidence)
- [bats-core/bats-core](https://github.com/bats-core/bats-core) -- Bash Automated Testing System (HIGH confidence)

---
*Stack research for: Auto-Context Claude Code Plugin*
*Researched: 2026-02-24*
