# Phase 2: Project Bootstrap - Research

**Researched:** 2026-02-25
**Domain:** Claude Code plugin skills, project scanning, tech stack detection, build command discovery
**Confidence:** HIGH

## Summary

Phase 2 creates two Claude Code plugin skills (`/auto-context:ac-init` and `/auto-context:ac-reset`) that bootstrap project context. The `/ac-init` skill is the flagship: when invoked, Claude scans the project's structure, config files, git history, and architecture patterns to generate initial conventions that get injected into CLAUDE.md via the existing Phase 1 marker/injection pipeline. The goal is to surpass Claude Code's built-in `/init` command, which only generates basic build commands and a high-level architecture overview. `/ac-reset` provides a clean teardown of all auto-context state.

The key architectural insight is that **skills are prompt-driven, not script-driven**. A skill's SKILL.md contains instructions that Claude follows using its own tools (Read, Glob, Grep, Bash). The skill tells Claude *what to scan and how to process it* -- Claude's intelligence does the actual pattern recognition. This is fundamentally different from Phase 1's shell-script hooks. The scanning instructions should be highly specific about which files to examine and what patterns to extract, while leaving Claude's reasoning to handle the actual detection. Build/test/lint command discovery should use deterministic jq-based extraction from config files (package.json scripts, Makefile targets, pyproject.toml) augmented by Claude's ability to interpret what each command does.

**Primary recommendation:** Implement `/ac-init` as a SKILL.md with detailed scanning instructions that guide Claude through a multi-step project analysis (structure scan, config file extraction, git history analysis, convention generation), writing results to `.auto-context/conventions.json` and triggering CLAUDE.md injection. Implement `/ac-reset` as a simpler SKILL.md that clears the data store and removes marker content.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| BOOT-01 | `/ac-init` scans project structure, tech stack, config files, git history to generate initial context | Skills system allows Claude to use Read/Glob/Grep/Bash tools to scan anything. SKILL.md instructions define what to scan. Multi-step scanning pattern covers structure, config, git history. |
| BOOT-02 | `/ac-init` surpasses Claude Code's built-in `/init` quality (detects architecture patterns, existing conventions) | `/init` only produces build commands + high-level architecture. Our skill can detect: framework-specific patterns, naming conventions, testing patterns, module boundaries, dependency patterns, error handling styles. Detailed scanning instructions enable deeper analysis. |
| BOOT-03 | Auto-discover build/test/lint commands from package.json scripts, Makefile targets, pyproject.toml, Cargo.toml | Deterministic extraction via jq for package.json, grep/awk for Makefile, TOML parsing for pyproject.toml. Each config format has well-known locations for commands. |
| TRNS-03 | `/ac-reset` clears `.auto-context/` directory and removes CLAUDE.md auto-section cleanly | Skill instructs Claude to `rm -rf .auto-context/` and use existing markers.sh to remove marker section from CLAUDE.md. Simple teardown operation. |
</phase_requirements>

## Standard Stack

### Core

| Library/Tool | Version | Purpose | Why Standard |
|-------------|---------|---------|--------------|
| Bash | 3.2+ (macOS) / 5.x (Linux) | Helper scripts for deterministic extraction (bundled with skills) | Consistent with Phase 1 decision; zero dependency |
| jq | 1.6+ | Extract scripts/commands from package.json and other JSON configs | Standard JSON CLI; already required by Phase 1 |
| SKILL.md | Agent Skills spec | Skill definition files that Claude follows | Official Claude Code plugin skills format |

### Supporting

| Library/Tool | Version | Purpose | When to Use |
|-------------|---------|---------|-------------|
| git | 2.x+ | Git history analysis (log, shortlog, diff-tree) | During project bootstrap scan for contribution patterns |
| awk/grep | POSIX | Makefile target extraction, TOML parsing | Build command discovery from non-JSON config files |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|-----------|-----------|----------|
| SKILL.md (prompt-driven scanning) | Shell script scanning | Shell scripts are deterministic but cannot reason about patterns; SKILL.md leverages Claude's intelligence for convention detection |
| jq for JSON extraction | Claude reading JSON directly | jq is faster and deterministic for known fields; Claude adds interpretation of what commands mean |
| Manual TOML parsing with awk | Python TOML parser | Python would add dependency; awk handles the simple extraction needed (scripts, test commands) |

**Installation:**
```bash
# No additional installation needed -- jq is already required from Phase 1
# Skills are file-based, no compilation or build step
```

## Architecture Patterns

### Recommended Skill Structure

```
skills/
├── ac-init/
│   ├── SKILL.md                 # Main scanning instructions for Claude
│   └── scripts/
│       └── discover-commands.sh # Deterministic build/test/lint extraction
├── ac-reset/
│   └── SKILL.md                 # Teardown instructions
```

### Pattern 1: Prompt-Driven Scanning Skill

**What:** A SKILL.md that instructs Claude to perform a multi-step project analysis using its built-in tools (Read, Glob, Grep, Bash)
**When to use:** For `/ac-init` -- the primary project bootstrap skill
**Why this pattern:** Claude Code's `/init` is itself "just a strong prompt that writes an instructions file." Our skill follows the same pattern but with deeper, more structured scanning instructions.

**Example SKILL.md frontmatter:**
```yaml
# Source: https://code.claude.com/docs/en/skills (Skills documentation)
---
name: ac-init
description: Bootstrap project context by scanning structure, tech stack, config files, and git history. Generates initial conventions that surpass Claude Code's built-in /init. Use when setting up auto-context for a new project.
disable-model-invocation: true
---
```

Key frontmatter decisions:
- `disable-model-invocation: true` -- user must explicitly invoke `/auto-context:ac-init`, not auto-triggered
- No `context: fork` -- runs inline so Claude can access conversation context and write to project files
- No `allowed-tools` restriction -- Claude needs full tool access (Read, Glob, Grep, Bash, Write)

### Pattern 2: Deterministic Command Discovery Script

**What:** A bundled bash script that extracts build/test/lint commands from config files deterministically
**When to use:** Called from SKILL.md instructions to reliably extract commands before Claude interprets them

**Example:**
```bash
#!/usr/bin/env bash
# scripts/discover-commands.sh
# Extracts build/test/lint commands from project config files
set -euo pipefail

CWD="${1:-.}"
RESULT="{}"

# --- package.json ---
if [ -f "$CWD/package.json" ]; then
  SCRIPTS=$(jq -r '.scripts // {} | to_entries[] | "\(.key): \(.value)"' "$CWD/package.json" 2>/dev/null || echo "")
  if [ -n "$SCRIPTS" ]; then
    RESULT=$(echo "$RESULT" | jq --arg scripts "$SCRIPTS" '. + {package_json_scripts: $scripts}')
  fi
fi

# --- Makefile ---
if [ -f "$CWD/Makefile" ]; then
  TARGETS=$(grep -E '^[a-zA-Z_-]+:' "$CWD/Makefile" | sed 's/:.*//' | head -30)
  if [ -n "$TARGETS" ]; then
    RESULT=$(echo "$RESULT" | jq --arg targets "$TARGETS" '. + {makefile_targets: $targets}')
  fi
fi

# --- pyproject.toml ---
if [ -f "$CWD/pyproject.toml" ]; then
  # Extract [tool.pytest], [tool.ruff], [project.scripts] sections
  RESULT=$(echo "$RESULT" | jq '. + {pyproject_toml: true}')
fi

# --- Cargo.toml ---
if [ -f "$CWD/Cargo.toml" ]; then
  RESULT=$(echo "$RESULT" | jq '. + {cargo_toml: true}')
fi

echo "$RESULT" | jq -c '.'
```

### Pattern 3: Convention Output Format

**What:** The format that `/ac-init` writes to `.auto-context/conventions.json`
**When to use:** When storing bootstrap-generated conventions

Conventions generated by `/ac-init` should use the same format as Phase 1's conventions.json:
```json
[
  {
    "text": "Use TypeScript with strict mode enabled (tsconfig.json: strict: true)",
    "confidence": 0.8,
    "source": "bootstrap",
    "created_at": "2026-02-25T10:00:00Z",
    "observed_in": ["tsconfig.json"]
  }
]
```

Key fields:
- `confidence`: Bootstrap conventions start at 0.8 (high but not maximum -- can be refined by observation)
- `source`: "bootstrap" distinguishes from session-observed conventions
- `observed_in`: File evidence for the convention

### Pattern 4: Skill Namespace in Plugin Context

**What:** Plugin skills are namespaced as `/plugin-name:skill-name`
**When to use:** Always for plugin skills

```
# Invocation
/auto-context:ac-init        # Bootstrap project context
/auto-context:ac-reset       # Clear all auto-context data
```

Source: https://code.claude.com/docs/en/plugins -- "Skills are prefixed with this (e.g., `/my-first-plugin:hello`)."

### Pattern 5: Multi-Step Scanning Instructions

**What:** The SKILL.md body should guide Claude through a structured multi-step analysis
**When to use:** For the `/ac-init` skill

The scanning should proceed in phases:
1. **Structure scan**: Glob for key files, identify project type and layout
2. **Config extraction**: Read config files, extract tech stack and tooling
3. **Command discovery**: Run bundled script for deterministic command extraction
4. **Git analysis**: Analyze git log for contribution patterns and active areas
5. **Convention synthesis**: Combine findings into conventions
6. **Injection**: Write to conventions.json and trigger CLAUDE.md update

### Anti-Patterns to Avoid

- **Overloading the skill with too many instructions:** Keep SKILL.md under 500 lines (official recommendation). Use bundled scripts for deterministic work, let Claude reason about patterns.
- **Making the skill auto-invocable:** `/ac-init` is a one-time bootstrap action. Set `disable-model-invocation: true` to prevent Claude from randomly running it.
- **Hard-coding framework lists:** Don't enumerate every possible framework. Instead, teach Claude to detect frameworks from config files (next.config.*, vite.config.*, astro.config.*, etc.) using glob patterns.
- **Scanning everything:** Don't read every file. Focus on config files, entry points, and a sample of source files. Reading too much wastes context window.
- **Writing directly to CLAUDE.md from the skill:** Write to `conventions.json` instead and let the existing SessionStart injection pipeline handle CLAUDE.md. This maintains the single-writer principle.
- **Running `context: fork`:** The init skill needs to write to project files (.auto-context/), so it must run inline, not in a forked subagent context.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON extraction from package.json | Custom awk/sed parser | jq | JSON edge cases (nested objects, special chars) |
| Framework detection | Exhaustive if/elif chain | Glob patterns + Claude reasoning | New frameworks appear constantly; Claude can recognize them |
| TOML parsing | Full TOML parser in bash | Targeted grep/awk for known sections | Only need specific sections (scripts, dependencies); full parsing is overkill |
| Git history analysis | Custom git log parser | `git log --format` + `git shortlog` | Git provides rich formatting options; no need to parse raw output |
| Convention injection into CLAUDE.md | New injection mechanism | Existing markers.sh + inject-context.sh from Phase 1 | Phase 1 already handles marker integrity, token budget, and injection |

**Key insight:** The skill's power comes from Claude's reasoning ability. The bash scripts handle deterministic extraction (what commands exist), while Claude handles pattern recognition (what the project's conventions are). Don't try to make bash scripts recognize patterns -- that's Claude's job.

## Common Pitfalls

### Pitfall 1: Skill Not Found After Creation

**What goes wrong:** Skill directory created but `/auto-context:ac-init` not available
**Why it happens:** Plugin not reloaded after adding skills directory; or SKILL.md missing/malformed frontmatter
**How to avoid:** Restart Claude Code after adding skills. Verify SKILL.md has valid YAML frontmatter between `---` markers. Test with `--plugin-dir .`
**Warning signs:** Skill not appearing in `/help` output

### Pitfall 2: Convention Overwrites vs Merges

**What goes wrong:** Running `/ac-init` a second time overwrites manually-reviewed conventions
**Why it happens:** Naive write to conventions.json replaces entire file
**How to avoid:** Check for existing conventions before writing. Merge bootstrap conventions with existing ones. Use `source: "bootstrap"` field to identify which conventions came from init.
**Warning signs:** User-approved conventions disappearing after re-running init

### Pitfall 3: Context Window Exhaustion During Scan

**What goes wrong:** Skill tries to read too many files, Claude runs out of context
**Why it happens:** Overly broad scanning instructions (e.g., "read all source files")
**How to avoid:** Limit scanning to config files + small sample of source files. Use Glob to find files, then Read selectively. Cap file reads at reasonable limits (e.g., first 100 lines of each file, max 20 source files sampled).
**Warning signs:** Claude truncating responses, hitting context limits, or producing shallow analysis

### Pitfall 4: Missing Script Executable Permission

**What goes wrong:** Bundled `discover-commands.sh` fails to execute
**Why it happens:** Git may not preserve executable bit depending on config
**How to avoid:** Always `chmod +x scripts/*.sh`. Also consider running via `bash scripts/discover-commands.sh` in SKILL.md instructions instead of `./scripts/discover-commands.sh`
**Warning signs:** "Permission denied" errors when skill runs

### Pitfall 5: /ac-reset Leaving Orphaned Markers

**What goes wrong:** After reset, CLAUDE.md has empty marker section or orphaned markers
**Why it happens:** Reset clears data but doesn't clean up CLAUDE.md marker section
**How to avoid:** Reset must both: (1) `rm -rf .auto-context/` AND (2) remove marker section from CLAUDE.md. Use the existing markers.sh functions or have Claude edit the file directly.
**Warning signs:** Empty marker section persisting in CLAUDE.md after reset

### Pitfall 6: Platform-Specific Config File Locations

**What goes wrong:** Scanning misses config files on some platforms
**Why it happens:** Different projects use different config file names for the same tool (e.g., `.eslintrc.json` vs `.eslintrc.js` vs `eslint.config.js` vs `eslint.config.mjs`)
**How to avoid:** Use broad glob patterns: `eslint.config.*`, `.eslintrc.*`, `prettier.config.*`, `.prettierrc*`, etc.
**Warning signs:** Framework/tooling not detected despite being present in the project

### Pitfall 7: Insufficient Differentiation from /init

**What goes wrong:** `/ac-init` produces output similar to `/init`, not justifying its existence
**Why it happens:** Scanning only build commands and file structure (same as /init)
**How to avoid:** Go deeper: detect naming conventions (camelCase vs snake_case), testing patterns (Jest vs Vitest vs pytest), architecture patterns (feature-sliced, domain-driven), error handling patterns, import style (relative vs absolute), module patterns. This is what surpasses /init.
**Warning signs:** Output looks like what `/init` would produce

## Code Examples

### Complete SKILL.md for /ac-init (Template)

```yaml
# Source: https://code.claude.com/docs/en/skills + https://code.claude.com/docs/en/plugins
---
name: ac-init
description: Bootstrap project context by scanning structure, tech stack, config files, and git history. Generates initial conventions that surpass Claude Code's built-in /init. Use when setting up auto-context for a new project.
disable-model-invocation: true
---

# Auto-Context: Project Bootstrap

Initialize auto-context by scanning this project and generating initial conventions.

## Step 1: Initialize Data Store

Ensure `.auto-context/` directory exists with required JSON files:
- conventions.json (array)
- candidates.json (array)
- anti-patterns.json (array)
- config.json (version, token_budget, chars_per_token)
- session-log.jsonl

## Step 2: Detect Project Type and Structure

Use Glob to find key indicator files. Check for presence of:

**Package managers / Languages:**
- package.json → Node.js/JavaScript/TypeScript
- pyproject.toml, setup.py, requirements.txt → Python
- Cargo.toml → Rust
- go.mod → Go
- Gemfile → Ruby
- pom.xml, build.gradle → Java/Kotlin

**Frameworks (check config files):**
- next.config.* → Next.js
- vite.config.* → Vite
- astro.config.* → Astro
- nuxt.config.* → Nuxt
- angular.json → Angular
- svelte.config.* → SvelteKit

**Tooling:**
- tsconfig.json → TypeScript
- .eslintrc*, eslint.config.* → ESLint
- .prettierrc*, prettier.config.* → Prettier
- jest.config.*, vitest.config.*, pytest.ini → Test frameworks
- Makefile → Make-based build
- Dockerfile, docker-compose.* → Docker
- .github/workflows/ → GitHub Actions CI

Read each detected config file to extract specific settings.

## Step 3: Discover Build/Test/Lint Commands

Run the bundled discovery script:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/ac-init/scripts/discover-commands.sh .
```

Interpret the output to identify:
- Build command(s)
- Test command(s) including single-test execution
- Lint command(s)
- Dev server command
- Any other useful scripts

## Step 4: Analyze Git History

If this is a git repository:
```bash
git log --oneline -20          # Recent commits for patterns
git shortlog -sn --no-merges HEAD~100..HEAD  # Active contributors
git diff-tree --no-commit-id --name-only -r HEAD~10..HEAD  # Recently changed files
```

Look for:
- Commit message conventions (conventional commits, etc.)
- Active areas of the codebase
- Contribution patterns

## Step 5: Sample Source Code for Conventions

Read a small sample of source files (3-5 files from active areas) to detect:
- Naming conventions (camelCase, snake_case, PascalCase)
- Import style (relative vs absolute, barrel files)
- Error handling patterns
- Comment style
- Module organization patterns

## Step 6: Synthesize Conventions

Combine all findings into conventions. Each convention should be:
- Specific and actionable (not vague)
- Evidenced by files examined
- Scored with confidence 0.6-0.9 (bootstrap range)

Write conventions to `.auto-context/conventions.json`.

## Step 7: Trigger CLAUDE.md Update

After writing conventions, inform the user that conventions have been generated
and will be injected into CLAUDE.md on next session start.
```

### SKILL.md for /ac-reset

```yaml
# Source: https://code.claude.com/docs/en/skills
---
name: ac-reset
description: Clear all auto-context data and remove auto-generated sections from CLAUDE.md. Use to start fresh or uninstall auto-context from a project.
disable-model-invocation: true
---

# Auto-Context: Reset

Clear all auto-context data for this project.

## Steps

1. **Remove data store**: Delete the `.auto-context/` directory entirely
   ```bash
   rm -rf .auto-context/
   ```

2. **Clean CLAUDE.md**: Remove the auto-context marker section from CLAUDE.md
   - Find and remove everything between `<!-- auto-context:start -->` and `<!-- auto-context:end -->` (inclusive)
   - If the file is empty after removal, delete it only if it was created by auto-context

3. **Confirm**: Report what was cleaned up to the user
```

### Config File Scanning Patterns

```bash
# Source: Project research - standard config file locations per ecosystem

# Node.js ecosystem
NODEJS_INDICATORS=("package.json" "package-lock.json" "yarn.lock" "pnpm-lock.yaml")
NODEJS_FRAMEWORKS=("next.config.*" "vite.config.*" "nuxt.config.*" "astro.config.*" "svelte.config.*" "angular.json" "remix.config.*")
NODEJS_TOOLING=("tsconfig.json" "tsconfig.*.json" ".eslintrc*" "eslint.config.*" ".prettierrc*" "prettier.config.*" "jest.config.*" "vitest.config.*" ".babelrc*" "babel.config.*" "webpack.config.*" "rollup.config.*")

# Python ecosystem
PYTHON_INDICATORS=("pyproject.toml" "setup.py" "setup.cfg" "requirements.txt" "Pipfile" "poetry.lock")
PYTHON_TOOLING=("pytest.ini" "tox.ini" "mypy.ini" ".flake8" "ruff.toml" ".ruff.toml")

# Rust ecosystem
RUST_INDICATORS=("Cargo.toml" "Cargo.lock")
RUST_TOOLING=("rustfmt.toml" ".rustfmt.toml" "clippy.toml" ".clippy.toml")

# Go ecosystem
GO_INDICATORS=("go.mod" "go.sum")

# General
GENERAL_BUILD=("Makefile" "CMakeLists.txt" "Justfile" "Taskfile.yml")
GENERAL_CI=(".github/workflows/*.yml" ".gitlab-ci.yml" ".circleci/config.yml" "Jenkinsfile")
GENERAL_CONTAINER=("Dockerfile" "docker-compose.yml" "docker-compose.yaml")
```

### Package.json Script Extraction with jq

```bash
# Source: jq documentation + package.json spec
# Extract categorized commands from package.json

# All scripts
jq -r '.scripts // {} | to_entries[] | "\(.key): \(.value)"' package.json

# Build commands (common patterns)
jq -r '.scripts // {} | to_entries[] | select(.key | test("^(build|compile|bundle)")) | "\(.key): \(.value)"' package.json

# Test commands
jq -r '.scripts // {} | to_entries[] | select(.key | test("^(test|spec|e2e|cypress)")) | "\(.key): \(.value)"' package.json

# Lint commands
jq -r '.scripts // {} | to_entries[] | select(.key | test("^(lint|format|prettier|eslint|check)")) | "\(.key): \(.value)"' package.json

# Dev server
jq -r '.scripts // {} | to_entries[] | select(.key | test("^(dev|start|serve)")) | "\(.key): \(.value)"' package.json
```

### Makefile Target Extraction

```bash
# Source: Make manual + common patterns
# Extract non-hidden targets from Makefile

grep -E '^[a-zA-Z_][a-zA-Z0-9_-]*:' Makefile | \
  grep -v -E '^\.' | \
  sed 's/:.*//' | \
  sort | \
  head -30
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|-------------|-----------------|--------------|--------|
| `/init` generates basic CLAUDE.md | Skills-based deep scanning with pattern detection | Claude Code skills system (2025) | Skills can access tools, read files, run scripts -- much deeper than a simple prompt |
| `commands/` directory for slash commands | `skills/` directory with SKILL.md | Claude Code 1.0.33+ (2025) | Skills support frontmatter, bundled resources, invocation control |
| Hardcoded project type detection | Config file glob patterns + Claude reasoning | Ongoing | More resilient to new frameworks and tools |

**Deprecated/outdated:**
- `.claude/commands/` still works but `skills/` is preferred for new development
- Plugin skills MUST use `skills/` directory (not `commands/`)

## Open Questions

1. **Should `/ac-init` trigger CLAUDE.md injection immediately or defer to next SessionStart?**
   - What we know: SessionStart hook already handles injection. The skill could write conventions and then manually call inject-context.sh, or let the next SessionStart pick them up.
   - What's unclear: Whether the user expects to see CLAUDE.md updated immediately after running `/ac-init`
   - Recommendation: Have the skill write conventions to `.auto-context/conventions.json`, then call `bash ${CLAUDE_PLUGIN_ROOT}/scripts/inject-context.sh` with appropriate stdin JSON to trigger immediate injection. This gives instant feedback.

2. **Convention confidence scoring for bootstrap-generated items**
   - What we know: Phase 6 will implement full lifecycle. Bootstrap conventions need initial confidence scores.
   - What's unclear: Whether bootstrap conventions should start as "conventions" or "candidates" in the lifecycle
   - Recommendation: Store as conventions with `source: "bootstrap"` and confidence 0.7-0.9 depending on evidence strength. This allows immediate injection while still being subject to later lifecycle management.

3. **Re-running `/ac-init` on an already-bootstrapped project**
   - What we know: Users may want to re-scan after significant project changes
   - What's unclear: Whether to merge, replace, or prompt the user
   - Recommendation: Detect existing conventions. If present, merge: keep user-approved conventions (those without `source: "bootstrap"`), replace bootstrap conventions with new scan results. Warn the user about what will change.

4. **How to invoke inject-context.sh from the skill context**
   - What we know: inject-context.sh expects JSON on stdin with `cwd` and `session_id` fields
   - What's unclear: Whether `${CLAUDE_PLUGIN_ROOT}` is available in the skill's Bash execution context
   - Recommendation: Have the skill instruct Claude to construct the appropriate JSON and pipe it to the script. Alternatively, have the skill directly write to CLAUDE.md using the same marker logic (simpler, fewer dependencies). Test both approaches during implementation.

## Sources

### Primary (HIGH confidence)
- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills) - Complete SKILL.md format, frontmatter fields, invocation control, supporting files, plugin skills namespace
- [Claude Code Plugins Documentation](https://code.claude.com/docs/en/plugins) - Plugin structure, skill namespacing (`/plugin-name:skill-name`), development testing with `--plugin-dir`
- [Anthropic Skills Repository](https://github.com/anthropics/skills) - Official skill examples including skill-creator (best practices for SKILL.md authoring)
- Phase 1 codebase (inject-context.sh, markers.sh, tokens.sh) - Existing injection pipeline that Phase 2 integrates with

### Secondary (MEDIUM confidence)
- [Build your own /init command](https://kau.sh/blog/build-ai-init-command/) - Analysis of what Claude Code's /init does and how to surpass it
- [O'Reilly: Reverse Engineering Architecture](https://www.oreilly.com/radar/reverse-engineering-your-software-architecture-with-claude-code-to-help-claude-code/) - Techniques for scanning project architecture for AI assistants
- [OneAway Claude Code Skills Guide](https://oneaway.io/blog/claude-code-skills-slash-commands) - Community guide on skill creation patterns
- [Mikhail Shilkov Inside Claude Code Skills](https://mikhail.io/2025/10/claude-code-skills/) - Deep dive on skill structure and invocation

### Tertiary (LOW confidence)
- Framework config file names and patterns - based on general web development knowledge; specific file names should be verified against actual projects

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Skills system is well-documented by Anthropic with official examples; bash/jq consistent with Phase 1
- Architecture: HIGH - Plugin skills pattern is clearly documented; scanning approach proven by /init's own design
- Pitfalls: HIGH - Common skill development issues documented in official troubleshooting; convention management pitfalls derived from Phase 1 experience
- Config file patterns: MEDIUM - Based on common knowledge of each ecosystem; specific file names may vary

**Research date:** 2026-02-25
**Valid until:** 2026-03-25 (skills system is stable; 30-day validity appropriate)
