#!/usr/bin/env bash
# Self-test for scripts/ci-needs-build.sh: commits changes to a throwaway repository and checks, for each one,
# whether the script lets CI skip the build. Runs in the lint job next to the other guard self-tests.
#
# Usage: scripts/ci-needs-build-selftest.sh
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ci-needs-build.sh"
repo="$(mktemp -d)"
trap 'rm -rf "$repo"' EXIT
failures=0

git -c init.defaultBranch=main init -q "$repo"
git -C "$repo" config user.name "ci-needs-build self-test"
git -C "$repo" config user.email "selftest@example.invalid"
git -C "$repo" config commit.gpgsign false
git -C "$repo" config core.autocrlf false

# change <message> <shell command>: runs the command inside the repository and commits everything it changed.
change() {
    (cd "$repo" && sh -c "$2") >/dev/null
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "$1"
}

head_sha() {
    git -C "$repo" rev-parse HEAD
}

# expect <true|false> <label> <base> <head>: records a failure unless ci-needs-build.sh prints code=<true|false>.
expect() {
    local got
    got="$(cd "$repo" && bash "$script" "$3" "$4" 2>/dev/null)" || got="exit status $?"
    if [[ "$got" == "code=$1" ]]; then
        echo "ok: $2"
    else
        echo "FAIL: $2: expected code=$1, got '$got'" >&2
        failures=$((failures + 1))
    fi
}

change "base" 'mkdir -p .claude docs Packages/Domain &&
    echo a > README.md && echo a > .claude/settings.json && echo a > docs/notes.md &&
    echo a > Packages/Domain/README.md && echo "let value = 1" > Packages/Domain/Code.swift'
root=$(head_sha)

change "docs" 'echo b >> docs/notes.md'
docs=$(head_sha)
expect false "a change under docs/" "$root" "$docs"

change "root markdown" 'echo b >> README.md'
readme=$(head_sha)
expect false "a Markdown file at the repository root" "$docs" "$readme"

change "claude" 'echo b >> .claude/settings.json'
claude=$(head_sha)
expect false "a change under .claude/" "$readme" "$claude"
expect false "several docs-only commits" "$root" "$claude"

change "nested markdown" 'echo b >> Packages/Domain/README.md'
nested=$(head_sha)
expect true "a Markdown file outside the root" "$claude" "$nested"

change "code" 'echo "let other = 2" >> Packages/Domain/Code.swift'
code=$(head_sha)
expect true "a Swift change" "$nested" "$code"
expect true "docs and code together" "$root" "$code"

change "move" 'git mv Packages/Domain/Code.swift docs/Code.swift'
moved=$(head_sha)
expect true "a code file moved into docs/" "$code" "$moved"

expect true "an all-zero base (new branch)" "0000000000000000000000000000000000000000" "$code"
expect true "an unknown base (force push)" "1234567890abcdef1234567890abcdef12345678" "$code"
expect true "an empty base" "" "$code"

if [[ "$failures" -gt 0 ]]; then
    echo "$failures case(s) failed" >&2
    exit 1
fi
echo "All cases passed"
