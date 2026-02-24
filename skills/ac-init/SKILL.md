---
name: ac-init
description: Bootstrap project context by scanning structure, tech stack, config files, and git history. Generates initial conventions that surpass Claude Code's built-in /init. Use when setting up auto-context for a new project.
disable-model-invocation: true
---

# Auto-Context: Project Bootstrap

Initialize auto-context by performing a deep project scan and generating initial conventions. This skill surpasses Claude Code's built-in `/init` by detecting naming conventions, testing patterns, architecture patterns, error handling, and import style -- patterns that `/init` does not examine.

**Important rules:**
- Do NOT read every file. Focus on config files, entry points, and a small source sample.
- Write conventions to `.auto-context/conventions.json`, NOT directly to CLAUDE.md.
- The injection pipeline handles CLAUDE.md updates.
- If re-running on an existing project: preserve non-bootstrap conventions, replace bootstrap ones.

---

## Step 1: Initialize Data Store

Ensure the `.auto-context/` directory and required files exist:

```bash
mkdir -p .auto-context
```

Check each file and create only if missing:
- `conventions.json` -- initialize with `[]`
- `candidates.json` -- initialize with `[]`
- `anti-patterns.json` -- initialize with `[]`
- `config.json` -- initialize with `{"version":"0.1.0","token_budget":1000,"chars_per_token":3.0}`
- `session-log.jsonl` -- initialize empty

If `conventions.json` already has entries:
- Read existing conventions.
- If any have `"source"` values other than `"bootstrap"`, warn the user: "Found N existing non-bootstrap conventions. These will be preserved."
- Ask whether to proceed (merge) or abort.
- Bootstrap conventions (those with `"source": "bootstrap"`) will be replaced by the new scan.

---

## Step 2: Detect Project Type and Structure

Use Glob to find key indicator files. Check for presence of:

**Package managers / Languages:**
- `package.json` -> Node.js / JavaScript / TypeScript
- `pyproject.toml`, `setup.py`, `requirements.txt` -> Python
- `Cargo.toml` -> Rust
- `go.mod` -> Go
- `Gemfile` -> Ruby
- `pom.xml`, `build.gradle` -> Java / Kotlin

**Frameworks (check config files):**
- `next.config.*` -> Next.js
- `vite.config.*` -> Vite
- `astro.config.*` -> Astro
- `nuxt.config.*` -> Nuxt
- `angular.json` -> Angular
- `svelte.config.*` -> SvelteKit

**Tooling:**
- `tsconfig.json` -> TypeScript (Read it: check `strict`, `paths`, `target`)
- `.eslintrc*`, `eslint.config.*` -> ESLint
- `.prettierrc*`, `prettier.config.*` -> Prettier
- `jest.config.*`, `vitest.config.*`, `pytest.ini` -> Test frameworks
- `Makefile` -> Make-based build
- `Dockerfile`, `docker-compose.*` -> Docker
- `.github/workflows/` -> GitHub Actions CI

Read each detected config file to extract specific settings (e.g., TypeScript strict mode, ESLint rule overrides, test framework configuration). Record which files you found.

---

## Step 3: Discover Build/Test/Lint Commands

Run the bundled discovery script:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/ac-init/scripts/discover-commands.sh .
```

Interpret the JSON output to identify:
- **Build** command(s): e.g., `npm run build`, `make build`, `cargo build`
- **Test** command(s): e.g., `npm run test`, `pytest`, `cargo test`
  - Also identify single-file test execution if possible (e.g., `npx vitest run path/to/file`)
- **Lint** command(s): e.g., `npm run lint`, `ruff check .`, `cargo clippy`
- **Dev server**: e.g., `npm run dev`, `make serve`

Note the full invocation form for each command (with package manager prefix).

---

## Step 4: Analyze Git History

If this is a git repository, run these commands:

```bash
git log --oneline -20
git shortlog -sn --no-merges HEAD~100..HEAD 2>/dev/null || true
git diff-tree --no-commit-id --name-only -r HEAD~10..HEAD 2>/dev/null || true
```

Look for:
- **Commit message conventions**: conventional commits (`feat:`, `fix:`), ticket numbers, etc.
- **Active areas**: which directories/files changed most recently
- **Contribution patterns**: solo developer vs team, consistent vs varied commit styles

If not a git repository, skip this step.

---

## Step 5: Sample Source Code for Conventions

Read 3-5 source files from the most active areas (identified in Step 4) or main entry points. For each file, read only the first 100 lines.

Detect these patterns:
- **Naming conventions**: camelCase vs snake_case vs PascalCase for variables, functions, files
- **Import style**: relative (`./`) vs absolute (`@/`), barrel files (`index.ts` re-exports)
- **Error handling**: try/catch patterns, Result types, error boundaries, custom error classes
- **Comment style**: JSDoc, docstrings, inline comments, header comments
- **Module organization**: feature-sliced, domain-driven, route-based, flat structure
- **Testing patterns**: test file location (co-located vs `__tests__/`), naming (`.test.ts` vs `.spec.ts`), test structure (describe/it vs test)
- **Export patterns**: default exports vs named exports, barrel files

Cap your sampling: max 5 files, first 100 lines per file.

---

## Step 6: Synthesize Conventions

Combine all findings from Steps 2-5 into conventions. Each convention must be:
- **Specific and actionable** (not vague -- Claude should be able to follow it)
- **Evidenced** by files you examined
- **Scored** with confidence 0.6-0.9 (bootstrap range)

Convention JSON format:
```json
{
  "text": "Use TypeScript with strict mode enabled",
  "confidence": 0.8,
  "source": "bootstrap",
  "created_at": "2026-02-25T10:00:00Z",
  "observed_in": ["tsconfig.json"]
}
```

Generate conventions for these categories (as applicable):
1. **Tech stack and framework**: e.g., "Uses Next.js 14 with App Router"
2. **Build/test/lint commands**: e.g., "Run tests with: npm run test"
3. **Code style**: e.g., "Uses camelCase for variables, PascalCase for React components"
4. **Architecture patterns**: e.g., "Feature-sliced directory structure under src/features/"
5. **Testing patterns**: e.g., "Tests use Vitest with co-located .test.ts files"
6. **Error handling**: e.g., "API errors return {error: string, status: number} responses"
7. **Import style**: e.g., "Uses absolute imports with @/ path alias"
8. **Commit conventions**: e.g., "Uses conventional commits (feat:, fix:, docs:)"

Confidence scoring guide:
- 0.9: Detected from explicit configuration (tsconfig strict: true)
- 0.8: Observed consistently across multiple files
- 0.7: Observed in sampled files but not enough to confirm universality
- 0.6: Inferred from project structure or single observation

**Merge with existing conventions:**
1. Read current `conventions.json`
2. Keep all entries where `source` is NOT `"bootstrap"`
3. Replace all `source: "bootstrap"` entries with new scan results
4. Write merged array back to `.auto-context/conventions.json`

---

## Step 7: Trigger CLAUDE.md Update

After writing conventions, trigger the existing injection pipeline:

```bash
echo '{"cwd":"'"$(pwd)"'","session_id":"ac-init"}' | bash ${CLAUDE_PLUGIN_ROOT}/scripts/inject-context.sh
```

Report to the user:
- How many conventions were generated
- Which categories were detected
- Remind them: "Conventions are injected into CLAUDE.md at each session start"

If the injection command fails, still keep conventions.json intact -- injection will happen automatically at the next SessionStart.
