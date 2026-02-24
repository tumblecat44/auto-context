# Pitfalls Research

**Domain:** Context Engineering Automation (Auto-CLAUDE.md Generation)
**Researched:** 2026-02-24
**Confidence:** MEDIUM-HIGH (multiple credible sources corroborate core findings; some domain-specific claims based on first-principles reasoning from verified patterns)

## Critical Pitfalls

### Pitfall 1: Context Rot -- More Context Degrades Quality

**What goes wrong:**
The auto-generated CLAUDE.md grows over time as conventions accumulate. Once it crosses ~500 lines or ~1000 tokens of instructions, Claude's adherence to those instructions drops significantly. Chroma Research's 2025 study of 18 LLMs found that model performance degrades non-uniformly as input length increases -- even on simple tasks. The "attention budget" gets stretched thin and the model loses the ability to reliably attend to all injected context. Instructions in the middle of a long CLAUDE.md are particularly vulnerable (the "lost in the middle" effect).

**Why it happens:**
Automated systems naturally accumulate. Without aggressive pruning, every detected convention gets added but nothing gets removed. The system optimizes for completeness (adding useful patterns) without accounting for the attention cost of each additional token. Steinberger's 800-line AGENTS.md works because every line was hand-curated to justify its token cost -- automation lacks that curation instinct.

**How to avoid:**
- Enforce a hard token budget on the auto-context section (start at 500 tokens, max 1000 tokens). This is the single most important constraint.
- Implement mandatory decay: conventions that go unreferenced for N sessions must be evicted, not just marked as decayed.
- Rank conventions by impact (reward signal correlation) and only include top-K items within the token budget.
- Use the "less is more" principle from the Steinberger approach: 10-15 hard constraints beat 50 soft suggestions.
- Consider on-demand context loading via Skills rather than static CLAUDE.md injection for lower-priority conventions.

**Warning signs:**
- Auto-context section exceeds 500 lines or 1000 tokens
- User reports that Claude "forgets" or "ignores" conventions that are present in CLAUDE.md
- Reward signal (acceptance rate) plateaus or declines despite adding more conventions
- Conventions at the bottom of the auto-section are followed less reliably than those at the top

**Phase to address:**
Phase 1 (Plugin Skeleton) -- the token budget must be a hard constraint from day one. The injection script (`inject-context.sh`) must enforce a maximum token count and prioritize conventions by confidence/impact score. This is not a Phase 4 optimization -- it is a Phase 1 survival constraint.

**Severity:** CRITICAL
**Likelihood:** HIGH -- this will happen without explicit prevention

---

### Pitfall 2: Convention Detection False Positives (Noise as Signal)

**What goes wrong:**
The pattern extraction agent detects "conventions" that are actually one-off decisions, copy-paste artifacts, or framework boilerplate. Industry data from static analysis tools shows that even mature tools operate at 5-15% false positive rates. For a novel system doing convention inference (not just rule checking), expect 20-40% false positive rate initially. False conventions injected into CLAUDE.md actively mislead Claude, causing it to follow incorrect patterns with high confidence.

**Why it happens:**
Convention detection requires distinguishing between:
- Intentional patterns (real conventions) -- e.g., "we always use `async/await` instead of `.then()`"
- Incidental patterns (correlation not convention) -- e.g., "the last 3 files happened to use camelCase because they were in a specific module"
- Framework-imposed patterns (not team choices) -- e.g., Next.js file naming is a framework requirement, not a convention
- Copy-paste propagation (one bad pattern repeated) -- duplication looks like consistency

The plan requires 3 occurrences to promote to Candidate, but 3 occurrences in a short time window (single session or related feature work) is not statistically significant. The observations are not independent.

**How to avoid:**
- Require observations across multiple independent sessions (not just 3 occurrences within one session). A convention should be observed in at least 2-3 separate sessions to be promoted to Candidate.
- Separate framework-imposed patterns from team conventions. Build an allowlist of known framework patterns (Next.js routing, React hooks naming, etc.) and exclude them from convention detection.
- Require the context-extractor agent to explicitly classify each detected pattern: `intentional`, `incidental`, `framework-imposed`, `uncertain`. Only `intentional` patterns should become candidates.
- Keep the `/ac-review` skill as a mandatory gate before any convention reaches CLAUDE.md in v1. Auto-promotion is a Phase 4 feature, not Phase 2.
- Weight observations by diversity: patterns seen across different file types, different modules, and different sessions count more than repeated patterns in one area.

**Warning signs:**
- Users frequently rejecting candidates in `/ac-review`
- Conventions that contradict each other appearing in the candidates list
- CLAUDE.md contains framework-obvious rules that any developer would know (e.g., "use `export default` in page components")
- The same pattern detected in copied/duplicated code across files

**Phase to address:**
Phase 2 (Observation) -- the context-extractor agent prompt must be carefully designed to distinguish convention types. Phase 3 (Learning) -- the lifecycle management must enforce cross-session diversity requirements.

**Severity:** CRITICAL
**Likelihood:** HIGH -- convention inference is inherently noisy

---

### Pitfall 3: Reward Signal Misattribution (Write-then-Edit is a Noisy Proxy)

**What goes wrong:**
The plan uses "Claude Writes file, user Edits same file shortly after" as a negative reward signal and "Claude Writes file, no subsequent Edit" as a positive signal. This proxy is deeply flawed:
- Users edit Claude's output to add features, not to correct mistakes
- Users may not edit a wrong file because they did not notice the error yet
- Users may Edit a file Claude wrote for reasons unrelated to Claude's output quality (adding imports, expanding a feature)
- The time window matters enormously: an Edit 2 minutes later is likely a correction; an Edit 30 minutes later is likely new work

If reward signals are wrong, the entire lifecycle (promotion, decay, confidence scoring) optimizes toward the wrong objective. This is the classic **reward hacking** problem: the system optimizes a proxy metric that diverges from the true goal.

**Why it happens:**
METR's 2025 research on frontier models found that systems consistently find ways to optimize proxy metrics rather than true objectives. The Write-then-Edit heuristic is easy to implement but conflates several different user behaviors. The fundamental issue is that user intent (correction vs. extension) cannot be reliably inferred from tool usage alone.

**How to avoid:**
- Do not use Write-then-Edit as the sole reward signal. Combine multiple signals:
  1. **Explicit feedback** ("remember this", "don't do this") -- highest quality signal, lowest volume
  2. **Error repetition** (same error pattern appears in multiple sessions) -- strong negative signal
  3. **Undo patterns** (git revert, immediate full-file rewrite) -- stronger correction signal than partial Edit
  4. **Write-then-Edit with semantic diff** -- only count as negative if the Edit semantically changes Claude's logic (not just adding lines)
- Weight explicit feedback 10x over implicit signals. A single "don't do this" is worth more than 50 Write-then-Edit observations.
- Start with explicit feedback only (Phase 2) and add implicit signals later (Phase 3) only after validating the explicit signal pipeline works.
- Build a "signal quality dashboard" into `/ac-status` so the developer can see what signals are driving convention changes.

**Warning signs:**
- Reward scores fluctuate wildly session to session
- Conventions being demoted that the user actually values
- System promotes "safe" but unhelpful conventions (ones that are trivially correct but low-value)
- High-impact conventions get low confidence scores because users extend Claude's output (falsely counted as correction)

**Phase to address:**
Phase 3 (Learning) -- `track-reward.sh` must implement signal weighting and semantic diff analysis. Do not ship reward-based lifecycle management without multiple signal sources.

**Severity:** CRITICAL
**Likelihood:** HIGH -- proxy metrics always diverge from true objectives without careful design

---

### Pitfall 4: Context Poisoning via Incorrect Convention Entrenchment

**What goes wrong:**
A false convention makes it into CLAUDE.md. Claude now follows it faithfully. Because Claude follows it, the convention appears to be "working" (no correction needed). The convention's confidence score increases. It becomes harder to remove. This is a positive feedback loop that entrenches incorrect patterns.

Anthropic's own context engineering guidance warns: "One incorrect API pattern in your knowledge file means every future implementation will be wrong. Hallucinations in knowledge documents are catastrophic -- they compound with every use."

**Why it happens:**
This is the "model collapse" problem applied to context engineering. Research on AI feedback loops (ICLR 2025) shows that when systems learn from their own outputs, small errors compound into entropy spirals. In Auto-Context:
1. False convention enters CLAUDE.md
2. Claude follows the false convention in its output
3. User does not correct (because the output "looks right" or they do not notice)
4. System interprets lack of correction as positive reward
5. Convention confidence increases
6. Convention becomes harder to remove

This is structurally identical to model collapse through recursive self-training.

**How to avoid:**
- **Mandatory human review gate**: No convention should reach CLAUDE.md without user approval in v1. Auto-promotion is dangerous until the system has proven its detection accuracy.
- **Confidence decay floor**: Even high-confidence conventions should periodically require re-validation (e.g., every 20 sessions, re-present to user for confirmation).
- **Contradiction detection**: If a new observation contradicts an existing convention, flag it immediately rather than silently averaging.
- **Easy removal**: `/ac-review` must make it trivially easy to delete conventions. One-command removal, not a multi-step process.
- **Separate signal sources**: Use original human behavior (before convention injection) as ground truth. Track whether conventions change user behavior or merely reinforce Claude's behavior.

**Warning signs:**
- A convention has very high confidence but was never explicitly approved by the user
- `/ac-review` shows conventions the user does not recognize as their own practice
- Claude's coding style diverges from the user's actual preferences
- The user starts manually overriding CLAUDE.md auto-sections

**Phase to address:**
Phase 3 (Learning) -- lifecycle management must include re-validation cycles. Phase 2 (Observation) -- the context-extractor must flag uncertainty levels for each detected pattern.

**Severity:** CRITICAL
**Likelihood:** MEDIUM -- mitigated by the planned `/ac-review` gate, but still possible if users rubber-stamp reviews

---

### Pitfall 5: Hook Performance Kills the User Experience

**What goes wrong:**
The plan specifies command handlers must execute < 100ms, but real-world conditions make this hard to guarantee. `observe-tool.sh` runs on every PostToolUse event (every Write, Edit, or Bash call). In a typical Claude Code session, this can fire 50-200 times. If any hook takes 200ms due to disk I/O, jq parsing of a growing session-log.json, or file locking contention, the cumulative delay becomes noticeable. Users perceive Claude as "sluggish" and blame the plugin.

**Why it happens:**
- `session-log.json` grows throughout a session. jq must parse the entire file to append new entries (JSON is not an append-friendly format).
- Disk I/O varies: on spinning disk or network-mounted drives, file operations are slower.
- Multiple hooks fire on the same event: `SessionStart` triggers both `manage-lifecycle.sh` and `inject-context.sh` sequentially.
- Shell script startup overhead (fork, exec, path resolution) adds ~10-30ms per invocation on macOS.

**How to avoid:**
- Use JSON Lines (`.jsonl`) instead of JSON arrays for session-log. JSONL is append-only: `echo "$json_line" >> session-log.jsonl` -- no parsing needed for writes, O(1) append.
- Cache parsed data in memory-mapped files or use a simple lock-free append strategy.
- Measure and monitor: add timing instrumentation to every hook script from day one. Log execution time to a debug file.
- Set a hard timeout in hooks.json (the `timeout` field) and accept that some observations may be dropped rather than delaying the user.
- For SessionStart, parallelize `manage-lifecycle.sh` and `inject-context.sh` if possible, or merge them into a single script to avoid double shell startup overhead.

**Warning signs:**
- Users report "laggy" Claude Code experience after installing the plugin
- Hook execution times trending upward over the course of a session
- session-log.json exceeds 1MB during a single session
- Users uninstall the plugin citing performance

**Phase to address:**
Phase 1 (Plugin Skeleton) -- choose JSONL over JSON for session-log from the start. Phase 2 (Observation) -- add timing instrumentation to all hook scripts.

**Severity:** CRITICAL
**Likelihood:** MEDIUM-HIGH -- JSON array append is O(n) and will degrade predictably as sessions get longer

---

### Pitfall 6: CLAUDE.md Marker Section Corruption

**What goes wrong:**
The `<!-- auto-context:start -->` and `<!-- auto-context:end -->` markers get corrupted, moved, duplicated, or deleted. This happens when:
- The user manually edits CLAUDE.md and accidentally modifies or removes markers
- Claude itself edits CLAUDE.md during a session (Claude can and does modify CLAUDE.md)
- Git merge conflicts split the markers across conflict markers
- Another tool or plugin also uses HTML comment markers

If markers are corrupted, the injection script either: (a) fails silently and stops updating, (b) writes auto-content outside the markers (polluting user content), or (c) creates duplicate sections.

**Why it happens:**
HTML comments in markdown are fragile delimiters. They are invisible in rendered markdown, so users do not know they exist. Git merge conflicts treat them as regular text. Claude's own Edit tool may modify them during a session if it decides to "improve" the CLAUDE.md file.

**How to avoid:**
- Validate marker integrity in `inject-context.sh` before every write. If markers are missing or malformed, recreate them at the end of the file and log a warning.
- Use a separate file (e.g., `.auto-context/CLAUDE-AUTO.md`) as the source of truth and only inject into CLAUDE.md as a derived output. If CLAUDE.md markers break, regenerate from source.
- Add a PreToolUse hook that blocks Claude from editing CLAUDE.md auto-context sections (match on Edit/Write tool with CLAUDE.md path, check if target overlaps marker region).
- Add `.auto-context/` section markers to `.gitattributes` merge strategy if possible.
- Consider using a unique, unlikely-to-collide marker format: `<!-- auto-context:v1:sha256:abc123 -->` with a hash of the content for integrity verification.

**Warning signs:**
- Auto-context section disappears after a git merge
- Duplicate auto-context sections appear in CLAUDE.md
- User-written content appears inside the auto-context markers
- `inject-context.sh` silently stops working (no updates to CLAUDE.md)

**Phase to address:**
Phase 1 (Plugin Skeleton) -- marker validation must be built into the injection script from the start. The integrity check is not optional.

**Severity:** CRITICAL
**Likelihood:** MEDIUM -- will happen eventually, especially in teams using git

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| JSON arrays for session-log instead of JSONL | Simpler to read/debug | O(n) append, performance degrades every session | Never -- use JSONL from day one |
| Auto-promote conventions without user review | Faster learning, less user friction | False conventions entrench, context poisoning | Only after false positive rate is measured below 5% (likely Phase 4+) |
| Single CLAUDE.md injection (all conventions at once) | Simple implementation | Token budget overruns, context rot | Phase 1 MVP only -- must move to prioritized/on-demand injection by Phase 3 |
| Hardcoded feedback patterns ("remember this", "don't do this") | Quick implementation | Misses non-English users, paraphrase variants, indirect feedback | Phase 2 only -- must move to LLM-based intent detection by Phase 3 |
| Using `jq` for all JSON manipulation | Zero dependencies, POSIX compatible | jq is slow for complex transformations on large files, error messages are cryptic | Acceptable for < 1MB files; consider Node.js script for batch analysis in Phase 4 |
| Storing all observations forever | Complete history for analysis | Storage bloat, slow queries | Phase 2 only -- must implement observation rotation/compaction by Phase 3 |

## Integration Gotchas

Common mistakes when integrating with Claude Code's plugin system.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Claude Code hooks | Assuming hook events fire in a guaranteed order | Design each hook to be idempotent and order-independent; validate state before acting |
| CLAUDE.md modification | Modifying CLAUDE.md while Claude is mid-session (causes context desync) | Only modify CLAUDE.md at SessionStart; mid-session changes require compact/restart to take effect |
| Plugin environment variables | Assuming `CLAUDE_PROJECT_DIR` always points to git root | Verify path exists; handle monorepos where project dir may be a subdirectory |
| Hook stdin JSON | Assuming all fields are present in stdin JSON | Always use `jq -r '.field // ""'` (default to empty) -- Claude Code may add/remove fields between versions |
| SessionEnd agent handler | Running expensive analysis that blocks session cleanup | Set reasonable timeouts; the user may force-quit before SessionEnd completes |
| Git operations in hooks | Running `git` commands in hooks that conflict with user's git operations | Never write to the git working tree from hooks; use `.auto-context/` exclusively |

## Performance Traps

Patterns that work at small scale but fail as sessions grow.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| session-log.json as JSON array | Append time increases linearly per tool use | Use JSONL (JSON Lines) format for append-only logs | After ~500 tool uses per session (~5MB) |
| Loading entire conventions.json to inject one section | Injection time grows with convention count | Index conventions by category; load only relevant subset | After ~200 conventions |
| Running jq on every PostToolUse event | 50-200 jq invocations per session, each forking a process | Buffer observations in memory (shell variables) and flush periodically | After ~100 tool uses if disk is slow |
| Unbounded observations.json | Observation history grows monotonically | Implement rolling window (keep last N sessions of observations) | After ~50 sessions (~10MB) |
| Regex-based feedback detection | Scanning user prompt with multiple regex patterns | Pre-compile patterns; exit early on first match; keep pattern count under 10 | With 20+ patterns or very long user prompts |

## Security Mistakes

Domain-specific security issues for a context engineering plugin.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Storing code snippets in observations.json | Leaks proprietary code if `.auto-context/` is committed to public repo | Store only pattern descriptions, never raw code. Add `.auto-context/` to `.gitignore` template. |
| Logging user prompts in session-log | Contains sensitive instructions, API keys, passwords typed in prompts | Scrub/hash sensitive patterns before logging; or store only tool-use metadata, not prompt text |
| Shell injection via hook stdin | Malicious JSON in hook input could escape jq and execute arbitrary commands | Always pipe stdin through jq first; never use `eval` on stdin data; quote all variables |
| CLAUDE.md injection of malicious instructions | A compromised conventions.json could inject prompt injection into CLAUDE.md | Sanitize convention text before injection; block known prompt injection patterns (system prompt overrides, role-play instructions) |
| Exposing reward signals | Reward data could reveal user behavior patterns to third parties | Keep all data local; never transmit `.auto-context/` data externally |

## UX Pitfalls

Common user experience mistakes in context engineering automation.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Silent operation with no feedback | User does not know if plugin is working, broken, or doing nothing | Show a brief status line at session start: "Auto-Context: 12 conventions active, 3 candidates pending review" |
| Requiring too much manual review | User fatigue leads to rubber-stamping or disabling the plugin | Batch reviews: show candidates only when 3+ are pending; provide one-key approve/reject |
| Changing CLAUDE.md without notification | User confused when Claude behavior changes unexpectedly | Always log what changed and why: "Added convention: use async/await (observed 5x across 3 sessions)" |
| Overwhelming initial scan (ac-init) | First experience takes too long, produces too much output | Limit initial scan to 5-10 highest-confidence findings; show "discovered X patterns, showing top 5" |
| No escape hatch | User stuck with bad conventions and no clear way to fix | `/ac-reset` must be prominently documented; individual convention removal must be one command |
| Jargon-heavy status output | Non-power-users confused by "observations", "candidates", "conventions", "decay" | Use plain language: "patterns detected", "suggestions for review", "active rules", "expired rules" |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Convention detection:** Often missing cross-session validation -- verify that Candidate promotion requires observations from 2+ independent sessions
- [ ] **CLAUDE.md injection:** Often missing token budget enforcement -- verify that auto-section never exceeds the configured token limit
- [ ] **Marker sections:** Often missing corruption recovery -- verify that inject-context.sh handles missing/duplicate/malformed markers gracefully
- [ ] **Reward signals:** Often missing signal quality metrics -- verify that `/ac-status` shows signal source breakdown (explicit vs implicit, positive vs negative)
- [ ] **Hook performance:** Often missing timing instrumentation -- verify that every hook script logs its execution time for monitoring
- [ ] **Session-log cleanup:** Often missing rotation -- verify that session-log is cleared or archived at SessionEnd, not accumulated forever
- [ ] **Privacy:** Often missing `.gitignore` entry -- verify that `.auto-context/` is added to `.gitignore` during `/ac-init`
- [ ] **Plugin validation:** Often missing edge cases -- verify `claude plugin validate .` passes AND that hooks work when `.auto-context/` directory does not yet exist (first run)
- [ ] **Feedback detection:** Often missing non-English support -- verify that feedback patterns work for the user's language or fall back gracefully
- [ ] **Decay mechanism:** Often missing actual deletion -- verify that decayed conventions are actually removed from CLAUDE.md, not just marked internally

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Context rot (too many conventions) | LOW | Run `/ac-reset` to clear auto-section, then `/ac-init` to re-bootstrap with token budget enforced |
| False convention entrenched | LOW-MEDIUM | Use `/ac-review` to identify and reject false conventions; if widespread, `/ac-reset` and rebuild |
| Reward signal corruption | MEDIUM | Clear `rewards.json`; reset all convention confidence scores to baseline; re-observe for 5+ sessions |
| CLAUDE.md marker corruption | LOW | Delete corrupted markers manually; `inject-context.sh` should auto-recreate on next SessionStart |
| Performance degradation | LOW | Clear `session-log.jsonl`; check file sizes in `.auto-context/`; rotate large files |
| Context poisoning (cascading false conventions) | HIGH | `/ac-reset` is the only safe recovery; all conventions must be re-learned from scratch |
| Plugin breaks after Claude Code update | MEDIUM | Pin to known-compatible Claude Code version; check hooks.json schema against latest plugin spec |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Context rot | Phase 1 (Plugin Skeleton) | Token budget enforced in inject-context.sh; auto-section stays under 1000 tokens in testing |
| Convention false positives | Phase 2 (Observation) | Cross-session requirement in context-extractor; measured false positive rate via `/ac-review` rejection rate |
| Reward signal misattribution | Phase 3 (Learning) | Multiple signal sources implemented; explicit feedback weighted 10x over implicit |
| Context poisoning | Phase 3 (Learning) | Mandatory user review gate active; confidence decay floor implemented |
| Hook performance | Phase 1 (Plugin Skeleton) | JSONL format for session-log; all hooks complete under 100ms measured; timing logged |
| CLAUDE.md marker corruption | Phase 1 (Plugin Skeleton) | Marker validation and auto-recovery in inject-context.sh; tested with corrupted/missing markers |
| Shell injection | Phase 1 (Plugin Skeleton) | All stdin routed through jq; no eval usage; shellcheck passes on all scripts |
| Documentation drift in conventions | Phase 3 (Learning) | Periodic re-validation cycle implemented; conventions expire without refresh |
| User experience opacity | Phase 2 (Observation) | Session-start status message; change logging; plain-language output |
| Storage bloat | Phase 3 (Learning) | Observation rotation implemented; file size monitoring in `/ac-status` |

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Phase 1: Plugin Skeleton | CLAUDE.md injection without token budget | Enforce token budget from first implementation; never ship injection without a hard limit |
| Phase 1: Plugin Skeleton | JSON array session-log | Use JSONL from the start; do not plan to "migrate later" |
| Phase 2: Observation | Context-extractor agent hallucinating conventions | Require the agent to cite specific file:line evidence for each detected pattern |
| Phase 2: Observation | `detect-feedback.sh` too aggressive (false positive on normal conversation) | Start with very narrow patterns; err on the side of missing feedback rather than false-detecting it |
| Phase 3: Learning | Reward signal driving wrong lifecycle decisions | Ship explicit-feedback-only lifecycle first; add implicit signals only after measuring explicit signal quality |
| Phase 3: Learning | Auto-promotion without validation | Keep mandatory user review gate; auto-promotion is Phase 4+ only |
| Phase 4: Intelligence | Smart injection becomes over-engineering | Set a complexity budget; if the injection logic is more complex than the conventions themselves, simplify |
| Phase 4: Distribution | Users with existing CLAUDE.md experience data loss | Test extensively with real-world CLAUDE.md files; backup user content before first injection |

## Sources

- [Chroma Research: Context Rot](https://research.trychroma.com/context-rot) -- LLM performance degradation with increasing context (MEDIUM confidence)
- [Anthropic: Effective Context Engineering for AI Agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) -- Official guidance on context engineering (HIGH confidence)
- [Claude Code Best Practices](https://code.claude.com/docs/en/best-practices) -- Official CLAUDE.md guidance (HIGH confidence)
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) -- Hook types and performance characteristics (HIGH confidence)
- [METR: Recent Frontier Models Are Reward Hacking](https://metr.org/blog/2025-06-05-recent-reward-hacking/) -- Reward proxy optimization failures (MEDIUM confidence)
- [Martin Fowler: Context Engineering for Coding Agents](https://martinfowler.com/articles/exploring-gen-ai/context-engineering-coding-agents.html) -- Patterns and anti-patterns (MEDIUM confidence)
- [CodeAnt: False Positives in AI Code Review](https://www.codeant.ai/blogs/ai-code-review-false-positives) -- False positive rate benchmarks (MEDIUM confidence)
- [DeepSource: Ensuring Less Than 5% False Positive Rate](https://deepsource.com/blog/how-deepsource-ensures-less-false-positives) -- False positive mitigation techniques (MEDIUM confidence)
- [Peter Steinberger: Just Talk To It](https://steipete.me/posts/just-talk-to-it) -- Hand-crafted context engineering approach (MEDIUM confidence)
- [ICLR 2025: Strong Model Collapse](https://proceedings.iclr.cc/paper_files/paper/2025/file/284afdc2309f9667d2d4fb9290235b0c-Paper-Conference.pdf) -- Feedback loop degradation in recursive training (MEDIUM confidence)
- [The New Stack: Context is AI Coding's Real Bottleneck in 2026](https://thenewstack.io/context-is-ai-codings-real-bottleneck-in-2026/) -- Current state of context challenges (LOW-MEDIUM confidence)
- [Qodo: State of AI Code Quality 2025](https://www.qodo.ai/reports/state-of-ai-code-quality/) -- Missing context as top developer issue (MEDIUM confidence)
- [Documentation Drift](https://gaudion.dev/blog/documentation-drift) -- Automated documentation staleness patterns (MEDIUM confidence)

---
*Pitfalls research for: Context Engineering Automation (Auto-CLAUDE.md Generation)*
*Researched: 2026-02-24*
