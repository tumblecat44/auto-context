# Requirements: Auto-Context

**Defined:** 2026-02-24
**Core Value:** Use Claude Code normally, and your project context improves automatically.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Plugin Foundation

- [x] **PLUG-01**: Plugin manifest (plugin.json) registers hooks, skills, agents automatically on install
- [x] **PLUG-02**: Plugin operates zero-config — no user configuration needed after `claude plugin install`
- [x] **PLUG-03**: CLAUDE.md auto-content lives in marker sections (`<!-- auto-context:start/end -->`), user content never touched
- [x] **PLUG-04**: Marker section validates integrity on every injection (handles corruption, duplication, missing markers)
- [x] **PLUG-05**: `claude plugin validate .` passes on the plugin package

### Bootstrap & Discovery

- [ ] **BOOT-01**: `/ac-init` scans project structure, tech stack, config files, git history to generate initial context
- [ ] **BOOT-02**: `/ac-init` surpasses Claude Code's built-in `/init` quality (detects architecture patterns, existing conventions)
- [ ] **BOOT-03**: Auto-discover build/test/lint commands from package.json scripts, Makefile targets, pyproject.toml, Cargo.toml
- [ ] **BOOT-04**: Track file co-change relationships from session observations and git history
- [ ] **BOOT-05**: Generate file relationship map in `.auto-context/file-relations.json`

### Session Observation

- [ ] **OBSV-01**: PostToolUse hook logs file modifications (Write/Edit) to session log in JSONL format
- [ ] **OBSV-02**: PostToolUse hook logs Bash command executions and errors to session log
- [ ] **OBSV-03**: All observation hooks execute < 100ms (no user-perceived latency)
- [x] **OBSV-04**: Session log uses JSONL format (O(1) appends, not JSON arrays)
- [ ] **OBSV-05**: Session log rotated/cleared at session end (never accumulates across sessions)

### Explicit Feedback

- [ ] **FDBK-01**: UserPromptSubmit hook detects "remember this"/"기억해" patterns and writes to conventions immediately
- [ ] **FDBK-02**: UserPromptSubmit hook detects "don't do this"/"하지 마" patterns and writes to anti-patterns immediately
- [ ] **FDBK-03**: Explicit feedback weighted 10x over implicit signals in convention lifecycle

### Pattern Extraction

- [ ] **EXTR-01**: Stop hook agent handler analyzes session log for coding patterns, naming conventions, file structure patterns
- [ ] **EXTR-02**: Extraction agent classifies patterns as intentional/incidental/framework-imposed/uncertain
- [ ] **EXTR-03**: Only intentional patterns promoted to candidates (framework-imposed excluded)
- [ ] **EXTR-04**: Extraction agent cites specific file:line evidence for each detected pattern

### Convention Lifecycle

- [x] **LIFE-01**: 4-stage lifecycle: Observation → Candidate (3+ occurrences across 2+ sessions) → Convention → Decay
- [x] **LIFE-02**: Candidates require observations from 2+ independent sessions before promotion
- [x] **LIFE-03**: Conventions decay after 5+ sessions without reference
- [x] **LIFE-04**: Decayed conventions removed from CLAUDE.md injection
- [x] **LIFE-05**: Maximum 50 active conventions (lowest-confidence evicted when exceeded)
- [ ] **LIFE-06**: Mandatory user review gate via /ac-review before any convention reaches CLAUDE.md in v1

### Anti-Pattern Detection

- [ ] **ANTI-01**: Detect user correction patterns (Write→Edit sequences with semantic change) as negative signals
- [ ] **ANTI-02**: Detect repeated error patterns across sessions (same error 2+ times = strong negative)
- [ ] **ANTI-03**: Auto-register anti-patterns from explicit "don't do this" feedback
- [ ] **ANTI-04**: Anti-patterns stored in `.auto-context/anti-patterns.json` and injected into CLAUDE.md

### Reward Signal

- [ ] **RWRD-01**: Track Write→Edit pair analysis as implicit reward signal at Stop hook
- [ ] **RWRD-02**: Combine explicit feedback (10x weight) with implicit signals for convention confidence scoring
- [ ] **RWRD-03**: Store reward history in `.auto-context/rewards.json`
- [ ] **RWRD-04**: Display signal quality breakdown in /ac-status

### Smart Injection

- [x] **INJT-01**: Hard token budget (max 1000 tokens) for auto-context CLAUDE.md section
- [ ] **INJT-02**: Prioritize conventions by confidence score within token budget
- [ ] **INJT-03**: Overflow high-confidence conventions to `.claude/rules/auto-context-*.md` with path-scoped frontmatter
- [x] **INJT-04**: SessionStart hook injects conventions → CLAUDE.md marker section

### Path-Scoped Rules

- [ ] **PATH-01**: Detect module-specific conventions (patterns that apply only to certain file paths)
- [ ] **PATH-02**: Auto-generate `.claude/rules/auto-context-*.md` files with `paths:` frontmatter
- [ ] **PATH-03**: Path-scoped rules loaded on-demand by Claude Code (not at session start)

### Context Preservation

- [ ] **PRSC-01**: PreCompact hook backs up critical context data before context compression
- [ ] **PRSC-02**: SessionStart hook restores context from backup if needed

### Transparency & Control

- [ ] **TRNS-01**: `/ac-status` shows observation count, candidates, conventions, anti-patterns, reward trends
- [ ] **TRNS-02**: `/ac-review` displays candidate list with approve/reject/edit per item
- [ ] **TRNS-03**: `/ac-reset` clears `.auto-context/` directory and removes CLAUDE.md auto-section
- [ ] **TRNS-04**: Session-start status line: "Auto-Context: N conventions active, M candidates pending"
- [x] **TRNS-05**: Log convention changes with reason: "Added convention: use async/await (observed 5x across 3 sessions)"

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Advanced Intelligence

- **ADVN-01**: Convention quality scoring (prune low-value conventions by impact/token-cost ratio)
- **ADVN-02**: AGENTS.md cross-platform output (generate AGENTS.md alongside CLAUDE.md)
- **ADVN-03**: Semantic diff for Write→Edit reward signal (distinguish correction from extension)
- **ADVN-04**: Non-English feedback pattern support (beyond Korean/English)

### Distribution

- **DIST-01**: Official Anthropic marketplace registration
- **DIST-02**: Project-scope installation support (team sharing via `.claude-plugin/`)

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Full session replay (claude-mem approach) | Raw replay is noisy. Structured conventions > quantity. |
| IDE integration (VS Code, Cursor) | Claude Code plugin exclusive. Other tools have own ecosystems. |
| Cloud sync / team sharing | Local-first v1. Teams share via git. |
| External API calls | Plugin uses built-in agent handlers. No API keys needed. |
| AST-based code analysis | LLM agent handlers more flexible, language-agnostic. |
| Background daemon/server | Event-driven hooks only. No persistent processes. |
| Replacing Claude Code auto-memory | Complement, don't compete. Different purposes. |
| Complex configuration UI | Zero-config principle. Sensible defaults only. |
| Multi-model support | Claude Code exclusive. AGENTS.md compatibility is a nice side effect. |
| Auto-promotion without review | Deferred until false positive rate < 5%. Safety first. |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| PLUG-01 | Phase 1 | Complete |
| PLUG-02 | Phase 1 | Complete |
| PLUG-03 | Phase 1 | Complete |
| PLUG-04 | Phase 1 | Complete |
| PLUG-05 | Phase 1 | Complete |
| BOOT-01 | Phase 2 | Pending |
| BOOT-02 | Phase 2 | Pending |
| BOOT-03 | Phase 2 | Pending |
| BOOT-04 | Phase 8 | Pending |
| BOOT-05 | Phase 8 | Pending |
| OBSV-01 | Phase 3 | Pending |
| OBSV-02 | Phase 3 | Pending |
| OBSV-03 | Phase 3 | Pending |
| OBSV-04 | Phase 1 | Complete |
| OBSV-05 | Phase 3 | Pending |
| FDBK-01 | Phase 4 | Pending |
| FDBK-02 | Phase 4 | Pending |
| FDBK-03 | Phase 4 | Pending |
| EXTR-01 | Phase 5 | Pending |
| EXTR-02 | Phase 5 | Pending |
| EXTR-03 | Phase 5 | Pending |
| EXTR-04 | Phase 5 | Pending |
| LIFE-01 | Phase 6 | Complete |
| LIFE-02 | Phase 6 | Complete |
| LIFE-03 | Phase 6 | Complete |
| LIFE-04 | Phase 6 | Complete |
| LIFE-05 | Phase 6 | Complete |
| LIFE-06 | Phase 6 | Pending |
| ANTI-01 | Phase 7 | Pending |
| ANTI-02 | Phase 7 | Pending |
| ANTI-03 | Phase 7 | Pending |
| ANTI-04 | Phase 7 | Pending |
| RWRD-01 | Phase 7 | Pending |
| RWRD-02 | Phase 7 | Pending |
| RWRD-03 | Phase 7 | Pending |
| RWRD-04 | Phase 7 | Pending |
| INJT-01 | Phase 1 | Complete |
| INJT-02 | Phase 8 | Pending |
| INJT-03 | Phase 8 | Pending |
| INJT-04 | Phase 1 | Complete |
| PATH-01 | Phase 8 | Pending |
| PATH-02 | Phase 8 | Pending |
| PATH-03 | Phase 8 | Pending |
| PRSC-01 | Phase 6 | Pending |
| PRSC-02 | Phase 6 | Pending |
| TRNS-01 | Phase 6 | Pending |
| TRNS-02 | Phase 6 | Pending |
| TRNS-03 | Phase 2 | Pending |
| TRNS-04 | Phase 4 | Pending |
| TRNS-05 | Phase 6 | Complete |

**Coverage:**
- v1 requirements: 50 total
- Mapped to phases: 50
- Unmapped: 0

---
*Requirements defined: 2026-02-24*
*Last updated: 2026-02-24 after roadmap creation*
