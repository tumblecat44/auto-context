# Phase 3: Session Observation - Research

**Researched:** 2026-02-25
**Domain:** Claude Code PostToolUse hooks, JSONL session logging, session lifecycle (SessionEnd), performance constraints
**Confidence:** HIGH

## Summary

Phase 3 adds real-time session observation to the auto-context plugin. Two hook handlers capture events as Claude works: a PostToolUse command hook logs file modifications (Write/Edit) and Bash command executions to the existing `.auto-context/session-log.jsonl`, and a SessionEnd command hook rotates (clears) the session log at session end. The observation hooks must be invisible to the user -- executing in under 100ms each -- which means they do nothing more than extract fields from the hook's stdin JSON and append a single JSONL line via `echo >> file`.

The Claude Code hooks system is well-documented and stable. PostToolUse hooks receive `tool_name`, `tool_input`, and `tool_response` fields on stdin as JSON. The matcher field supports regex patterns, so `Write|Edit` matches file modification tools and `Bash` matches command execution. Multiple matcher groups can be defined under a single hook event, each with its own handler. SessionEnd hooks receive a `reason` field and cannot block session termination -- they are fire-and-forget, ideal for cleanup operations like log rotation.

Phase 1 already established the JSONL session log file (`.auto-context/session-log.jsonl`), the data store directory initialization, and the `echo >> file` append pattern. Phase 3 extends the existing `hooks/hooks.json` to add PostToolUse and SessionEnd entries alongside the existing SessionStart hook. The observation script follows the same patterns as `inject-context.sh`: read stdin once, extract fields with jq, append structured data, exit 0.

**Primary recommendation:** Create a single `scripts/observe-tool.sh` script that handles both Write/Edit and Bash PostToolUse events (dispatching on `tool_name`), plus a `scripts/cleanup-session.sh` for SessionEnd log rotation. Register both in `hooks/hooks.json` with appropriate matchers.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| OBSV-01 | PostToolUse hook logs file modifications (Write/Edit) to session log in JSONL format | PostToolUse hook with matcher `Write\|Edit` receives `tool_name`, `tool_input.file_path`, `tool_input.content` (Write) or `tool_input.old_string`/`tool_input.new_string` (Edit), and `tool_response`. Extract file path and operation type, append JSONL entry. |
| OBSV-02 | PostToolUse hook logs Bash command executions and errors to session log | PostToolUse hook with matcher `Bash` receives `tool_input.command`, `tool_input.description`, and `tool_response`. PostToolUseFailure with matcher `Bash` receives `error` and `is_interrupt` fields for failed commands. Both append JSONL entries. |
| OBSV-03 | All observation hooks execute < 100ms (no user-perceived latency) | Command hooks are synchronous and block Claude until they complete. The script must do only: read stdin, extract 3-4 fields with jq, format a single JSON line, append to file. No file scanning, no JSON array manipulation, no network calls. A single jq pipe plus echo >> is well under 100ms. |
| OBSV-05 | Session log rotated/cleared at session end (never accumulates across sessions) | SessionEnd command hook receives `reason` field. Script truncates session-log.jsonl (or archives to session-log.prev.jsonl for potential Phase 5 Stop hook extraction that may still be in progress). The SessionEnd event fires for all exit reasons: clear, logout, prompt_input_exit, bypass_permissions_disabled, other. |
</phase_requirements>

## Standard Stack

### Core

| Library/Tool | Version | Purpose | Why Standard |
|-------------|---------|---------|--------------|
| Bash | 3.2+ (macOS) / 5.x (Linux) | PostToolUse and SessionEnd command hook scripts | Consistent with Phase 1; zero dependency; only handler type supported for observation hooks |
| jq | 1.6+ | Extract tool_name, tool_input, tool_response fields from hook stdin JSON | Already required by Phase 1; standard JSON CLI tool; `-c` flag produces compact single-line output for JSONL |

### Supporting

| Library/Tool | Version | Purpose | When to Use |
|-------------|---------|---------|-------------|
| date | POSIX | ISO 8601 timestamps for JSONL entries | Every observation entry needs a timestamp |
| wc / stat | POSIX | Optional: measure session-log.jsonl size for rotation decisions | SessionEnd cleanup if size-based rotation is needed |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|-----------|-----------|----------|
| Single observe-tool.sh for all tools | Separate scripts per tool (observe-write.sh, observe-bash.sh) | Separate scripts avoid tool_name dispatch but add file count; single script is simpler and consistent with architecture docs |
| Synchronous PostToolUse hook | Async PostToolUse hook (`"async": true`) | Async hooks cannot return decision/context to Claude and run in background; sync is needed for reliability but must stay fast. Async would add complexity without benefit since our hook is already <100ms |
| Clearing session-log.jsonl at SessionEnd | Clearing at SessionStart (next session) | SessionEnd is the documented place for cleanup. However, SessionEnd may not fire if the process is killed. SessionStart should also handle stale logs as a safety net. |

**Installation:**
```bash
# No new dependencies -- jq already required by Phase 1
```

## Architecture Patterns

### Recommended Project Structure (Phase 3 additions)

```
auto-context/
├── hooks/
│   └── hooks.json                    # ADD: PostToolUse and SessionEnd entries
├── scripts/
│   ├── inject-context.sh             # EXISTING (Phase 1)
│   ├── observe-tool.sh               # NEW: PostToolUse handler for Write|Edit|Bash
│   ├── cleanup-session.sh            # NEW: SessionEnd handler for log rotation
│   └── lib/
│       ├── markers.sh                # EXISTING (Phase 1)
│       └── tokens.sh                 # EXISTING (Phase 1)
└── ...
```

### Pattern 1: PostToolUse Observation Hook

**What:** A command-type hook that fires after every Write, Edit, or Bash tool execution, extracts key fields, and appends a structured JSONL entry to the session log.
**When to use:** Every file modification or command execution during a Claude Code session.
**Example:**

```bash
# scripts/observe-tool.sh
# Source: https://code.claude.com/docs/en/hooks (PostToolUse input schema)
#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
CWD=$(echo "$INPUT" | jq -r '.cwd')
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

STORE_DIR="${CWD}/.auto-context"
LOG_FILE="${STORE_DIR}/session-log.jsonl"

# Ensure log file exists (safety net if SessionStart didn't run)
[ -d "$STORE_DIR" ] || mkdir -p "$STORE_DIR"
[ -f "$LOG_FILE" ] || touch "$LOG_FILE"

case "$TOOL_NAME" in
  Write)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    echo "{\"ts\":\"${TS}\",\"event\":\"file_write\",\"tool\":\"Write\",\"file\":\"${FILE_PATH}\",\"session_id\":\"${SESSION_ID}\"}" >> "$LOG_FILE"
    ;;
  Edit)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    echo "{\"ts\":\"${TS}\",\"event\":\"file_edit\",\"tool\":\"Edit\",\"file\":\"${FILE_PATH}\",\"session_id\":\"${SESSION_ID}\"}" >> "$LOG_FILE"
    ;;
  Bash)
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
    # Truncate command to prevent log bloat (max 200 chars)
    COMMAND_SHORT="${COMMAND:0:200}"
    echo "$INPUT" | jq -c "{ts:\"${TS}\",event:\"bash_command\",tool:\"Bash\",command:.tool_input.command[0:200],session_id:\"${SESSION_ID}\"}" >> "$LOG_FILE"
    ;;
esac

exit 0
```

### Pattern 2: PostToolUseFailure for Error Logging

**What:** A separate matcher group for PostToolUseFailure that captures Bash command failures with error details.
**When to use:** When a Bash command fails (non-zero exit). This is separate from PostToolUse which only fires on success.
**Example:**

```bash
# In observe-tool.sh, handle PostToolUseFailure input
# Source: https://code.claude.com/docs/en/hooks (PostToolUseFailure input)
# PostToolUseFailure provides: error (string), is_interrupt (boolean)
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name')

if [ "$HOOK_EVENT" = "PostToolUseFailure" ]; then
  ERROR=$(echo "$INPUT" | jq -r '.error // empty')
  ERROR_SHORT="${ERROR:0:200}"
  echo "$INPUT" | jq -c "{ts:\"${TS}\",event:\"bash_error\",tool:\"Bash\",command:.tool_input.command[0:200],error:.error[0:200],session_id:\"${SESSION_ID}\"}" >> "$LOG_FILE"
  exit 0
fi
```

### Pattern 3: SessionEnd Log Rotation

**What:** A command hook on SessionEnd that clears or archives the session log to prevent cross-session accumulation.
**When to use:** Every session end (all reasons).
**Example:**

```bash
# scripts/cleanup-session.sh
# Source: https://code.claude.com/docs/en/hooks (SessionEnd event)
#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd')

STORE_DIR="${CWD}/.auto-context"
LOG_FILE="${STORE_DIR}/session-log.jsonl"

if [ -f "$LOG_FILE" ]; then
  # Truncate the log file (clear contents, keep file)
  : > "$LOG_FILE"
fi

exit 0
```

### Pattern 4: hooks.json Configuration with Multiple Matchers

**What:** Extend the existing hooks.json to register PostToolUse, PostToolUseFailure, and SessionEnd hooks alongside the existing SessionStart hook.
**When to use:** Phase 3 hooks.json update.
**Example:**

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

### Anti-Patterns to Avoid

- **Heavy processing in PostToolUse hooks:** NEVER analyze patterns, merge JSON arrays, or scan files in the observation hook. Append only. All analysis happens later in Phase 5 (Stop agent hook).
- **Storing raw file content in session log:** Do NOT log `tool_input.content` (Write) or `tool_response` contents. Log only the file path and operation type. Content logging would bloat the session log and raise privacy concerns.
- **Storing full Bash output in session log:** Do NOT log `tool_response` for Bash commands. The output can be enormous (test suites, build output). Log only the command string (truncated) and error messages.
- **Using jq to read/modify the session log during observation:** The session log is append-only during observation. Never read it, never parse it, never modify existing entries. Only `echo >> file`.
- **Using async hooks for observation:** Async hooks cannot provide decision control and add complexity. Since our hook is <100ms synchronous, async adds zero benefit but introduces race conditions on the log file.
- **Separate scripts per tool:** A single observe-tool.sh dispatching on tool_name is cleaner than observe-write.sh + observe-edit.sh + observe-bash.sh. Same script, same patterns, fewer files.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON field extraction from stdin | Custom awk/sed parsing | jq -r '.field' | Hook input is complex nested JSON; jq handles edge cases (escaping, null fields) correctly |
| JSONL formatting | Manual string concatenation for all fields | jq -c for complex entries, simple echo for known-safe fields | jq -c ensures valid JSON output with proper escaping; echo is faster for simple fields |
| File locking for concurrent appends | flock wrapper for session-log.jsonl | No locking needed | Claude Code runs hooks sequentially per event; there is no concurrent write risk for a single-session log file |
| Timestamp generation | Custom date formatting logic | `date -u +%Y-%m-%dT%H:%M:%SZ` | POSIX date produces ISO 8601; no need for custom formatting |

**Key insight:** The observation layer is intentionally minimal. Its only job is to produce structured append-only data that Phase 5 (Pattern Extraction) consumes later. Simplicity in the observation layer directly enables the <100ms performance constraint.

## Common Pitfalls

### Pitfall 1: SessionEnd Not Firing on Kill

**What goes wrong:** Session log never gets cleared because the process was killed (SIGKILL/SIGTERM), and SessionEnd hook did not fire.
**Why it happens:** SessionEnd fires for clean exits (clear, logout, prompt exit) but may not fire on hard kills or crashes.
**How to avoid:** Add a safety net in SessionStart (inject-context.sh) or the observation script: if session-log.jsonl has entries with a different session_id than the current session, truncate it before proceeding. This handles stale logs from crashed sessions.
**Warning signs:** Session log grows across sessions; Phase 5 extraction sees events from previous sessions.

### Pitfall 2: jq Spawning Overhead

**What goes wrong:** Multiple jq invocations per hook call add up to >100ms.
**Why it happens:** Each `echo "$INPUT" | jq -r '.field'` spawns a new jq process. On macOS, process spawning has ~5-10ms overhead per call.
**How to avoid:** Extract all needed fields in a single jq invocation: `read -r TOOL SESSION CWD <<< $(echo "$INPUT" | jq -r '[.tool_name, .session_id, .cwd] | @tsv')`. Or use a single jq -c pipeline for the entire entry construction.
**Warning signs:** Hook execution consistently near 50-100ms in `--debug` output.

### Pitfall 3: Command String Escaping in JSONL

**What goes wrong:** Bash commands containing quotes, newlines, or special characters produce invalid JSON in the session log.
**Why it happens:** Using string interpolation (`"command":"${CMD}"`) instead of jq for JSON construction.
**How to avoid:** Use `jq -c` to construct the JSONL entry when the command field comes from user input. jq handles JSON string escaping automatically. For simple known-safe fields (timestamps, tool names), echo interpolation is fine.
**Warning signs:** `jq` errors when reading session-log.jsonl in later phases; lines with unescaped quotes.

### Pitfall 4: Log File Bloat from Verbose Commands

**What goes wrong:** Session log grows to megabytes within a single session because long Bash commands or error messages are logged verbatim.
**Why it happens:** Not truncating the command or error fields before logging.
**How to avoid:** Truncate command strings to 200 characters and error messages to 200 characters. The session log entry should be a summary, not a transcript. Phase 5 can read the actual transcript via `transcript_path` if needed.
**Warning signs:** session-log.jsonl exceeds 100KB for a typical session.

### Pitfall 5: Script Not Executable After Creation

**What goes wrong:** PostToolUse and SessionEnd hooks silently fail; no observations are captured.
**Why it happens:** New scripts created without `chmod +x`.
**How to avoid:** Always `chmod +x scripts/observe-tool.sh scripts/cleanup-session.sh` after creating them. Git tracks the executable bit, so this persists.
**Warning signs:** No entries appearing in session-log.jsonl despite active tool usage.

### Pitfall 6: Stale Session ID in Log After Resume

**What goes wrong:** Resumed sessions write new entries but old entries from the same session_id remain, causing duplicate processing in Phase 5.
**Why it happens:** SessionEnd may have been skipped (crash/kill), and the session log was not cleared. When the same session resumes, it appends to existing entries.
**How to avoid:** The cleanup safety net at SessionStart handles this. Also, Phase 5 extraction should be idempotent and handle duplicate entries gracefully.
**Warning signs:** session-log.jsonl has duplicate session_start entries.

## Code Examples

Verified patterns from official sources:

### PostToolUse Input for Write Tool

```json
// Source: https://code.claude.com/docs/en/hooks (PostToolUse input schema)
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../.claude/projects/.../00893aaf.jsonl",
  "cwd": "/Users/user/my-project",
  "permission_mode": "default",
  "hook_event_name": "PostToolUse",
  "tool_name": "Write",
  "tool_input": {
    "file_path": "/Users/user/my-project/src/app.ts",
    "content": "file content here"
  },
  "tool_response": {
    "filePath": "/Users/user/my-project/src/app.ts",
    "success": true
  },
  "tool_use_id": "toolu_01ABC123..."
}
```

### PostToolUse Input for Edit Tool

```json
// Source: https://code.claude.com/docs/en/hooks (PreToolUse Edit fields apply to PostToolUse)
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../.claude/projects/.../00893aaf.jsonl",
  "cwd": "/Users/user/my-project",
  "permission_mode": "default",
  "hook_event_name": "PostToolUse",
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "/Users/user/my-project/src/app.ts",
    "old_string": "original text",
    "new_string": "replacement text",
    "replace_all": false
  },
  "tool_response": { "success": true },
  "tool_use_id": "toolu_01DEF456..."
}
```

### PostToolUse Input for Bash Tool

```json
// Source: https://code.claude.com/docs/en/hooks (PreToolUse Bash fields apply to PostToolUse)
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../.claude/projects/.../00893aaf.jsonl",
  "cwd": "/Users/user/my-project",
  "permission_mode": "default",
  "hook_event_name": "PostToolUse",
  "tool_name": "Bash",
  "tool_input": {
    "command": "npm test",
    "description": "Run test suite",
    "timeout": 120000
  },
  "tool_response": { "stdout": "...", "stderr": "...", "exitCode": 0 },
  "tool_use_id": "toolu_01GHI789..."
}
```

### PostToolUseFailure Input for Bash Tool

```json
// Source: https://code.claude.com/docs/en/hooks (PostToolUseFailure input)
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../.claude/projects/.../00893aaf.jsonl",
  "cwd": "/Users/user/my-project",
  "permission_mode": "default",
  "hook_event_name": "PostToolUseFailure",
  "tool_name": "Bash",
  "tool_input": {
    "command": "npm test",
    "description": "Run test suite"
  },
  "tool_use_id": "toolu_01ABC123...",
  "error": "Command exited with non-zero status code 1",
  "is_interrupt": false
}
```

### SessionEnd Input

```json
// Source: https://code.claude.com/docs/en/hooks (SessionEnd input)
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../.claude/projects/.../00893aaf.jsonl",
  "cwd": "/Users/user/my-project",
  "permission_mode": "default",
  "hook_event_name": "SessionEnd",
  "reason": "other"
}
```

### JSONL Session Log Entry Format

```jsonl
{"ts":"2026-02-25T10:30:00Z","event":"session_start","session_id":"abc123","cwd":"/path/to/project"}
{"ts":"2026-02-25T10:30:05Z","event":"file_write","tool":"Write","file":"/path/to/src/app.ts","session_id":"abc123"}
{"ts":"2026-02-25T10:30:10Z","event":"file_edit","tool":"Edit","file":"/path/to/src/app.ts","session_id":"abc123"}
{"ts":"2026-02-25T10:30:15Z","event":"bash_command","tool":"Bash","command":"npm test","session_id":"abc123"}
{"ts":"2026-02-25T10:30:20Z","event":"bash_error","tool":"Bash","command":"npm run lint","error":"Command exited with non-zero status code 1","session_id":"abc123"}
```

### Efficient Single-jq Field Extraction

```bash
# Source: bash best practices for performance-sensitive hooks
# Extract multiple fields in one jq invocation to minimize process spawning
eval "$(echo "$INPUT" | jq -r '@sh "TOOL_NAME=\(.tool_name) SESSION_ID=\(.session_id) CWD=\(.cwd)"')"

# Or use read with tab-separated values
IFS=$'\t' read -r TOOL_NAME SESSION_ID CWD <<< "$(echo "$INPUT" | jq -r '[.tool_name, .session_id, .cwd] | @tsv')"
```

### Complete hooks.json After Phase 3

```json
// Source: existing hooks.json + Phase 3 additions
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

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|-------------|-----------------|--------------|--------|
| SessionEnd agent hook for extraction | Stop agent hook for extraction (Phase 5) | Discovered in project architecture research | SessionEnd only supports command hooks; observation stays in PostToolUse command hooks |
| Multiple tool-specific observation scripts | Single observe-tool.sh dispatching on tool_name | Architecture recommendation | Fewer files, consistent patterns, single maintenance point |
| Synchronous JSON array reads for logging | JSONL append-only with `echo >>` | Phase 1 design decision (OBSV-04) | O(1) append vs O(n) read-modify-write; critical for <100ms constraint |
| Full content logging | Metadata-only logging (file path, command truncated) | Architecture research recommendation | Prevents log bloat and privacy concerns; Phase 5 can access transcript_path if full details are needed |

**Deprecated/outdated:**
- Using `session-log.json` (JSON array) for session logging: Project uses `session-log.jsonl` (JSONL format) per OBSV-04 requirement, established in Phase 1.
- Using SessionEnd for pattern extraction agent: SessionEnd does NOT support agent hooks. Pattern extraction uses Stop hook (Phase 5).

## Open Questions

1. **Should PostToolUseFailure also capture Write/Edit failures?**
   - What we know: PostToolUseFailure fires when any tool call throws errors or returns failure results. Write/Edit failures (e.g., permission denied, path not found) are possible.
   - What's unclear: How frequently Write/Edit failures occur in practice and whether they provide useful signal for pattern extraction.
   - Recommendation: Start with Bash-only PostToolUseFailure (most common and useful for error pattern detection per ANTI-02). Expand to Write|Edit in Phase 7 if anti-pattern detection needs it.

2. **Should the session log include tool_response data for Write/Edit?**
   - What we know: PostToolUse includes `tool_response` (success/failure status, file path). For Write, `tool_input.content` has the full file content.
   - What's unclear: Whether downstream phases (5, 7) need the response data or if the input metadata suffices.
   - Recommendation: Log only metadata (file path, tool name, timestamp, session_id). Do NOT log content or response. Phase 5 extraction agent can read actual files and transcript if needed.

3. **Race condition between Stop hook (Phase 5) and SessionEnd log rotation**
   - What we know: Stop fires when Claude finishes responding. SessionEnd fires when the session terminates. The order is Stop first, then SessionEnd. But there may be multiple Stop events per session (one per user turn).
   - What's unclear: Whether the Phase 5 Stop agent hook (which reads session-log.jsonl) will always complete before SessionEnd fires and clears the log.
   - Recommendation: For now, SessionEnd truncates the log. Phase 5 should be designed to handle this: either the Stop hook processes and marks entries, or the cleanup-session.sh archives to a `.prev` file that the next SessionStart cleans up. This is Phase 5's concern, not Phase 3's. Phase 3 should implement simple truncation and document this concern for Phase 5.

4. **Performance measurement approach**
   - What we know: OBSV-03 requires <100ms execution. Claude Code `--debug` mode shows hook execution details.
   - What's unclear: Whether there's a programmatic way to measure hook execution time within the hook itself.
   - Recommendation: Use `date +%s%N` (nanosecond timestamp) at script start and end, output timing to stderr in debug mode. Also verify with `time` command during manual testing. The hook script itself should be minimal enough that 100ms is a generous budget.

## Sources

### Primary (HIGH confidence)
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) - Complete PostToolUse input schema (tool_name, tool_input, tool_response for Write/Edit/Bash), PostToolUseFailure input schema (error, is_interrupt), SessionEnd input schema (reason field), matcher syntax (regex, pipe-separated tool names), exit code semantics (0=success, 2=blocking error), JSON output fields, async hook capability, event support matrix (command-only vs all types)
- [Claude Code Hook Development SKILL.md](https://github.com/anthropics/claude-code/blob/main/plugins/plugin-dev/skills/hook-development/SKILL.md) - Plugin hook patterns, matcher examples, performance guidance
- [Auto-Context Architecture Research](/.planning/research/ARCHITECTURE.md) - Project-specific hook architecture (observe-tool.sh pattern, dual-speed processing, SessionEnd cleanup), verified against official docs

### Secondary (MEDIUM confidence)
- [Claude Code Hooks Guide](https://code.claude.com/docs/en/hooks-guide) - Practical examples and troubleshooting patterns
- [DataCamp Claude Code Hooks Tutorial](https://www.datacamp.com/tutorial/claude-code-hooks) - PostToolUse practical examples with matchers

### Tertiary (LOW confidence)
- None. All critical claims verified with official docs.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Same Bash+jq stack as Phase 1; no new dependencies
- Architecture: HIGH - PostToolUse hook input/output schema verified against official docs; JSONL pattern established in Phase 1; architecture research pre-defined the observe-tool.sh pattern
- Pitfalls: HIGH - Process spawning overhead, escaping, log bloat, SessionEnd reliability all documented from real-world hook development patterns and official docs
- Code examples: HIGH - Input schemas copied from official Claude Code hooks reference with exact field names and types

**Research date:** 2026-02-25
**Valid until:** 2026-03-25 (hook system is stable; 30-day validity appropriate)
