#!/usr/bin/env bash
# Deterministic build/test/lint command extraction from project config files
# Outputs a single JSON object to stdout with discovered commands
# Called by /auto-context:ac-init skill during project bootstrap
set -euo pipefail

CWD="${1:-.}"

# Initialize result object
RESULT='{}'

# --- package.json ---
if [ -f "$CWD/package.json" ]; then
  PKG_SECTION='{}'

  # Extract all scripts as object
  SCRIPTS_JSON=$(jq '.scripts // {}' "$CWD/package.json" 2>/dev/null || echo '{}')
  PKG_SECTION=$(echo "$PKG_SECTION" | jq --argjson scripts "$SCRIPTS_JSON" '.scripts = $scripts')

  # Categorize scripts by key name patterns
  BUILD=$(echo "$SCRIPTS_JSON" | jq '[to_entries[] | select(.key | test("^(build|compile|bundle)")) | {(.key): .value}] | add // {}' 2>/dev/null || echo '{}')
  TEST=$(echo "$SCRIPTS_JSON" | jq '[to_entries[] | select(.key | test("^(test|spec|e2e|cypress)")) | {(.key): .value}] | add // {}' 2>/dev/null || echo '{}')
  LINT=$(echo "$SCRIPTS_JSON" | jq '[to_entries[] | select(.key | test("^(lint|format|prettier|eslint|check|typecheck)")) | {(.key): .value}] | add // {}' 2>/dev/null || echo '{}')
  DEV=$(echo "$SCRIPTS_JSON" | jq '[to_entries[] | select(.key | test("^(dev|start|serve)")) | {(.key): .value}] | add // {}' 2>/dev/null || echo '{}')

  PKG_SECTION=$(echo "$PKG_SECTION" | jq \
    --argjson build "$BUILD" \
    --argjson test "$TEST" \
    --argjson lint "$LINT" \
    --argjson dev "$DEV" \
    '.categorized = {build: $build, test: $test, lint: $lint, dev: $dev}')

  # Extract packageManager field if present
  PKG_MGR=$(jq -r '.packageManager // empty' "$CWD/package.json" 2>/dev/null || true)
  if [ -n "$PKG_MGR" ]; then
    PKG_SECTION=$(echo "$PKG_SECTION" | jq --arg pm "$PKG_MGR" '.package_manager = $pm')
  fi

  # Extract module type
  MOD_TYPE=$(jq -r '.type // empty' "$CWD/package.json" 2>/dev/null || true)
  if [ -n "$MOD_TYPE" ]; then
    PKG_SECTION=$(echo "$PKG_SECTION" | jq --arg mt "$MOD_TYPE" '.module_type = $mt')
  fi

  RESULT=$(echo "$RESULT" | jq --argjson pkg "$PKG_SECTION" '.package_json = $pkg')
else
  RESULT=$(echo "$RESULT" | jq '.package_json = null')
fi

# --- Makefile ---
if [ -f "$CWD/Makefile" ]; then
  # Extract non-hidden targets (up to 30)
  TARGETS=$(grep -E '^[a-zA-Z_][a-zA-Z0-9_-]*:' "$CWD/Makefile" | grep -v -E '^\.' | sed 's/:.*//' | head -30)
  if [ -n "$TARGETS" ]; then
    # Convert newline-separated targets to JSON array
    TARGETS_JSON=$(echo "$TARGETS" | jq -R -s 'split("\n") | map(select(length > 0))')
    RESULT=$(echo "$RESULT" | jq --argjson t "$TARGETS_JSON" '.makefile_targets = $t')
  else
    RESULT=$(echo "$RESULT" | jq '.makefile_targets = []')
  fi
else
  RESULT=$(echo "$RESULT" | jq '.makefile_targets = null')
fi

# --- pyproject.toml ---
if [ -f "$CWD/pyproject.toml" ]; then
  PYTOOLS=()

  # Detect known tool sections
  grep -q '\[tool\.pytest' "$CWD/pyproject.toml" 2>/dev/null && PYTOOLS+=("pytest")
  grep -q '\[tool\.ruff' "$CWD/pyproject.toml" 2>/dev/null && PYTOOLS+=("ruff")
  grep -q '\[tool\.mypy' "$CWD/pyproject.toml" 2>/dev/null && PYTOOLS+=("mypy")
  grep -q '\[tool\.black' "$CWD/pyproject.toml" 2>/dev/null && PYTOOLS+=("black")
  grep -q '\[tool\.isort' "$CWD/pyproject.toml" 2>/dev/null && PYTOOLS+=("isort")
  grep -q '\[tool\.poetry\.scripts' "$CWD/pyproject.toml" 2>/dev/null && PYTOOLS+=("poetry-scripts")

  # Extract project.scripts entries if present
  PROJ_SCRIPTS=()
  if grep -q '\[project\.scripts\]' "$CWD/pyproject.toml" 2>/dev/null; then
    # Extract lines between [project.scripts] and next section header
    PROJ_SCRIPTS_RAW=$(awk '/^\[project\.scripts\]/{found=1; next} /^\[/{found=0} found && /=/{print $1}' "$CWD/pyproject.toml" | head -20)
    if [ -n "$PROJ_SCRIPTS_RAW" ]; then
      while IFS= read -r line; do
        [ -n "$line" ] && PROJ_SCRIPTS+=("$line")
      done <<< "$PROJ_SCRIPTS_RAW"
    fi
  fi

  # Build JSON
  PYTOOLS_JSON=$(printf '%s\n' "${PYTOOLS[@]}" 2>/dev/null | jq -R -s 'split("\n") | map(select(length > 0))' || echo '[]')
  PYSCRIPTS_JSON=$(printf '%s\n' "${PROJ_SCRIPTS[@]}" 2>/dev/null | jq -R -s 'split("\n") | map(select(length > 0))' || echo '[]')

  RESULT=$(echo "$RESULT" | jq \
    --argjson tools "$PYTOOLS_JSON" \
    --argjson scripts "$PYSCRIPTS_JSON" \
    '.pyproject = {tools: $tools, project_scripts: $scripts}')
else
  RESULT=$(echo "$RESULT" | jq '.pyproject = null')
fi

# --- Cargo.toml ---
if [ -f "$CWD/Cargo.toml" ]; then
  CARGO_INFO='{}'

  # Detect workspace vs single crate
  if grep -q '\[workspace\]' "$CWD/Cargo.toml" 2>/dev/null; then
    CARGO_INFO=$(echo "$CARGO_INFO" | jq '.is_workspace = true')
  else
    CARGO_INFO=$(echo "$CARGO_INFO" | jq '.is_workspace = false')
  fi

  # Extract package name
  PKG_NAME=$(awk '/^\[package\]/{found=1} found && /^name/{gsub(/[" ]/, ""); sub(/name=/, ""); print; exit}' "$CWD/Cargo.toml" 2>/dev/null || true)
  if [ -n "$PKG_NAME" ]; then
    CARGO_INFO=$(echo "$CARGO_INFO" | jq --arg name "$PKG_NAME" '.package_name = $name')
  fi

  # Detect dev-dependencies (test frameworks)
  DEV_DEPS=()
  if grep -q '\[dev-dependencies\]' "$CWD/Cargo.toml" 2>/dev/null; then
    DEV_DEPS_RAW=$(awk '/^\[dev-dependencies\]/{found=1; next} /^\[/{found=0} found && /=/{print $1}' "$CWD/Cargo.toml" | head -20)
    if [ -n "$DEV_DEPS_RAW" ]; then
      while IFS= read -r line; do
        [ -n "$line" ] && DEV_DEPS+=("$line")
      done <<< "$DEV_DEPS_RAW"
    fi
  fi

  DEV_DEPS_JSON=$(printf '%s\n' "${DEV_DEPS[@]}" 2>/dev/null | jq -R -s 'split("\n") | map(select(length > 0))' || echo '[]')
  CARGO_INFO=$(echo "$CARGO_INFO" | jq --argjson deps "$DEV_DEPS_JSON" '.dev_dependencies = $deps')

  RESULT=$(echo "$RESULT" | jq --argjson cargo "$CARGO_INFO" '.cargo = $cargo')
else
  RESULT=$(echo "$RESULT" | jq '.cargo = null')
fi

# Output final JSON
echo "$RESULT" | jq '.'

exit 0
