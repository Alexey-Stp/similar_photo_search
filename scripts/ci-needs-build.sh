#!/usr/bin/env bash
# Decides whether CI has to lint, build and test a change.
# Prints `code=true` or `code=false` on stdout (meant for $GITHUB_OUTPUT); explanation goes to stderr.
#
# A change skips the build only if every changed file matches a docs-only path:
#   .claude/**   Claude Code skills and settings
#   docs/**      backlog and design notes
#   *.md         Markdown files at the repository root (README, CLAUDE.md)
# Anything else, including this script and the workflows, runs the full pipeline.
#
# Usage: scripts/ci-needs-build.sh <base-sha> <head-sha>
set -euo pipefail

base="${1:-}"
head="${2:?usage: ci-needs-build.sh <base-sha> <head-sha>}"
docs_only='^(\.claude/|docs/)|^[^/]+\.md$'

# No usable base (first push of a branch, force push, shallow history): build to be safe.
if [[ -z "$base" || "$base" =~ ^0+$ ]] || ! git cat-file -e "${base}^{commit}" 2>/dev/null; then
    echo "No usable base commit; running the full pipeline" >&2
    echo "code=true"
    exit 0
fi

changed="$(git diff --name-only "$base" "$head")"
needs_build="$(grep -vE "$docs_only" <<< "$changed" || true)"

if [[ -n "$needs_build" ]]; then
    echo "Build needed for:" >&2
    echo "$needs_build" >&2
    echo "code=true"
else
    echo "Docs-only change; skipping lint, build and tests. Changed files:" >&2
    echo "${changed:-<none>}" >&2
    echo "code=false"
fi
