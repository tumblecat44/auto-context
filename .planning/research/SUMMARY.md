# Project Research Summary

**Project:** Auto-Context — Claude Code Plugin
**Domain:** Context engineering automation (Claude Code plugin system)
**Researched:** 2026-02-24
**Confidence:** HIGH (all core platform facts verified against official Claude Code documentation)

## Executive Summary

Auto-Context is a Claude Code plugin that automates the full lifecycle of project context engineering — from initial project scan through continuous observation, pattern extraction, convention promotion, and CLAUDE.md injection. The plugin sits inside Claude Code's native hook and skill system, requiring zero external dependencies beyond Bash and jq. Research confirms that no existing tool covers the complete Observe -> Extract -> Lifecycle -> Inject -> Measure loop across all context layers. Claude Code's built-in auto-memory (MEMORY.md) covers session notes; claude-mem covers raw session replay; but structured convention extraction, path-scoped rule generation, and anti-pattern tracking remain genuinely unoccupied ground.

The recommended approach is a two-speed pipeline: fast command hooks (< 100ms, PostToolUse/UserPromptSubmit/SessionStart) append raw signals to a JSONL log, while heavyweight analysis runs on the Stop hook via an agent handler and through on-demand skills. A critical architecture finding overrides the original plan: SessionEnd does NOT support agent-type hooks — the extraction agent must use the Stop hook instead. All data is stored as JSON files in `.auto-context/` (git-committable, human-readable, zero-dependency). CLAUDE.md is updated at SessionStart using HTML comment markers that protect all user-written content.

The top risks are context rot (auto-accumulated CLAUDE.md sections degrade attention), convention false positives (noise mistaken for signal), and reward signal misattribution (Write-then-Edit is a noisy proxy). Mitigation for all three starts in Phase 1: enforce a hard token budget on the auto-section (500-1000 tokens), require mandatory human review before any convention reaches CLAUDE.md, and start with explicit user feedback as the sole promotion signal before adding implicit signals. These are not Phase 4 optimizations — they are Phase 1 survival constraints.

---

## Key Findings

### Recommended Stack

The plugin uses Bash + jq exclusively for all runtime scripts. This is a deliberate zero-dependency choice: the plugin caches to `~/.claude/plugins/cache` and must work on any system with Claude Code installed. Command hooks receive JSON on stdin, must exit in under 100ms for in-loop events, and communicate back via exit codes and stdout JSON. TypeScript/Node.js and Python are explicitly ruled out — they add cold-start latency and dependency overhead that violates the hook performance constraint.

Skills (SKILL.md format) and agents (markdown frontmatter format) are the native Claude Code abstractions for user-facing commands and background analysis. Agent handlers use Claude's built-in subagent capability at no additional cost. The data store is eight JSON files in `.auto-context/`, with `session-log` using JSONL (JSON Lines) for O(1) appends instead of JSON arrays.

**Core technologies:**
- Bash (POSIX 3.2+): all hook command handlers — zero dependencies, < 100ms achievable, required by official examples
- jq 1.6+: JSON parsing in scripts — only runtime dependency, required for hook stdin/stdout I/O
- Markdown (SKILL.md / agent .md): skills and agents — native Claude Code format, no alternative
- JSON/JSONL: data storage and hook I/O — human-readable, git-committable, zero dependency

**Development tools (not runtime dependencies):**
- ShellCheck: static analysis for all bash scripts
- BATS (bats-core 1.10+): unit testing for bash scripts
- `claude --plugin-dir` + `claude plugin validate .`: official plugin testing and validation

**Minimum Claude Code version:** 1.0.33+ (for plugin system support)

### Expected Features

Research identified nine table-stakes features (expected baseline), eight differentiators (competitive advantage), and ten explicit anti-features (never build).

**Must have (table stakes):**
- `/ac-init` bootstrap scan — surpass Claude Code's built-in `/init`; detect stack, commands, conventions
- Session observation (PostToolUse, UserPromptSubmit, Stop hooks) — the "automatic" in Auto-Context
- CLAUDE.md auto-generation with marker sections — never touch user content; marker-based separation
- Closed-loop command discovery — auto-detect build/test/lint from package.json, Makefile, Cargo.toml, go.mod
- Explicit feedback capture ("remember this", "don't do this") — must be more reliable than built-in auto-memory
- `/ac-status` transparency — users need visibility into what has been learned; black-box erodes trust
- Safe CLAUDE.md coexistence — existing content preserved; handle both `./CLAUDE.md` and `.claude/CLAUDE.md`
- `/ac-review` convention review — human oversight gate before conventions reach CLAUDE.md
- Zero-config operation — install and forget; hooks register automatically via plugin manifest

**Should have (competitive differentiators):**
- Convention lifecycle (Observation -> Candidate -> Convention -> Decay) — no other tool has this; prevents stale rule accumulation
- Anti-pattern detection (correction-derived "don't do this" rules) — automates Steinberger's "organizational scar tissue"
- Path-scoped rule generation (`.claude/rules/*.md` with paths frontmatter) — no existing tool does this
- File relationship mapping (co-change tracking for module boundary detection)
- PreCompact context preservation — unique hook into Claude Code's compaction cycle
- Reward signal measurement (Write-Edit pair analysis + explicit feedback)
- Smart context injection with token budget management

**Defer (v2+):**
- Convention quality scoring (requires mature reward signals from earlier phases)
- Cross-platform AGENTS.md generation (nice-to-have portability, not core value)
- Auto-promotion without user review (not until false positive rate is measured below 5%)
- User-level preference detection (risky scope creep into ~/.claude)

**Explicit anti-features (never build):**
- Full session replay (claude-mem already does this; raw replay is noisy)
- Cloud sync or external API calls (local-first, no API keys, no auth overhead)
- Background daemon or persistent process (event-driven hooks only)
- AST-based code analysis (adds dependency weight; LLM agent handles this better)
- Complex configuration UI (violates zero-config principle)

### Architecture Approach

The system is a two-speed pipeline: fast command hooks (< 100ms) append lightweight signals to `.auto-context/session-log.jsonl` in real time, while heavyweight pattern extraction runs as an agent handler on the Stop hook and through on-demand skills. The critical finding that overrides the original plan: **SessionEnd only supports command-type hooks** — the extraction agent must use Stop instead. Stop supports agent/prompt handlers, fires when Claude finishes responding, and provides `last_assistant_message` for analysis context.

**Major components:**
1. Observation Pipeline (command hooks: PostToolUse, UserPromptSubmit) — captures raw signals < 100ms, appends to session-log.jsonl
2. Pattern Extractor (Stop agent hook + /ac-extract skill) — analyzes session data, identifies patterns, updates candidates.json
3. Lifecycle Manager (SessionStart command hook) — promotes candidates meeting threshold, decays stale conventions
4. Context Injector (SessionStart command hook) — reads conventions.json, updates CLAUDE.md marker section within token budget
5. Reward Tracker (Stop command hook) — analyzes Write-Edit pairs, updates rewards.json with per-convention scores
6. Skills Interface (ac-init, ac-status, ac-review, ac-extract, ac-reset) — user-facing controls
7. Data Store (.auto-context/ JSON/JSONL files) — all state persisted locally, git-committable

The learning loop follows a simplified reinforcement model: State (conventions.json) + Action (which conventions to inject) + Reward (Write-Edit analysis + explicit feedback) + Policy (confidence scoring). The lifecycle state machine: Raw Signal -> Candidate (3+ observations across 2+ sessions) -> Convention (user-approved) -> Decayed (5+ sessions unreferenced) -> Removed.

Context is managed at three levels: root CLAUDE.md (Phase 1), directory-level CLAUDE.md (Phase 2), and `.claude/rules/*.md` with path scoping (Phase 3). JSONL format (not JSON arrays) is mandatory for session-log to maintain O(1) append performance across long sessions.

### Critical Pitfalls

1. **Context rot** — auto-accumulated CLAUDE.md degrades Claude attention beyond ~500-1000 tokens. Avoid by enforcing a hard token budget in inject-context.sh from Phase 1 day one; implement mandatory decay that actually removes conventions, not just marks them; rank by reward signal and inject only top-K items. This is a Phase 1 survival constraint, not a Phase 4 optimization.

2. **Convention false positives (noise as signal)** — automated systems will detect framework-imposed patterns, copy-paste artifacts, and single-session flukes as conventions. Avoid by requiring observations across 2+ independent sessions (not just 3 occurrences), building a framework-pattern allowlist (Next.js routing, React hooks naming), having context-extractor classify patterns as `intentional`/`incidental`/`framework-imposed`/`uncertain`, and keeping `/ac-review` as a mandatory gate in all phases through v1.

3. **Reward signal misattribution** — Write-then-Edit is a noisy proxy; users edit Claude's output to add features, not just correct mistakes. Avoid by weighting explicit feedback 10x over implicit signals, starting with explicit-feedback-only lifecycle in Phase 2, adding implicit signals only after validating explicit signal quality, and combining multiple signal types (undo patterns, error repetition, semantic diffs) before Write-Edit alone.

4. **Context poisoning via feedback loops** — a false convention reaches CLAUDE.md, Claude follows it, the system interprets lack of correction as positive reward, confidence increases, the convention entrenches. Avoid by making `/ac-review` the mandatory promotion gate in all v1 phases, implementing a confidence decay floor (periodic re-validation every 20 sessions), and adding contradiction detection that flags new observations that conflict with existing conventions.

5. **Hook performance degradation** — session-log JSON array append is O(n) and degrades predictably. Shell startup adds 10-30ms per invocation on macOS; 50-200 hook fires per session compounds this. Avoid by using JSONL (append-only, O(1) writes) from Phase 1, adding timing instrumentation to every script from the start, and setting a hard hook timeout in hooks.json accepting dropped observations over user-perceived lag.

6. **CLAUDE.md marker section corruption** — HTML comment markers get corrupted by manual edits, git merge conflicts, or Claude's own Edit tool. Avoid by validating marker integrity in inject-context.sh before every write, maintaining `.auto-context/CLAUDE-AUTO.md` as source of truth (CLAUDE.md is a derived output), and blocking Claude's Edit tool from touching the auto-context section via PreToolUse hook.

---

## Implications for Roadmap

Research confirms the four-phase structure proposed in FEATURES.md, with one significant modification from ARCHITECTURE.md (Stop hook instead of SessionEnd for extraction). The build order has strict dependency constraints that must be respected.

### Phase 1: Foundation — Plugin Skeleton + Bootstrap

**Rationale:** All other phases depend on having a valid plugin manifest, working data store, shared script libraries, and the ability to write to CLAUDE.md. The `/ac-init` skill must deliver immediate value on install — otherwise users have no reason to keep the plugin.

**Delivers:** A working Claude Code plugin that installs via `/plugin`, bootstraps project context via `/ac-init` (surpassing Claude Code's built-in `/init`), and maintains a clean CLAUDE.md auto-section with token budget enforcement and marker protection.

**Addresses features:** T1 (bootstrap scan), T3 (CLAUDE.md generation), T4 (closed-loop command discovery), T7 (safe coexistence), T9 (zero-config)

**Avoids pitfalls:** Hook performance (use JSONL from day one), marker corruption (validate markers in inject-context.sh), context rot (hard token budget in inject-context.sh), shell injection (route all stdin through jq)

**Critical constraint:** Token budget enforcement and JSONL format must be implemented here. They cannot be retrofitted without breaking changes.

**Research flag:** Standard patterns — this phase uses well-documented Claude Code plugin APIs. No deeper research needed. Use `claude plugin validate .` as verification gate.

### Phase 2: Observation Engine — Hooks + Feedback + Status

**Rationale:** Without observation, nothing is automatic. Phase 1 delivers static bootstrap; Phase 2 makes the plugin alive and responsive to ongoing work. The observation pipeline is prerequisite for all Phase 3 learning.

**Delivers:** Real-time session observation (PostToolUse/UserPromptSubmit hooks), explicit feedback capture ("remember this" patterns), `/ac-status` transparency skill, and session cleanup (SessionEnd command hook).

**Addresses features:** T2 (session observation), T5 (explicit feedback capture), T6 (status visibility)

**Avoids pitfalls:** False positives (context-extractor must classify pattern types; require observations across 2+ sessions before candidates), performance (all hooks < 100ms with timing instrumentation), UX opacity (show session-start status message)

**Key design decision:** Start with explicit feedback as the sole signal source. Do not wire reward-based lifecycle changes in this phase. Explicit feedback is the highest-quality, lowest-noise signal available.

**Research flag:** Needs attention in planning — the detect-feedback.sh pattern matching scope is a judgment call. Starting too broad (many regex patterns) will cause false positives; starting too narrow will miss user feedback. Plan the initial pattern set carefully.

### Phase 3: Intelligence — Lifecycle, Review, Anti-Pattern Detection

**Rationale:** This is where Auto-Context becomes genuinely differentiated. The convention lifecycle (Observation -> Candidate -> Convention -> Decay) and mandatory review gate have no equivalent in competing tools. This phase requires Phase 2 to produce observation data.

**Delivers:** Stop agent hook for pattern extraction, convention lifecycle management with state machine, `/ac-review` skill for human oversight, anti-pattern detection from correction patterns, PreCompact preservation hook, reward tracking (with explicit feedback prioritized 10x over implicit).

**Addresses features:** D1 (convention lifecycle), T8 (convention review), D2 (anti-pattern detection), D7 (PreCompact preservation), D5 (reward signals — explicit-first)

**Avoids pitfalls:** Context poisoning (mandatory review gate, confidence decay floor, contradiction detection), reward misattribution (explicit signals only until implicit signal quality is validated), false positive entrenchment (cross-session diversity requirement for candidates)

**Architecture note:** The Stop hook is both the agent extraction handler AND the command-based reward tracker. Both fire on Stop — this is correct and verified against official docs. SessionEnd runs only the lightweight cleanup command.

**Research flag:** This phase carries the highest technical risk. The context-extractor agent prompt design (classifying patterns as intentional/incidental/framework-imposed) needs careful iteration. Plan a validate step: measure the `/ac-review` candidate rejection rate as a proxy for false positive rate. If rejection rate exceeds 30%, recalibrate the extraction prompt before proceeding.

### Phase 4: Advanced Context Engineering — Path Scoping, Smart Injection, Distribution

**Rationale:** Phase 4 builds on the proven learning loop from Phase 3. File relationship mapping enables path-scoped rule generation. Reward data from Phase 3 enables token budget prioritization. This phase is about quality and distribution, not core functionality.

**Delivers:** File relationship mapping (co-change tracking), path-scoped `.claude/rules/` generation, directory-level CLAUDE.md files, smart context injection with reward-weighted prioritization, token budget overflow to rules files, marketplace packaging and distribution.

**Addresses features:** D4 (file relationships), D3 (path-scoped rules), D6 (smart injection), marketplace distribution

**Avoids pitfalls:** Context explosion (token budget overflow to rules files rather than CLAUDE.md), over-engineering (if smart injection logic is more complex than conventions themselves, simplify)

**Research flag:** Path-scoped rule generation (D3) has no reference implementation to validate against — it is genuinely novel. Build incrementally: file relationship detection first, then path-scoped generation only when relationships exceed a confidence threshold.

### Phase Ordering Rationale

- Phases 1-4 form a strict dependency chain: manifest -> data store -> hooks -> extraction -> lifecycle -> scoring -> distribution
- inject-context.sh is in Phase 1 (not Phase 3) because even /ac-init needs to write to CLAUDE.md
- Explicit feedback (T5) is in Phase 2, not Phase 3, because it is the foundation for reward signals — Phase 3 reward tracking builds on it
- Token budget and JSONL are Phase 1 survival constraints; retrofitting them later requires breaking changes
- The Stop-instead-of-SessionEnd architecture discovery is critical: ensure hooks.json in Phase 1 scaffold uses the correct Stop handler target even before extraction is implemented

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 3 (Intelligence):** Convention extraction agent prompt design is novel with no reference implementation. The boundary between "intentional pattern" and "incidental pattern" requires careful calibration. Plan a dedicated research step for the context-extractor agent prompt before implementation.
- **Phase 4 (Distribution):** Marketplace submission process to Anthropic's official marketplace is not fully documented. Use Phase 4 planning research to verify current submission requirements.

Phases with standard patterns (skip research-phase):
- **Phase 1 (Foundation):** Plugin manifest, hooks.json, SKILL.md format are fully documented in official Claude Code docs at HIGH confidence. JSONL format is well-established. No research needed.
- **Phase 2 (Observation):** PostToolUse/UserPromptSubmit command hooks follow documented patterns. Explicit feedback detection via regex is straightforward. No research needed.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All platform facts verified against official Claude Code documentation (hooks, skills, agents, plugin manifest, environment variables). Bash + jq choice is corroborated by official Anthropic examples. |
| Features | HIGH (table stakes) / MEDIUM (differentiators) | Table stakes verified against Claude Code docs, AGENTS.md standard, and community patterns. Differentiators (D1-D8) are design synthesis with no external validation — they are novel by definition. |
| Architecture | HIGH (hook types/events) / MEDIUM (design patterns) | Critical SessionEnd finding (command-only) is HIGH confidence from official docs. Two-speed pipeline design and lifecycle state machine are synthesis with no direct external validation. |
| Pitfalls | MEDIUM-HIGH | Context rot, false positives, and reward hacking are corroborated by published research (Chroma, METR, ICLR 2025). CLAUDE.md marker corruption and hook performance are first-principles extrapolation from verified platform behavior. |

**Overall confidence:** HIGH for platform facts, MEDIUM for design decisions

### Gaps to Address

- **Convention promotion threshold calibration:** The plan specifies 3 observations across 2+ sessions. This threshold is not validated anywhere. During Phase 3 planning, treat this as a tunable parameter and build instrumentation to measure it empirically.
- **Reward signal weighting (10x explicit over implicit):** The 10x weighting factor is proposed, not validated. Treat as a starting point; build A/B tracking into `/ac-status` to measure whether the weighting is actually improving convention quality.
- **Convention decay timing (5 sessions):** Proposed in plan, not validated. Start conservative (longer decay period) and shorten empirically. Wrong decay timing causes either stale convention accumulation or thrashing.
- **Token budget (500-1000 tokens):** Chroma Research supports the general principle; the specific limits need validation against real projects. Build in configurability from Phase 1 so the limit can be tuned without code changes.
- **Stop hook agent + command hook interaction:** Both the agent extraction and command reward tracking fire on Stop. Official docs confirm this is valid (multiple hooks per event), but the ordering and potential race conditions on `.auto-context/` files need verification during Phase 3 implementation.

---

## Sources

### Primary (HIGH confidence)
- [Claude Code Plugins Reference](https://code.claude.com/docs/en/plugins-reference) — plugin manifest schema, directory structure, environment variables, CLI commands
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) — all 16 hook events, handler types, JSON I/O schemas, exit codes, matcher patterns; source of critical SessionEnd finding
- [Claude Code Skills Reference](https://code.claude.com/docs/en/skills) — SKILL.md format, frontmatter fields, dynamic context injection
- [Claude Code Subagents Reference](https://code.claude.com/docs/en/sub-agents) — agent markdown format, built-in agents, model selection; no-nesting constraint
- [Claude Code Memory Reference](https://code.claude.com/docs/en/memory) — multi-level CLAUDE.md hierarchy, auto-memory, path-scoped rules
- [Claude Code Plugin Marketplaces](https://code.claude.com/docs/en/plugin-marketplaces) — marketplace.json format, distribution, installation scopes
- [Anthropic: Effective Context Engineering for AI Agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) — official context engineering patterns

### Secondary (MEDIUM confidence)
- [Peter Steinberger's AGENTS.MD](https://github.com/steipete/agent-scripts/blob/main/AGENTS.MD) — ~150-line reference implementation (note: widely cited as 800 lines; actual file is ~150 lines)
- [AGENTS.md Standard](https://agents.md/) — cross-platform format specification
- [claude-mem Plugin](https://github.com/thedotmack/claude-mem) — competitor architecture (README analysis only)
- [Chroma Research: Context Rot](https://research.trychroma.com/context-rot) — LLM performance degradation with increasing context
- [METR: Recent Frontier Models Are Reward Hacking](https://metr.org/blog/2025-06-05-recent-reward-hacking/) — reward proxy optimization failures
- [ICLR 2025: Strong Model Collapse](https://proceedings.iclr.cc/paper_files/paper/2025/file/284afdc2309f9667d2d4fb9290235b0c-Paper-Conference.pdf) — feedback loop degradation
- [Martin Fowler: Context Engineering for Coding Agents](https://martinfowler.com/articles/exploring-gen-ai/context-engineering-coding-agents.html) — layer model and patterns
- [Spotify: Context Engineering for Background Agents](https://engineering.atspotify.com/2025/11/context-engineering-background-coding-agents-part-2) — production patterns

### Tertiary (LOW confidence, needs validation)
- Convention decay timing (5-session threshold) — proposed in plan, no external validation
- Reward signal weighting (10x explicit vs implicit) — proposed, needs empirical calibration
- "800-line AGENTS.MD" claim — widely cited but contradicted by direct file analysis (~150 lines)

---
*Research completed: 2026-02-24*
*Ready for roadmap: yes*
