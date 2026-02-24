# Phase 5: Pattern Extraction - Research

**Researched:** 2026-02-25
**Domain:** Claude Code Stop hook with agent handler, LLM-driven pattern extraction from JSONL session logs, pattern classification taxonomy, evidence citation
**Confidence:** HIGH

## Summary

Phase 5 adds the intelligence layer to auto-context: when Claude finishes responding, a Stop hook with an agent handler analyzes the session log (`session-log.jsonl`) and extracts coding patterns with cited evidence. The agent classifies each pattern as intentional, incidental, framework-imposed, or uncertain, and only intentional patterns are promoted to candidate status in `candidates.json`.

The architecture is straightforward. Claude Code's Stop hook supports all three handler types: command, prompt, and agent. An agent hook (`type: "agent"`) spawns a subagent with access to Read, Grep, and Glob tools, allowing it to inspect the session log, read actual source files for evidence, and return a structured decision. The agent hook receives the Stop event JSON input on stdin (which includes `session_id`, `cwd`, `transcript_path`, and `last_assistant_message`), processes the session log, and returns `{ "ok": true }` to allow Claude to stop normally. The pattern extraction is a side effect -- the agent writes candidate patterns to `candidates.json` before returning its decision.

The critical design challenge is the Stop-vs-SessionEnd race condition documented in Phase 3 research. Stop fires when Claude finishes responding (inside the agentic loop). SessionEnd fires when the session terminates. The current `cleanup-session.sh` (SessionEnd handler) truncates session-log.jsonl. Since Stop fires first and the agent hook blocks until completion (synchronous by default, up to 60s timeout), the extraction agent will have full access to the session log. However, the Stop hook fires on **every** Claude response, not just at session end. The agent must be efficient and should check `stop_hook_active` to prevent infinite loops.

**Primary recommendation:** Register a Stop hook with `type: "agent"` in `hooks/hooks.json`. The agent prompt instructs the subagent to: (1) read `.auto-context/session-log.jsonl`, (2) identify patterns from file modifications and command executions, (3) read the actual files for evidence, (4) classify each pattern, (5) write intentional patterns to `.auto-context/candidates.json`, and (6) return `{ "ok": true }`. Use a command hook wrapper script that first checks if the session log has enough data to warrant extraction (minimum threshold), then delegates to the agent hook -- or alternatively, put the minimum-check logic in the agent prompt itself and accept the small LLM cost for short sessions.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| EXTR-01 | Stop hook agent handler analyzes session log for coding patterns, naming conventions, file structure patterns | Stop hook supports `type: "agent"` handlers. Agent subagent has access to Read, Grep, Glob tools. Session log contains file_write, file_edit, bash_command, explicit_feedback events with file paths and commands. Agent reads session-log.jsonl, identifies patterns from file paths (naming conventions, structure), file contents (coding patterns), and command patterns. |
| EXTR-02 | Extraction agent classifies patterns as intentional/incidental/framework-imposed/uncertain | Agent prompt includes classification taxonomy with definitions and examples for each category. Intentional: consistent deliberate choices across files. Incidental: one-off or random. Framework-imposed: dictated by framework requirements (e.g., Next.js `app/` directory). Uncertain: insufficient evidence. Classification is part of the structured output the agent produces. |
| EXTR-03 | Only intentional patterns promoted to candidates (framework-imposed excluded) | Agent prompt explicitly instructs: only write patterns classified as "intentional" to candidates.json. Framework-imposed, incidental, and uncertain patterns are logged but not promoted. The writing logic in the agent filters on classification before persisting. |
| EXTR-04 | Extraction agent cites specific file:line evidence for each detected pattern | Agent uses Read and Grep tools to inspect actual source files referenced in the session log. Each candidate pattern includes an `evidence` array with `{file, line, snippet}` entries. The agent prompt requires minimum 2 evidence citations per pattern. |
</phase_requirements>

## Standard Stack

### Core

| Library/Tool | Version | Purpose | Why Standard |
|-------------|---------|---------|--------------|
| Claude Code agent hook | Current | Stop hook with `type: "agent"` spawns subagent for pattern analysis | Official hook type; has Read/Grep/Glob tool access; up to 50 turns; perfect for multi-file inspection |
| Bash | 3.2+ (macOS) / 5.x (Linux) | Optional command hook wrapper for pre-check before agent | Consistent with Phases 1-4; fast pre-check avoids unnecessary LLM calls |
| jq | 1.6+ | JSON manipulation for candidates.json merging (in wrapper script if needed) | Already required by Phases 1-4; handles atomic JSON file updates |

### Supporting

| Library/Tool | Version | Purpose | When to Use |
|-------------|---------|---------|-------------|
| date | POSIX | ISO 8601 timestamps for candidate entries | Every candidate entry needs created_at timestamp |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|-----------|-----------|----------|
| Agent hook (`type: "agent"`) | Prompt hook (`type: "prompt"`) | Prompt hook is single-turn, cannot read files or inspect codebase. Agent hook can use Read/Grep/Glob for evidence gathering. Agent is required for EXTR-04 (file:line citations). |
| Agent hook for extraction | Command hook calling external script | Command hook could parse the session log with jq/awk, but cannot do LLM reasoning for pattern classification (EXTR-02). The intelligence requires an LLM. |
| Stop hook | SessionEnd hook | SessionEnd only supports `type: "command"` -- no agent or prompt hooks. Stop supports all three types. This is a locked architectural decision from the roadmap. |
| Agent hook directly on Stop | Command hook wrapper + agent hook | A command wrapper could pre-check session log size and skip extraction for trivially small sessions (< 5 entries). Saves LLM cost. But adds complexity. Recommend starting with agent-only and optimizing later if cost is a concern. |

**Installation:**
```bash
# No new dependencies -- agent hooks are built into Claude Code
# jq already required by Phases 1-4
```

## Architecture Patterns

### Recommended Project Structure (Phase 5 additions)

```
auto-context/
├── hooks/
│   └── hooks.json                    # ADD: Stop agent hook entry
├── scripts/
│   ├── inject-context.sh             # EXISTING (Phase 1)
│   ├── observe-tool.sh               # EXISTING (Phase 3)
│   ├── cleanup-session.sh            # MODIFY: archive session log before truncating
│   ├── detect-feedback.sh            # EXISTING (Phase 4)
│   └── lib/
│       ├── markers.sh                # EXISTING (Phase 1)
│       └── tokens.sh                 # EXISTING (Phase 1)
├── agents/
│   └── extract-patterns.md           # NEW: Agent prompt file for pattern extraction
└── ...
```

### Pattern 1: Stop Hook with Agent Handler

**What:** A Stop hook with `type: "agent"` that spawns a subagent to analyze the session log and extract coding patterns.
**When to use:** Every time Claude finishes responding (Stop event fires).
**Configuration:**

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/pre-extract-check.sh"
          }
        ]
      }
    ]
  }
}
```

**Alternative (agent-only, simpler):**

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "agent",
            "prompt": "... extraction prompt referencing $ARGUMENTS ...",
            "timeout": 120
          }
        ]
      }
    ]
  }
}
```

**Key constraint:** The Stop hook fires on EVERY Claude response, not just session end. The agent prompt MUST include logic to skip extraction when: (a) `stop_hook_active` is true (prevent infinite loops), or (b) the session log has insufficient data. The agent returns `{ "ok": true }` in all cases -- it should never block Claude from stopping.

### Pattern 2: Two-Phase Architecture (Command Wrapper + Agent)

**What:** A command hook performs a fast pre-check, and only invokes the heavyweight agent when warranted.
**When to use:** When LLM cost optimization matters. The command hook checks session log size (< 5 meaningful entries = skip) and the `stop_hook_active` field before the agent runs.
**Recommended approach for this project.**

Phase A (command hook `pre-extract-check.sh`):
```bash
#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
CWD=$(echo "$INPUT" | jq -r '.cwd')

# Prevent infinite loops
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

LOG_FILE="${CWD}/.auto-context/session-log.jsonl"

# Skip if session log doesn't exist or is too small
if [ ! -s "$LOG_FILE" ]; then
  exit 0
fi

# Count meaningful events (exclude session_start)
EVENT_COUNT=$(jq -r 'select(.event != "session_start") | .event' "$LOG_FILE" 2>/dev/null | wc -l | tr -d ' ')
if [ "$EVENT_COUNT" -lt 3 ]; then
  exit 0
fi

# Signal that extraction should proceed (exit 0 allows Claude to stop)
# The actual extraction happens in a separate agent hook that also fires on Stop
exit 0
```

Phase B (agent hook): fires in parallel on the same Stop event, performs extraction.

**However**, there is a simpler approach: use a SINGLE agent hook whose prompt includes instructions to check for sufficient data and skip gracefully. This avoids the complexity of coordinating two hooks. The LLM cost of checking "is there enough data?" is minimal compared to the full extraction.

### Pattern 3: Agent Prompt for Pattern Extraction

**What:** The prompt that drives the extraction subagent. This is the core intelligence of Phase 5.
**When to use:** Embedded in the agent hook configuration or referenced as a file.

The prompt must instruct the agent to:

1. **Read the session log** at `.auto-context/session-log.jsonl`
2. **Identify patterns** from:
   - File paths (naming conventions, directory structure)
   - File modifications (coding patterns, import style, error handling)
   - Bash commands (build/test/lint conventions)
   - Explicit feedback events (already captured, but reinforce)
3. **Read actual source files** for evidence using Read tool
4. **Classify each pattern** as intentional / incidental / framework-imposed / uncertain
5. **Cite evidence** with file:line references
6. **Write candidates** to `.auto-context/candidates.json` (only intentional patterns)
7. **Return** `{ "ok": true }` to allow Claude to stop

The prompt must include:
- Classification taxonomy with clear definitions
- Examples of each classification category
- Minimum evidence threshold (2+ citations per pattern)
- Instructions to skip if session log is empty or has < 3 events
- Instructions to skip if `stop_hook_active` is true (from $ARGUMENTS)
- Deduplication: do not add candidates that already exist

### Pattern 4: Candidate JSON Schema

**What:** The structure of entries in `candidates.json` produced by the extraction agent.
**When to use:** When writing extracted patterns to the candidate store.

```json
[
  {
    "text": "Uses camelCase for function names and PascalCase for React components",
    "classification": "intentional",
    "confidence": 0.3,
    "source": "extraction",
    "created_at": "2026-02-25T14:30:00Z",
    "session_id": "abc123",
    "observations": 1,
    "sessions_seen": ["abc123"],
    "evidence": [
      {
        "file": "src/utils/formatDate.ts",
        "line": 5,
        "snippet": "export function formatDate(date: Date): string {"
      },
      {
        "file": "src/components/UserProfile.tsx",
        "line": 12,
        "snippet": "export const UserProfile: React.FC<Props> = ({ user }) => {"
      }
    ]
  }
]
```

Key fields:
- `classification`: "intentional" (only these get stored)
- `confidence`: starts at 0.3 for single-session extraction (low; needs multi-session confirmation per Phase 6 LIFE-02)
- `source`: "extraction" (distinguishes from "explicit" and "bootstrap")
- `observations`: count of times this pattern was observed (starts at 1)
- `sessions_seen`: array of session_ids where pattern was observed (for LIFE-02 cross-session requirement)
- `evidence`: array of file:line citations (for EXTR-04)

### Pattern 5: Session Log Archive Before Cleanup

**What:** Modify `cleanup-session.sh` to archive the session log before truncating, so that if extraction hasn't completed, the data isn't lost.
**When to use:** SessionEnd handler modification.

```bash
#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd')

LOG_FILE="${CWD}/.auto-context/session-log.jsonl"

if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
  # Archive before truncating (Phase 5 extraction may still need this)
  cp "$LOG_FILE" "${LOG_FILE}.prev" 2>/dev/null || true
  : > "$LOG_FILE"
fi

exit 0
```

**Note:** This archive is a safety net. In the normal flow, the Stop agent hook completes before SessionEnd fires (Stop is in the agentic loop, SessionEnd is on session termination). The `.prev` file can be cleaned up by the next SessionStart.

### Anti-Patterns to Avoid

- **Blocking Claude from stopping:** The extraction agent must ALWAYS return `{ "ok": true }`. Never return `{ "ok": false }` -- pattern extraction is a background concern, not a quality gate. Blocking would force Claude to keep working when the user expects it to stop.
- **Running extraction on every Stop event without checks:** Stop fires after EVERY Claude response, not just at session end. Without a minimum-data threshold check, the agent would fire dozens of times per session on trivially small logs.
- **Infinite Stop hook loops:** If `stop_hook_active` is not checked, the extraction agent's own tool usage could trigger another Stop event, causing an infinite loop. The `stop_hook_active` field exists specifically to prevent this.
- **Writing framework-imposed patterns as candidates:** Patterns like "uses Next.js app/ directory" or "uses React hooks" are framework requirements, not team conventions. The classification step must filter these out (EXTR-03).
- **Modifying conventions.json directly:** The extraction agent writes to `candidates.json`, NOT `conventions.json`. Promotion from candidate to convention happens in Phase 6 (Convention Lifecycle) with mandatory user review. This separation is a core architectural decision.
- **Storing evidence without file:line specificity:** Vague evidence like "observed in src/" is insufficient. EXTR-04 requires specific file:line citations. The agent must use Read or Grep to find exact line numbers.
- **Putting the entire extraction prompt inline in hooks.json:** Long prompts in JSON are fragile and hard to maintain. Use a separate markdown file referenced by the command wrapper, or keep the agent prompt concise with clear instructions.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Pattern classification | Custom heuristic rules for classifying patterns | LLM agent with classification taxonomy in prompt | Pattern classification requires semantic understanding (is this convention intentional or framework-imposed?); LLM reasoning handles edge cases better than regex rules |
| File content inspection for evidence | jq/awk parsing of source files | Agent's built-in Read and Grep tools | The agent subagent has Read, Grep, Glob tools that handle all file types, character encodings, and edge cases |
| Session log parsing | Custom JSONL parser | jq for structured extraction (in command wrapper) or agent's Read tool | jq handles malformed lines gracefully; the agent can read JSONL files directly |
| Deduplication of candidate patterns | String-exact matching of pattern text | Semantic comparison in the agent prompt | Two patterns may describe the same convention in different words; LLM can detect semantic duplicates |
| JSON file atomic updates | Manual string manipulation | jq for merge + mv for atomic write | jq handles JSON escaping, array merging, and validation; mv provides atomic file replacement |

**Key insight:** Phase 5 is the first phase where the LLM does the heavy lifting (not just shell scripts). The agent hook is the right tool because pattern extraction requires judgment, classification, and evidence gathering -- tasks that shells cannot do. The shell wrapper handles only the fast-path optimization (skip extraction for trivial sessions).

## Common Pitfalls

### Pitfall 1: Infinite Stop Hook Loop

**What goes wrong:** The extraction agent uses Read/Grep tools, which trigger PostToolUse events. When the agent finishes, another Stop event fires, spawning another extraction agent, ad infinitum.
**Why it happens:** Agent hooks on Stop fire whenever Claude (or a subagent acting on behalf of Claude) finishes responding. If the agent's own completion triggers another Stop, the loop begins.
**How to avoid:** Check `stop_hook_active` in the hook input ($ARGUMENTS). When `stop_hook_active` is `true`, return `{ "ok": true }` immediately without doing any work. The official docs explicitly document this field for exactly this purpose.
**Warning signs:** Claude Code never stops responding; spinning indicator runs indefinitely; session hangs.

### Pitfall 2: Stop Hook Firing Too Often

**What goes wrong:** The extraction agent runs after every single Claude response, even trivial ones like "I've read the file" where the session log has 1-2 entries.
**Why it happens:** Stop fires on EVERY Claude response, not just at the end of a complex task.
**How to avoid:** Implement a minimum-data threshold. If session-log.jsonl has fewer than 3 meaningful events (excluding session_start), skip extraction entirely. This can be done in a command hook pre-check or in the agent prompt itself (instruct the agent to check log size first).
**Warning signs:** High LLM cost; noisy candidates from trivial sessions; slow response times.

### Pitfall 3: Race Condition with SessionEnd Cleanup

**What goes wrong:** The SessionEnd handler truncates session-log.jsonl before the Stop agent hook finishes reading it.
**Why it happens:** If a user exits immediately after Claude's last response, SessionEnd could fire while the Stop agent is still processing.
**How to avoid:** The Stop hook is synchronous and blocks Claude's response completion until it returns. SessionEnd fires after the session terminates (user exits). Since Stop blocks until done, the agent should complete before SessionEnd fires in the normal case. As a safety net, archive the session log to `.prev` in cleanup-session.sh before truncating.
**Warning signs:** Extraction agent finds empty session log; candidates.json never gets new entries.

### Pitfall 4: Framework-Imposed Patterns Leaking Through

**What goes wrong:** Candidates.json fills with obvious framework patterns ("uses package.json for dependencies", "uses tsconfig.json for TypeScript config") that provide zero value.
**Why it happens:** The agent detects patterns without distinguishing between team choices and framework requirements.
**How to avoid:** The classification taxonomy in the agent prompt must clearly define "framework-imposed" with examples: any pattern that is required by the framework/tool being used, not a team choice. The agent should have concrete examples: `app/` directory in Next.js = framework-imposed; camelCase function naming = intentional choice. Also include a "negative examples" section in the prompt.
**Warning signs:** Candidates list dominated by obvious/trivial patterns; user sees no value in extracted patterns.

### Pitfall 5: Agent Prompt Too Long for hooks.json

**What goes wrong:** The agent prompt for extraction is 2000+ characters, making hooks.json unreadable and fragile.
**Why it happens:** The extraction task requires detailed instructions (taxonomy, examples, output format, file paths, deduplication logic).
**How to avoid:** Two options: (1) Use a command hook wrapper that constructs the agent invocation, passing the prompt from a separate file. (2) Keep the prompt in hooks.json but make it concise, moving detailed classification examples to a separate file that the agent reads as its first step (e.g., `agents/extract-patterns.md`). Option 2 is recommended for plugin distribution -- the agent reads its detailed instructions from a bundled file.
**Warning signs:** hooks.json becomes a wall of escaped text; prompt changes require careful JSON escaping.

### Pitfall 6: Duplicate Candidates Across Sessions

**What goes wrong:** The same pattern is added to candidates.json multiple times across different sessions, inflating observation counts incorrectly.
**Why it happens:** The extraction agent does not check for existing candidates before writing.
**How to avoid:** The agent prompt must include deduplication instructions: read existing candidates.json, check for semantic duplicates (same pattern described differently), and increment `observations` / append to `sessions_seen` for existing candidates rather than adding new entries. The agent's LLM reasoning can handle semantic deduplication better than exact string matching.
**Warning signs:** candidates.json has near-duplicate entries; observation counts are lower than expected because they're split across duplicates.

## Code Examples

Verified patterns from official sources:

### Stop Hook Input Schema

```json
// Source: https://code.claude.com/docs/en/hooks (Stop input)
{
  "session_id": "abc123",
  "transcript_path": "~/.claude/projects/.../00893aaf.jsonl",
  "cwd": "/Users/user/my-project",
  "permission_mode": "default",
  "hook_event_name": "Stop",
  "stop_hook_active": false,
  "last_assistant_message": "I've completed the refactoring. Here's a summary..."
}
```

### Agent Hook Configuration in hooks.json

```json
// Source: https://code.claude.com/docs/en/hooks (Agent-based hooks)
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "agent",
            "prompt": "Your extraction prompt here. Hook input: $ARGUMENTS",
            "timeout": 120
          }
        ]
      }
    ]
  }
}
```

### Agent Hook Response Schema

```json
// Source: https://code.claude.com/docs/en/hooks (Agent-based hooks response)
// Allow Claude to stop (extraction complete or skipped):
{ "ok": true }

// Block Claude from stopping (NEVER use this for extraction):
{ "ok": false, "reason": "explanation" }
```

### JSONL Session Log Entries (Input to Extraction)

```jsonl
{"ts":"2026-02-25T10:30:00Z","event":"session_start","session_id":"abc123","cwd":"/path/to/project"}
{"ts":"2026-02-25T10:30:05Z","event":"file_write","tool":"Write","file":"/path/to/src/utils/formatDate.ts","session_id":"abc123"}
{"ts":"2026-02-25T10:30:10Z","event":"file_edit","tool":"Edit","file":"/path/to/src/components/UserProfile.tsx","session_id":"abc123"}
{"ts":"2026-02-25T10:30:15Z","event":"bash_command","tool":"Bash","command":"npm test","session_id":"abc123"}
{"ts":"2026-02-25T10:30:20Z","event":"explicit_feedback","type":"convention","text":"always use pnpm","session_id":"abc123"}
{"ts":"2026-02-25T10:30:25Z","event":"file_edit","tool":"Edit","file":"/path/to/src/utils/parseUrl.ts","session_id":"abc123"}
```

### Candidate Entry Format

```json
// Output format the extraction agent writes to candidates.json
{
  "text": "Uses camelCase for utility function names",
  "classification": "intentional",
  "confidence": 0.3,
  "source": "extraction",
  "created_at": "2026-02-25T14:30:00Z",
  "session_id": "abc123",
  "observations": 1,
  "sessions_seen": ["abc123"],
  "evidence": [
    {
      "file": "src/utils/formatDate.ts",
      "line": 5,
      "snippet": "export function formatDate(date: Date): string {"
    },
    {
      "file": "src/utils/parseUrl.ts",
      "line": 3,
      "snippet": "export function parseUrl(raw: string): URL {"
    }
  ]
}
```

### hooks.json After Phase 5

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/inject-context.sh"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/detect-feedback.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/observe-tool.sh"
          }
        ]
      }
    ],
    "PostToolUseFailure": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/observe-tool.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/pre-extract-check.sh"
          },
          {
            "type": "agent",
            "prompt": "You are the auto-context pattern extraction agent. Read the instructions at ${CLAUDE_PLUGIN_ROOT}/agents/extract-patterns.md, then analyze the session log and extract coding patterns. Hook input: $ARGUMENTS",
            "timeout": 120,
            "statusMessage": "Auto-Context: analyzing session for patterns..."
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-session.sh"
          }
        ]
      }
    ]
  }
}
```

**Important note on hooks.json structure:** The `Stop` event has TWO hooks in the same matcher group. Per official docs, "All matching hooks run in parallel." This means the command hook (pre-extract-check.sh) and the agent hook run in parallel. The command hook performs a fast check and returns immediately. The agent hook performs the actual extraction.

**Alternative (simpler, recommended for v1):** Use only the agent hook with the pre-check logic embedded in the agent prompt itself:

```json
"Stop": [
  {
    "hooks": [
      {
        "type": "agent",
        "prompt": "You are the auto-context pattern extraction agent. First check: if stop_hook_active is true in the input, or if the session log at .auto-context/session-log.jsonl has fewer than 3 non-session_start entries, respond with {\"ok\": true} immediately. Otherwise, read the full instructions at the path shown below and extract patterns.\n\nInstructions file: Use Read tool on agents/extract-patterns.md in the plugin root.\n\nHook input: $ARGUMENTS",
        "timeout": 120,
        "statusMessage": "Auto-Context: analyzing session for patterns..."
      }
    ]
  }
]
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|-------------|-----------------|--------------|--------|
| SessionEnd agent hook for extraction | Stop agent hook for extraction | Discovered during roadmap creation | SessionEnd only supports `type: "command"` hooks. Stop supports all three types including agent. |
| Command hook for all hooks | Agent hook for pattern extraction | Phase 5 (first phase to use agent hooks) | Previous phases used command hooks exclusively. Phase 5 is the first to leverage LLM reasoning via agent hook. |
| Inline agent prompt in hooks.json | Agent reads instructions from bundled .md file | Best practice for long prompts | Keeps hooks.json clean; prompt changes don't require JSON escaping; .md file is version-controlled separately. |
| Single hook per Stop event | Pre-check command + agent hook (or agent-only with embedded check) | Optimization for LLM cost | Avoids unnecessary LLM invocations for trivial sessions. |

**Deprecated/outdated:**
- Using SessionEnd for pattern extraction: SessionEnd does NOT support agent hooks. Stop hook is the correct event.
- Using `type: "prompt"` for extraction: Prompt hooks are single-turn and cannot use Read/Grep/Glob tools. Agent hooks are required for evidence gathering (EXTR-04).

## Open Questions

1. **Should the extraction agent use a specific model, or rely on the default fast model?**
   - What we know: Agent hooks default to a "fast model" (likely Haiku). The `model` field can override this. Pattern extraction and classification may benefit from a more capable model.
   - What's unclear: Whether the default fast model has sufficient reasoning capability for pattern classification and evidence gathering. The extraction task involves semantic understanding (intentional vs. framework-imposed) and code reading.
   - Recommendation: Start with the default model (cheaper, faster). If classification quality is poor (too many false positives in candidates), upgrade to a more capable model via the `model` field. The agent prompt quality matters more than the model choice for this task.

2. **How should the pre-extract-check.sh command hook interact with the agent hook when both fire on Stop?**
   - What we know: All matching hooks in the same matcher group run in parallel. The command hook cannot "cancel" the agent hook.
   - What's unclear: If the command hook returns early (exit 0), does the agent hook still run? Yes -- they run in parallel, not sequentially.
   - Recommendation: Use the simpler single-agent-hook approach with the pre-check logic in the agent prompt. This avoids the parallel execution complexity. The agent can check log size as its first step (one Read call) and return immediately if insufficient data.

3. **What is the right minimum threshold for triggering extraction?**
   - What we know: A session with only 1-2 file edits produces very little pattern signal. A session with 10+ diverse file operations has meaningful patterns.
   - What's unclear: The exact threshold that balances false negative (missing patterns from short sessions) vs. noise (extracting patterns from trivial sessions).
   - Recommendation: Start with 3 meaningful events (file_write, file_edit, bash_command -- excluding session_start). Adjust after observing real-world usage. This is conservative enough to avoid noise but permissive enough to catch patterns from focused sessions.

4. **How should the `$ARGUMENTS` placeholder and `${CLAUDE_PLUGIN_ROOT}` interact in the agent prompt?**
   - What we know: `$ARGUMENTS` is replaced with the hook input JSON. `${CLAUDE_PLUGIN_ROOT}` is an environment variable expanded by the shell when the command runs. For agent hooks, the prompt is sent to the LLM, not executed as a shell command.
   - What's unclear: Whether `${CLAUDE_PLUGIN_ROOT}` is expanded in agent hook prompts. The docs say the placeholder `$ARGUMENTS` is expanded, but environment variables may not be.
   - Recommendation: Test whether `${CLAUDE_PLUGIN_ROOT}` expands in agent prompts. If not, use the `cwd` field from the hook input (available via $ARGUMENTS) to construct the path: `$CWD/.auto-context/` for data files. For the instructions file, either inline the prompt or use a relative path from cwd. **This needs validation during implementation.**

5. **Should candidate confidence start at 0.3 or lower?**
   - What we know: Bootstrap conventions use 0.6-0.9 (source: "bootstrap"). Explicit feedback uses 1.0 (source: "explicit"). Extraction-based candidates need multi-session confirmation before promotion (LIFE-02 requires observations from 2+ independent sessions).
   - What's unclear: The right initial confidence for extraction candidates. Too high = premature promotion risk. Too low = never gets noticed.
   - Recommendation: 0.3 for single-session extraction. This clearly distinguishes from bootstrap (0.6+) and explicit (1.0) sources. Phase 6 will define the promotion threshold. The confidence should increase as more sessions confirm the pattern.

## Sources

### Primary (HIGH confidence)
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) - Complete Stop hook input schema (stop_hook_active, last_assistant_message), agent hook configuration (type: "agent", prompt, model, timeout), response schema (ok: true/false), event support matrix (Stop supports command/prompt/agent), hook handler execution model (parallel within matcher group), common input fields (session_id, transcript_path, cwd), exit code semantics, decision control patterns
- [Claude Code Hooks Guide](https://code.claude.com/docs/en/hooks-guide) - Stop hook infinite loop prevention (stop_hook_active check), agent-based hooks practical usage, prompt-based hooks response format, plugin hooks configuration

### Secondary (MEDIUM confidence)
- Phase 3 Research (`.planning/phases/03-session-observation/03-RESEARCH.md`) - Session log format, JSONL entry schema, Stop-vs-SessionEnd ordering, race condition documentation
- Phase 4 Plan (`.planning/phases/04-explicit-feedback/04-01-PLAN.md`) - Existing hook registration patterns, conventions.json and anti-patterns.json schema, atomic JSON write pattern (jq + tmp + mv)
- Existing codebase (`hooks/hooks.json`, `scripts/*.sh`) - Verified current hook structure, session log format, data store paths, coding patterns used in Phases 1-4

### Tertiary (LOW confidence)
- None. All critical claims verified with official docs.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Agent hooks are officially documented and supported for Stop events. No new dependencies needed.
- Architecture: HIGH - Stop hook with agent handler is the documented approach for multi-file inspection. Pattern classification taxonomy is a prompt engineering task with well-understood techniques. Session log format is established from Phase 3.
- Pitfalls: HIGH - Infinite loop prevention (stop_hook_active) is explicitly documented. Stop-vs-SessionEnd ordering verified from lifecycle documentation. Framework-imposed pattern leakage is a known concern from convention detection literature.
- Code examples: HIGH - Hook configuration, input schema, and response format taken directly from official Claude Code hooks reference.

**Research date:** 2026-02-25
**Valid until:** 2026-03-25 (hook system is stable; 30-day validity appropriate)
