#!/usr/bin/env bash
# Fails if any entitlements file in the repository grants a networking entitlement (zero-network policy,
# CLAUDE.md rule #1, SPS-5). Scans every *.entitlements file wherever it lives (app folder, Config/, ...),
# plus any file named by `entitlements:`/`path:` in project.yml or CODE_SIGN_ENTITLEMENTS in an xcconfig,
# so moving the target's entitlements to another directory does not bypass the check.
# Usage: scripts/check-entitlements.sh [root]   (root defaults to the repository; used by the CI self-test)
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
root="$(cd "${1:-$repo}" && pwd)"
cd "$root"

files=()
# Every *.entitlements file, skipping build output and the self-test fixtures of the real repository.
while IFS= read -r -d '' file; do
    files+=("${file#./}")
done < <(find . \( -path ./scripts/fixtures -o -name .build -o -name DerivedData -o -name .git \) -prune \
              -o -name '*.entitlements' -type f -print0)

# Files configured explicitly, even with an unusual extension.
configured="$( {
    if [[ -f project.yml ]]; then
        grep -A3 -E '^[[:space:]]+entitlements:' project.yml \
            | grep -oE 'path:[[:space:]]*[^[:space:]]+' | sed -E 's/path:[[:space:]]*//; s/["'\'']//g' || true
    fi
    for xcconfig in $(find . -name '*.xcconfig' -not -path './scripts/fixtures/*' 2>/dev/null); do
        grep -hoE '^[[:space:]]*CODE_SIGN_ENTITLEMENTS[^=]*=[[:space:]]*[^[:space:]]+' "$xcconfig" \
            | sed -E 's/.*=[[:space:]]*//' || true
    done
} | sort -u )"
while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    if [[ ! -f "$file" ]]; then
        echo "error: configured entitlements file $file does not exist" >&2
        exit 1
    fi
    files+=("$file")
done <<< "$configured"

status=0
for file in $(printf '%s\n' "${files[@]+"${files[@]}"}" | sort -u); do
    if grep -nE 'com\.apple\.(developer\.networking|security\.network)' "$file" >&2; then
        echo "error: $file grants a networking entitlement (zero-network policy)" >&2
        status=1
    fi
done

if [[ $status -eq 0 ]]; then
    echo "Entitlements OK (${#files[@]} file(s) checked)"
fi
exit $status
