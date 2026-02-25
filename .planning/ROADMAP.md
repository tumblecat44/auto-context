# Roadmap: Auto-Context

## Overview

Auto-Context transforms Claude Code's project context from a manually-maintained burden into a self-improving system. The build progresses through eight phases: a plugin skeleton with CLAUDE.md injection and token budget enforcement; project bootstrap scanning; real-time session observation; explicit user feedback capture; pattern extraction via Stop hook agent; convention lifecycle with mandatory review gates; anti-pattern detection and reward signals; and finally path-scoped rules with smart injection. Each phase delivers a verifiable capability that the next phase depends on.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Plugin Skeleton & Injection** - Valid plugin manifest, CLAUDE.md marker injection with token budget, data store (completed 2026-02-24)
- [x] **Phase 2: Project Bootstrap** - /ac-init scans project structure and generates initial context (completed 2026-02-25)
- [x] **Phase 3: Session Observation** - PostToolUse hooks capture file changes and commands in real-time JSONL log (completed 2026-02-25)
- [x] **Phase 4: Explicit Feedback** - User prompts like "remember this" and "don't do this" captured as conventions/anti-patterns (completed 2026-02-25)
- [x] **Phase 5: Pattern Extraction** - Stop hook agent analyzes session logs to identify coding patterns (completed 2026-02-25)
- [x] **Phase 6: Convention Lifecycle & Review** - 4-stage lifecycle with mandatory user review gate before CLAUDE.md (completed 2026-02-25)
- [x] **Phase 7: Anti-Patterns & Reward Signals** - Correction detection, error tracking, and confidence scoring (completed 2026-02-25)
- [x] **Phase 8: Path-Scoped Rules & Smart Injection** - Module-specific rules, file relationships, reward-weighted injection (completed 2026-02-25)

## Phase Details

### Phase 1: Plugin Skeleton & Injection
**Goal**: A valid Claude Code plugin that installs, creates the data store, and can write to CLAUDE.md within a hard token budget
**Depends on**: Nothing (first phase)
**Requirements**: PLUG-01, PLUG-02, PLUG-03, PLUG-04, PLUG-05, INJT-01, INJT-04, OBSV-04
**Success Criteria** (what must be TRUE):
  1. `claude plugin validate .` passes on the plugin package
  2. `claude plugin install` registers the plugin with zero user configuration needed
  3. CLAUDE.md auto-content appears inside `<!-- auto-context:start/end -->` markers and existing user content is untouched
  4. Marker section validates integrity on injection (handles corruption, duplication, missing markers gracefully)
  5. Auto-context section never exceeds 1000 tokens regardless of input
**Plans**: 2 plans

Plans:
- [x] 01-01-PLAN.md — Plugin scaffold, hook config, data store init, JSONL session log
- [x] 01-02-PLAN.md — CLAUDE.md marker injection with integrity validation and token budget enforcement

### Phase 2: Project Bootstrap
**Goal**: Users run /ac-init and get high-quality project context that surpasses Claude Code's built-in /init
**Depends on**: Phase 1
**Requirements**: BOOT-01, BOOT-02, BOOT-03, TRNS-03
**Success Criteria** (what must be TRUE):
  1. `/ac-init` scans project structure, tech stack, config files, and git history to generate initial context
  2. `/ac-init` detects architecture patterns and existing conventions beyond what `/init` produces
  3. Build/test/lint commands are auto-discovered from package.json, Makefile, pyproject.toml, Cargo.toml
  4. `/ac-reset` clears `.auto-context/` directory and removes CLAUDE.md auto-section cleanly
**Plans**: 2 plans

Plans:
- [x] 02-01-PLAN.md — /ac-init skill with discover-commands script and multi-step scanning instructions
- [x] 02-02-PLAN.md — /ac-reset skill and plugin skills validation

### Phase 3: Session Observation
**Goal**: The plugin silently captures file modifications and command executions in real-time with zero user-perceived latency
**Depends on**: Phase 1
**Requirements**: OBSV-01, OBSV-02, OBSV-03, OBSV-05
**Success Criteria** (what must be TRUE):
  1. PostToolUse hook logs file modifications (Write/Edit tool usage) to session-log.jsonl
  2. PostToolUse hook logs Bash command executions and errors to session-log.jsonl
  3. All observation hooks execute in under 100ms (no user-perceived delay)
  4. Session log is rotated/cleared at session end (never accumulates across sessions)
**Plans**: 2 plans

Plans:
- [x] 03-01-PLAN.md — PostToolUse observation hook for Write/Edit/Bash with PostToolUseFailure error logging
- [x] 03-02-PLAN.md — SessionEnd log rotation and SessionStart stale log safety net

### Phase 4: Explicit Feedback
**Goal**: Users can say "remember this" or "don't do this" and the plugin captures it immediately as a convention or anti-pattern
**Depends on**: Phase 1
**Requirements**: FDBK-01, FDBK-02, FDBK-03, TRNS-04
**Success Criteria** (what must be TRUE):
  1. UserPromptSubmit hook detects "remember this" / "don't do this" patterns (English and Korean) and writes to storage immediately
  2. Explicit feedback is weighted 10x over implicit signals in all downstream confidence scoring
  3. Session-start status line displays "Auto-Context: N conventions active, M candidates pending"
**Plans**: 2 plans

Plans:
- [x] 04-01-PLAN.md — UserPromptSubmit hook for English/Korean feedback detection with convention/anti-pattern persistence
- [x] 04-02-PLAN.md — Session-start status line enhancement with anti-pattern count

### Phase 5: Pattern Extraction
**Goal**: At session end, an agent analyzes the session log and identifies intentional coding patterns with cited evidence
**Depends on**: Phase 3
**Requirements**: EXTR-01, EXTR-02, EXTR-03, EXTR-04
**Success Criteria** (what must be TRUE):
  1. Stop hook agent handler analyzes session-log.jsonl for coding patterns, naming conventions, and file structure patterns
  2. Extraction agent classifies each pattern as intentional / incidental / framework-imposed / uncertain
  3. Only intentional patterns are promoted to candidate status (framework-imposed patterns excluded)
  4. Each detected pattern includes specific file:line evidence citations
**Plans**: 2 plans

Plans:
- [x] 05-01-PLAN.md — Extraction agent prompt with classification taxonomy and evidence requirements
- [x] 05-02-PLAN.md — Stop agent hook registration and session log archive safety net

### Phase 6: Convention Lifecycle & Review
**Goal**: Conventions follow a rigorous 4-stage lifecycle and never reach CLAUDE.md without explicit user approval
**Depends on**: Phase 5
**Requirements**: LIFE-01, LIFE-02, LIFE-03, LIFE-04, LIFE-05, LIFE-06, TRNS-01, TRNS-02, TRNS-05, PRSC-01, PRSC-02
**Success Criteria** (what must be TRUE):
  1. Conventions progress through Observation -> Candidate (3+ occurrences across 2+ sessions) -> Convention -> Decay lifecycle
  2. No convention reaches CLAUDE.md without user approval via /ac-review
  3. Conventions decay after 5+ sessions without reference and are removed from CLAUDE.md injection
  4. Maximum 50 active conventions enforced (lowest-confidence evicted when exceeded)
  5. /ac-status shows observation counts, candidates, conventions, anti-patterns, and reward trends
**Plans**: 3 plans

Plans:
- [x] 06-01-PLAN.md — Lifecycle state machine: session counter, promotion, decay, cap enforcement, migration, changelog
- [x] 06-02-PLAN.md — /ac-review and /ac-status skills for mandatory review gate and pipeline visibility
- [x] 06-03-PLAN.md — PreCompact context preservation hook and SessionStart restore logic

### Phase 7: Anti-Patterns & Reward Signals
**Goal**: The plugin detects what Claude should NOT do (from corrections and errors) and measures convention quality through reward signals
**Depends on**: Phase 3, Phase 6
**Requirements**: ANTI-01, ANTI-02, ANTI-03, ANTI-04, RWRD-01, RWRD-02, RWRD-03, RWRD-04
**Success Criteria** (what must be TRUE):
  1. User correction patterns (Write->Edit sequences with semantic change) are detected as negative signals
  2. Repeated error patterns across sessions (same error 2+ times) are flagged as strong negatives
  3. Anti-patterns from explicit "don't do this" feedback are auto-registered and injected into CLAUDE.md
  4. Write->Edit pair analysis produces implicit reward signals combined with explicit feedback (10x weight) for confidence scoring
  5. /ac-status displays signal quality breakdown and reward trends
**Plans**: 2 plans

Plans:
- [x] 07-01-PLAN.md — Anti-pattern detection engine, CLAUDE.md injection pipeline, and reward signal storage
- [x] 07-02-PLAN.md — Reward signal display and anti-pattern breakdown in /ac-status

### Phase 8: Path-Scoped Rules & Smart Injection
**Goal**: Conventions that apply only to specific modules are delivered as path-scoped rules, and injection prioritizes by confidence within the token budget
**Depends on**: Phase 6, Phase 7
**Requirements**: PATH-01, PATH-02, PATH-03, INJT-02, INJT-03, BOOT-04, BOOT-05
**Success Criteria** (what must be TRUE):
  1. Module-specific conventions are detected (patterns that apply only to certain file paths)
  2. `.claude/rules/auto-context-*.md` files are auto-generated with `paths:` frontmatter for path-scoped delivery
  3. Conventions are prioritized by confidence score within the token budget
  4. High-confidence conventions that overflow the CLAUDE.md token budget are placed in `.claude/rules/` files
  5. File co-change relationships are tracked from session observations and git history into `.auto-context/file-relations.json`
**Plans**: 2 plans

Plans:
- [x] 08-01-PLAN.md — File co-change tracking from git history and session observations
- [x] 08-02-PLAN.md — Path-scoped rule generation and smart confidence-weighted injection pipeline

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8
Note: Phases 2, 3, 4 all depend on Phase 1 and could execute in parallel, but sequential is recommended for solo developer.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Plugin Skeleton & Injection | 2/2 | Complete    | 2026-02-24 |
| 2. Project Bootstrap | 2/2 | Complete | 2026-02-25 |
| 3. Session Observation | 2/2 | Complete | 2026-02-25 |
| 4. Explicit Feedback | 2/2 | Complete | 2026-02-25 |
| 5. Pattern Extraction | 2/2 | Complete | 2026-02-25 |
| 6. Convention Lifecycle & Review | 3/3 | Complete    | 2026-02-25 |
| 7. Anti-Patterns & Reward Signals | 2/2 | Complete | 2026-02-25 |
| 8. Path-Scoped Rules & Smart Injection | 2/2 | Complete | 2026-02-25 |
