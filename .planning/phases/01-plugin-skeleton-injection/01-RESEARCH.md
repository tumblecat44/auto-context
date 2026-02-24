# Phase 1: Plugin Skeleton & Injection - Research

**Researched:** 2026-02-25
**Domain:** Claude Code Plugin System (manifest, hooks, CLAUDE.md injection, data store)
**Confidence:** HIGH

## Summary

Phase 1 establishes the foundational plugin package for Auto-Context: a valid Claude Code plugin that installs zero-config, creates the `.auto-context/` data store, injects auto-generated content into CLAUDE.md marker sections, and enforces a hard 1000-token budget. The Claude Code plugin system is well-documented and stable (public beta since v1.0.33, now mature), with a straightforward directory-based architecture requiring no build step, no compilation, and no registry approval.

The plugin manifest (`.claude-plugin/plugin.json`) only requires a `name` field; all component directories (hooks/, skills/, agents/) are auto-discovered at plugin root. The SessionStart hook is the correct injection point -- it fires on every session start and its stdout is added as context Claude can see. For CLAUDE.md file manipulation, a command-type hook running a Bash script handles marker-section reading, integrity validation, and content injection. The JSONL session log format is trivially O(1) appendable via `>>` (each line is an independent JSON object).

**Primary recommendation:** Build a minimal plugin with `.claude-plugin/plugin.json`, `hooks/hooks.json` (SessionStart command hook), `scripts/inject-context.sh` (reads conventions, writes to CLAUDE.md markers, enforces token budget), and `.auto-context/` directory initialization. Use `claude --plugin-dir .` for development testing.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PLUG-01 | Plugin manifest registers hooks, skills, agents automatically on install | plugin.json auto-discovers components in default locations (hooks/, skills/, agents/). Hooks path can also be explicit via `"hooks": "./hooks/hooks.json"`. Confirmed by official docs. |
| PLUG-02 | Zero-config after `claude plugin install` | Plugin system requires no user configuration. `enabledPlugins` in settings.json is auto-set on install. SessionStart hook fires automatically. |
| PLUG-03 | CLAUDE.md auto-content in `<!-- auto-context:start/end -->` markers, user content untouched | SessionStart command hook reads/writes CLAUDE.md. Script manipulates only content between markers. Existing content outside markers is preserved by sed/awk marker-bounded replacement. |
| PLUG-04 | Marker section validates integrity (corruption, duplication, missing markers) | Script must handle: missing markers (create them), duplicate markers (keep first pair, remove extras), corrupted markers (re-create), missing end marker (re-create). All logic in inject-context.sh. |
| PLUG-05 | `claude plugin validate .` passes | Validator checks: valid JSON in plugin.json, required `name` field, semantic versioning, directory structure, markdown frontmatter in agents/skills, executable scripts, cross-platform paths. |
| INJT-01 | Hard token budget max 1000 tokens for auto-context section | Token estimation via character count (1 token ~ 3.5 chars) or word count (1 token ~ 0.75 words). Script truncates/prioritizes content to stay under budget. Conservative estimate preferred. |
| INJT-04 | SessionStart hook injects conventions into CLAUDE.md marker section | SessionStart command hook fires on startup/resume/clear/compact. Script reads `.auto-context/conventions.json`, formats as markdown, writes between markers in CLAUDE.md. |
| OBSV-04 | Session log uses JSONL format (O(1) appends) | JSONL = one JSON object per line. Append via `echo '{"event":...}' >> session-log.jsonl`. No array rewriting. jq `-c` flag for compact single-line output. |
</phase_requirements>

## Standard Stack

### Core

| Library/Tool | Version | Purpose | Why Standard |
|-------------|---------|---------|--------------|
| Bash | 3.2+ (macOS default) / 5.x (Linux) | Hook command handlers, all scripts | Zero dependency, POSIX-compatible, Claude Code plugin convention for command hooks |
| jq | 1.6+ | JSON parsing/manipulation in scripts | Standard JSON CLI tool, used by Claude Code plugin ecosystem, handles stdin JSON from hooks |

### Supporting

| Library/Tool | Version | Purpose | When to Use |
|-------------|---------|---------|-------------|
| sed | POSIX | Marker section manipulation in CLAUDE.md | When replacing content between markers |
| awk | POSIX | Text processing, token counting by word/char | Alternative to sed for multi-line marker operations |
| wc | POSIX | Character/word counting for token estimation | Token budget enforcement |
| date | POSIX | Timestamps for JSONL log entries | Session log event timestamps |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|-----------|-----------|----------|
| Bash + jq | Node.js scripts | Node.js offers richer JSON handling but adds dependency; Bash+jq is zero-dep and matches project decision |
| sed for markers | Python script | Python is more robust for text manipulation but violates zero-dependency constraint |
| Character-based token estimation | Anthropic count_tokens API | API is accurate but requires network call + API key; offline estimation is sufficient for budget enforcement |

**Installation:**
```bash
# jq is the only external dependency (usually pre-installed on dev machines)
# macOS:
brew install jq
# Linux:
apt-get install jq  # or yum install jq
```

## Architecture Patterns

### Recommended Plugin Structure

```
auto-context/                          # Plugin root (= git repo root)
├── .claude-plugin/
│   └── plugin.json                    # Plugin manifest (name, version, description)
├── hooks/
│   └── hooks.json                     # Hook event configuration
├── scripts/
│   ├── inject-context.sh              # SessionStart → read conventions → write CLAUDE.md
│   ├── init-store.sh                  # Initialize .auto-context/ directory (called by inject-context.sh)
│   └── lib/
│       ├── markers.sh                 # CLAUDE.md marker section read/write/validate functions
│       └── tokens.sh                  # Token counting/budget enforcement functions
├── skills/                            # Empty for Phase 1 (populated in later phases)
├── agents/                            # Empty for Phase 1 (populated in later phases)
├── README.md
└── LICENSE
```

**User project directory (created by plugin):**
```
user-project/
├── .auto-context/                     # Created on first SessionStart
│   ├── conventions.json               # Confirmed conventions (empty array initially)
│   ├── candidates.json                # Candidate patterns (empty array initially)
│   ├── anti-patterns.json             # Anti-pattern DB (empty array initially)
│   ├── session-log.jsonl              # Current session observation buffer
│   └── config.json                    # Plugin runtime config (token budget, thresholds)
├── CLAUDE.md                          # Existing or created, with marker section
│   # ... user content (untouched) ...
│   # <!-- auto-context:start -->
│   # ... auto-generated content ...
│   # <!-- auto-context:end -->
└── ...
```

### Pattern 1: SessionStart Hook for Context Injection

**What:** A command-type hook on SessionStart that reads convention data and injects it into CLAUDE.md
**When to use:** Every session start (startup, resume, clear, compact)
**Example:**

```bash
# hooks/hooks.json
# Source: https://code.claude.com/docs/en/plugins-reference (Hook configuration)
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
    ]
  }
}
```

```bash
# scripts/inject-context.sh (simplified)
# Source: https://code.claude.com/docs/en/hooks (SessionStart decision control)
#!/usr/bin/env bash
set -euo pipefail

# Read hook input from stdin
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')

# Initialize data store if needed
STORE_DIR="${CWD}/.auto-context"
mkdir -p "$STORE_DIR"

# Read conventions and inject into CLAUDE.md
CLAUDE_MD="${CWD}/CLAUDE.md"
# ... marker manipulation logic ...

# Output status as additionalContext (optional)
cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Auto-Context: N conventions active, M candidates pending"
  }
}
EOF

exit 0
```

### Pattern 2: Marker Section Management

**What:** Read/write/validate content between `<!-- auto-context:start -->` and `<!-- auto-context:end -->` markers
**When to use:** Every time CLAUDE.md is modified by the plugin

```bash
# Source: project requirements PLUG-03, PLUG-04
MARKER_START="<!-- auto-context:start -->"
MARKER_END="<!-- auto-context:end -->"

# Check if markers exist
has_markers() {
  local file="$1"
  grep -q "$MARKER_START" "$file" 2>/dev/null && grep -q "$MARKER_END" "$file" 2>/dev/null
}

# Insert markers at end of file if missing
ensure_markers() {
  local file="$1"
  if ! has_markers "$file"; then
    # Remove any orphaned single markers first
    local tmp="${file}.tmp"
    grep -v "$MARKER_START" "$file" | grep -v "$MARKER_END" > "$tmp" 2>/dev/null || true
    mv "$tmp" "$file"
    # Append fresh marker pair
    printf '\n%s\n%s\n' "$MARKER_START" "$MARKER_END" >> "$file"
  fi
}

# Replace content between markers
inject_content() {
  local file="$1"
  local content="$2"
  # Use awk to replace everything between markers
  awk -v start="$MARKER_START" -v end="$MARKER_END" -v content="$content" '
    $0 == start { print; print content; skip=1; next }
    $0 == end { skip=0 }
    !skip { print }
  ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}
```

### Pattern 3: Token Budget Enforcement

**What:** Ensure auto-context section never exceeds 1000 tokens
**When to use:** Before writing content to CLAUDE.md marker section

```bash
# Source: INJT-01 requirement, Anthropic docs (1 token ~ 3.5 chars)
MAX_TOKENS=1000
CHARS_PER_TOKEN=3.5  # Conservative estimate

estimate_tokens() {
  local text="$1"
  local char_count=${#text}
  # Use bc for floating point, fall back to integer division
  echo "$char_count" | awk -v cpt="$CHARS_PER_TOKEN" '{printf "%d", $1/cpt}'
}

enforce_budget() {
  local content="$1"
  local max_chars=$(echo "$MAX_TOKENS * $CHARS_PER_TOKEN" | bc | cut -d. -f1)
  if [ ${#content} -gt "$max_chars" ]; then
    # Truncate to budget with trailing indicator
    content="${content:0:$max_chars}..."
  fi
  echo "$content"
}
```

### Anti-Patterns to Avoid

- **Modifying user content outside markers:** NEVER touch content outside `<!-- auto-context:start/end -->`. Read the whole file, modify only the marker section, write back.
- **Using JSON arrays for session log:** JSON arrays require reading the entire file to append. JSONL (one JSON per line) allows O(1) `>>` append.
- **Blocking SessionStart with slow operations:** SessionStart hooks should be fast. Don't do heavy computation. Read pre-computed data from `.auto-context/conventions.json`.
- **Hardcoding paths:** Always use `${CLAUDE_PLUGIN_ROOT}` for plugin files and `cwd` from stdin JSON for project files. Never hardcode absolute paths.
- **Assuming CLAUDE.md exists:** The file may not exist yet. Create it if missing, then add markers.
- **Using `cat` to read stdin twice:** Hook stdin can only be read once. Store in a variable: `INPUT=$(cat)`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON parsing in Bash | Custom awk/sed JSON parser | jq | JSON edge cases (escaping, nesting, unicode) are deceptively complex |
| Token counting | Character-by-character tokenizer | Simple char/3.5 estimation | Exact tokenization requires the Claude tokenizer; estimation is sufficient for budget enforcement |
| File locking for concurrent writes | Custom flock wrapper | Single-threaded hook execution | Claude Code runs hooks sequentially per event; no concurrent write risk |
| Semantic versioning parsing | Regex version parser | Direct string in plugin.json | Validator handles semver checking; just use "X.Y.Z" format |

**Key insight:** Claude Code hooks execute sequentially and synchronously (unless explicitly marked async). There is no concurrent access to `.auto-context/` files from hooks, so file locking is unnecessary and would add complexity.

## Common Pitfalls

### Pitfall 1: Script Not Executable
**What goes wrong:** Hook script exists but Claude Code silently skips it
**Why it happens:** Missing `chmod +x` on shell scripts after creation
**How to avoid:** Always `chmod +x scripts/*.sh` after creating. Add to build/setup script. Git tracks executable bit.
**Warning signs:** Hook doesn't fire, no output in `claude --debug`

### Pitfall 2: Components Inside .claude-plugin/
**What goes wrong:** Plugin loads but hooks/skills/agents are missing
**Why it happens:** Putting `hooks/`, `skills/`, `agents/` inside `.claude-plugin/` directory
**How to avoid:** Only `plugin.json` goes in `.claude-plugin/`. Everything else at plugin root.
**Warning signs:** `claude --debug` shows plugin loading but no components registered

### Pitfall 3: Shell Profile Contaminating stdout
**What goes wrong:** JSON parsing fails for hook output
**Why it happens:** `.bashrc` or `.zshrc` prints text (motd, conda info, nvm warnings) that prepends to stdout
**How to avoid:** Use `#!/usr/bin/env bash` (not login shell). Don't source user profiles. Keep stdout pure JSON.
**Warning signs:** "JSON validation failed" errors in hook debug output

### Pitfall 4: Reading stdin Multiple Times
**What goes wrong:** Second read of stdin returns empty string
**Why it happens:** stdin is a stream, consumed on first read
**How to avoid:** `INPUT=$(cat)` at script start, then `echo "$INPUT" | jq ...` for each field extraction
**Warning signs:** Variables from stdin JSON are empty after first extraction

### Pitfall 5: CLAUDE.md Marker Corruption
**What goes wrong:** Auto-content appears outside markers, or markers are duplicated
**Why it happens:** Crash during write, concurrent editor modification, or user accidentally editing markers
**How to avoid:** Validate marker integrity before every injection. Handle: missing markers (re-create), duplicate start markers (keep first pair only), missing end marker (re-add), reversed order (re-create both)
**Warning signs:** Content appearing twice, markers in wrong order, marker count != 2

### Pitfall 6: Token Budget Overflow with Unicode
**What goes wrong:** Content exceeds 1000 tokens despite character-based check passing
**Why it happens:** Non-ASCII characters (Korean, CJK) may tokenize differently than English text
**How to avoid:** Use a conservative estimate (1 token ~ 3 chars instead of 3.5) as safety margin, or count bytes instead of characters for non-ASCII content
**Warning signs:** Auto-context section noticeably longer than expected

### Pitfall 7: sed Incompatibility Between macOS and Linux
**What goes wrong:** Marker manipulation works on macOS but fails on Linux (or vice versa)
**Why it happens:** macOS uses BSD sed (requires `-i ''`), Linux uses GNU sed (uses `-i` without arg)
**How to avoid:** Use `awk` instead of `sed -i` for in-place operations, or use temp file pattern (`command > tmp && mv tmp original`)
**Warning signs:** "invalid command code" or "unterminated s command" errors

## Code Examples

Verified patterns from official sources:

### Complete plugin.json Manifest
```json
// Source: https://code.claude.com/docs/en/plugins-reference#complete-schema
{
  "name": "auto-context",
  "version": "0.1.0",
  "description": "Automatic context engineering - project conventions accumulate and refine as you code",
  "author": {
    "name": "dgsw67",
    "url": "https://github.com/dgsw67"
  },
  "repository": "https://github.com/dgsw67/auto-context",
  "license": "MIT",
  "keywords": ["context-engineering", "CLAUDE.md", "automation", "conventions"],
  "hooks": "./hooks/hooks.json"
}
```

### Complete hooks.json for Phase 1
```json
// Source: https://code.claude.com/docs/en/hooks (SessionStart event)
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
    ]
  }
}
```

### SessionStart Hook Input (what the script receives on stdin)
```json
// Source: https://code.claude.com/docs/en/hooks#sessionstart-input
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../.claude/projects/.../00893aaf.jsonl",
  "cwd": "/Users/user/my-project",
  "permission_mode": "default",
  "hook_event_name": "SessionStart",
  "source": "startup",
  "model": "claude-sonnet-4-6"
}
```

### SessionStart Hook Output (JSON for context injection)
```json
// Source: https://code.claude.com/docs/en/hooks#sessionstart-decision-control
// Official example from explanatory-output-style plugin
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Auto-Context: 5 conventions active, 2 candidates pending review"
  }
}
```

### JSONL Session Log Entry Format
```bash
# Source: OBSV-04 requirement + JSONL spec
# Each line is a complete, independent JSON object
echo '{"ts":"2026-02-25T10:30:00Z","event":"session_start","session_id":"abc123","cwd":"/path/to/project"}' >> .auto-context/session-log.jsonl
echo '{"ts":"2026-02-25T10:30:05Z","event":"tool_use","tool":"Write","file":"/path/file.ts"}' >> .auto-context/session-log.jsonl
```

### Data Store Initialization
```bash
# Source: project architecture (section 6.6 of plan document)
init_store() {
  local store_dir="$1/.auto-context"
  mkdir -p "$store_dir"

  # Initialize JSON files only if they don't exist (preserve existing data)
  [ -f "$store_dir/conventions.json" ]   || echo '[]' > "$store_dir/conventions.json"
  [ -f "$store_dir/candidates.json" ]    || echo '[]' > "$store_dir/candidates.json"
  [ -f "$store_dir/anti-patterns.json" ] || echo '[]' > "$store_dir/anti-patterns.json"
  [ -f "$store_dir/config.json" ]        || cat > "$store_dir/config.json" << 'CONF'
{
  "version": "0.1.0",
  "token_budget": 1000,
  "chars_per_token": 3.5
}
CONF

  # Session log: create if missing, but don't overwrite (may have current session data)
  [ -f "$store_dir/session-log.jsonl" ] || touch "$store_dir/session-log.jsonl"
}
```

### Full Marker Integrity Validation
```bash
# Source: PLUG-04 requirement
validate_markers() {
  local file="$1"
  local start_marker="<!-- auto-context:start -->"
  local end_marker="<!-- auto-context:end -->"

  # Count occurrences
  local start_count=$(grep -c "$start_marker" "$file" 2>/dev/null || echo 0)
  local end_count=$(grep -c "$end_marker" "$file" 2>/dev/null || echo 0)

  # Case 1: Perfect - exactly one of each
  if [ "$start_count" -eq 1 ] && [ "$end_count" -eq 1 ]; then
    # Verify order: start must come before end
    local start_line=$(grep -n "$start_marker" "$file" | head -1 | cut -d: -f1)
    local end_line=$(grep -n "$end_marker" "$file" | head -1 | cut -d: -f1)
    if [ "$start_line" -lt "$end_line" ]; then
      echo "valid"
      return 0
    fi
  fi

  # Case 2: Missing both markers
  if [ "$start_count" -eq 0 ] && [ "$end_count" -eq 0 ]; then
    echo "missing_both"
    return 1
  fi

  # Case 3: Duplicates or corruption
  echo "corrupted"
  return 1
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|-------------|-----------------|--------------|--------|
| `commands/` directory for slash commands | `skills/` directory with `SKILL.md` | Claude Code 1.0.33+ (2025) | commands/ still works but skills/ is preferred for new plugins |
| `SessionEnd` for agent extraction | `Stop` hook for agent handlers | Discovered in project research (STATE.md) | SessionEnd does NOT support agent handlers; Stop does |
| Inline hooks in plugin.json | External `hooks/hooks.json` file | Both supported since launch | External file is cleaner for complex hook configs |
| Single JSON arrays for logs | JSONL format (one JSON per line) | Industry standard | O(1) append vs O(n) rewrite; Claude Code transcripts use JSONL |

**Deprecated/outdated:**
- `outputStyle` setting in Claude Code: Deprecated, replaced by plugins (e.g., explanatory-output-style plugin)
- `commands/` directory: Still works but `skills/` is the preferred location for new plugin skills

## Open Questions

1. **SessionStart hook execution order with multiple hooks**
   - What we know: Multiple hooks in the same event fire sequentially
   - What's unclear: If we need both `init-store.sh` and `inject-context.sh` on SessionStart, is the order guaranteed to be array order in hooks.json?
   - Recommendation: Combine into a single script that initializes then injects. Simpler and avoids ordering concerns.

2. **Plugin cache behavior during development**
   - What we know: Marketplace-installed plugins are copied to `~/.claude/plugins/cache`. Version bumps trigger re-copy.
   - What's unclear: Whether `--plugin-dir` bypasses cache (likely yes, as it loads directly)
   - Recommendation: Use `--plugin-dir .` during development. Only bump version for marketplace releases.

3. **Token estimation accuracy for multilingual content**
   - What we know: 1 token ~ 3.5 English characters. CJK/Korean characters tokenize differently (often 1-2 chars per token).
   - What's unclear: Exact ratio for mixed English/Korean content common in this project
   - Recommendation: Use conservative 3.0 chars/token estimate. Add 10% safety margin. Sufficient for Phase 1; can refine in Phase 8 (smart injection).

4. **CLAUDE.md file creation vs. existence assumption**
   - What we know: Many projects already have CLAUDE.md. Some don't.
   - What's unclear: Whether creating CLAUDE.md in a project without one is appropriate
   - Recommendation: Create CLAUDE.md only if `.auto-context/conventions.json` has content to inject. Don't create an empty file with just markers.

## Sources

### Primary (HIGH confidence)
- [Claude Code Plugins Reference](https://code.claude.com/docs/en/plugins-reference) - Complete plugin manifest schema, component paths, directory structure, environment variables, validation, debugging
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) - All hook events, JSON input/output schemas, exit codes, SessionStart decision control, matcher syntax
- [Claude Code Plugins Tutorial](https://code.claude.com/docs/en/plugins) - Plugin creation quickstart, development workflow with `--plugin-dir`, migration from standalone config
- [Official Claude Code Plugins (GitHub)](https://github.com/anthropics/claude-code/tree/main/plugins) - 13 official example plugins including explanatory-output-style (SessionStart hook pattern)
- [Anthropic Token Counting Docs](https://platform.claude.com/docs/en/build-with-claude/token-counting) - Official 1 token ~ 3.5 chars heuristic

### Secondary (MEDIUM confidence)
- [Claude Code Hooks Guide (Anthropic Blog)](https://claude.com/blog/how-to-configure-hooks) - Practical hook examples and troubleshooting
- [DataCamp Claude Code Plugins Tutorial](https://www.datacamp.com/tutorial/how-to-build-claude-code-plugins) - Step-by-step plugin creation walkthrough
- [Context Studios Plugin Guide](https://www.contextstudios.ai/blog/claude-code-plugins-the-complete-guide-to-the-extension-system-2025) - Ecosystem overview and growth metrics (9000+ plugins)

### Tertiary (LOW confidence)
- [Claude Code GitHub Issues](https://github.com/anthropics/claude-code/issues/6403) - PostToolUse hook debugging reports (community-sourced)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Bash+jq is confirmed project decision, matches official plugin patterns
- Architecture: HIGH - Plugin manifest schema and hooks system thoroughly documented by Anthropic with working examples
- Pitfalls: HIGH - Multiple sources confirm common issues (executable permissions, .claude-plugin/ structure, stdin consumption, sed portability)
- Token estimation: MEDIUM - Anthropic provides 3.5 chars/token heuristic but exact accuracy for non-English content is uncertain
- Marker manipulation: MEDIUM - Pattern is straightforward but edge cases (concurrent editors, partial writes) need defensive coding

**Research date:** 2026-02-25
**Valid until:** 2026-03-25 (plugin system is stable; 30-day validity appropriate)
