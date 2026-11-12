#!/usr/bin/env bash
# Self-test helper for CI: runs a guard against a negative fixture and passes only if the guard fails
# *for the intended reason*. Any non-zero exit is not enough: the output must contain the expected
# diagnostic, so an unrelated error (missing fixture, plist syntax, another rule) cannot make it pass.
# Usage: scripts/expect-failure.sh --expect "<text>"... [--absent "<text>"]... -- <command> [args...]
# Every --expect text must appear in the output, and no --absent text may.
set -euo pipefail

expect=()
absent=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --expect) expect+=("$2"); shift 2 ;;
        --absent) absent+=("$2"); shift 2 ;;
        --) shift; break ;;
        *) echo "usage: expect-failure.sh --expect <text>... [--absent <text>]... -- <command>" >&2; exit 2 ;;
    esac
done
if [[ ${#expect[@]} -eq 0 || $# -eq 0 ]]; then
    echo "usage: expect-failure.sh --expect <text>... [--absent <text>]... -- <command>" >&2
    exit 2
fi

set +e
output="$("$@" 2>&1)"
code=$?
set -e
echo "$output"

if [[ $code -eq 0 ]]; then
    echo "::error::self-test: '$*' succeeded but should have failed" >&2
    exit 1
fi
for text in "${expect[@]}"; do
    if ! grep -qF -- "$text" <<< "$output"; then
        echo "::error::self-test: '$*' failed, but not with the expected diagnostic: $text" >&2
        exit 1
    fi
done
for text in "${absent[@]+"${absent[@]}"}"; do
    if grep -qF -- "$text" <<< "$output"; then
        echo "::error::self-test: '$*' reported an unexpected diagnostic: $text" >&2
        exit 1
    fi
done
printf 'Self-test OK: rejected with "%s"\n' "${expect[@]}"
