#!/usr/bin/env bash
# Fails if a remote Swift package is declared or resolved that is not listed in allowed-packages.txt
# (CLAUDE.md rule #5, SPS-5). Checks:
#   - `.package(url: "...")` in Packages/*/Package.swift
#   - `url:` entries in project.yml
#   - every Package.resolved (v1 `repositoryURL`, v2/v3 `location`), which also lists transitive packages:
#     Packages/*/Package.resolved and the Xcode project/workspace swiftpm folders (present after
#     `xcodegen generate` + `xcodebuild -resolvePackageDependencies`).
# URLs are compared case-insensitively, ignoring a trailing ".git" or "/".
# Usage: scripts/check-dependencies.sh [root]   (root defaults to the repository; used by the CI self-tests)
# ALLOWED_PACKAGES_FILE overrides the allow-list path (CI self-test only).
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
root="$(cd "${1:-$repo}" && pwd)"
allowed_file="${ALLOWED_PACKAGES_FILE:-$repo/allowed-packages.txt}"
allowed_file="$(cd "$(dirname "$allowed_file")" && pwd)/$(basename "$allowed_file")"
cd "$root"
shopt -s nullglob

# Normalizes package URLs read line by line from stdin so equivalent spellings compare equal:
# lower-case, no trailing "/" and no trailing ".git".
normalize() {
    tr '[:upper:]' '[:lower:]' | sed -E 's#/+$##; s#\.git$##'
}

# One URL per line: drop comments and blank lines, strip whitespace inside each line (keep the line breaks).
allowed="$(grep -vE '^[[:space:]]*(#|$)' "$allowed_file" | sed -E 's/[[:space:]]+//g' | normalize || true)"

manifests=(Packages/*/Package.swift)
resolved=(Packages/*/Package.resolved
          *.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
          *.xcworkspace/xcshareddata/swiftpm/Package.resolved)

urls="$( {
    if [[ ${#manifests[@]} -gt 0 ]]; then
        grep -hoE '\.package\([[:space:]]*url:[[:space:]]*"[^"]+"' "${manifests[@]}" \
            | sed -E 's/.*"([^"]+)"/\1/' || true
    fi
    if [[ -f project.yml ]]; then
        grep -hoE '^[[:space:]]+url:[[:space:]]*[^[:space:]]+' project.yml \
            | sed -E 's/.*url:[[:space:]]*//; s/["'\'']//g' || true
    fi
    if [[ ${#resolved[@]} -gt 0 ]]; then
        grep -hoE '"(location|repositoryURL)"[[:space:]]*:[[:space:]]*"[^"]+"' "${resolved[@]}" \
            | sed -E 's/.*"([^"]+)"$/\1/' || true
    fi
} | sort -u )"

if [[ ${#resolved[@]} -gt 0 ]]; then
    echo "Checked Package.resolved: ${resolved[*]}"
fi

status=0
while IFS= read -r url; do
    if [[ -z "$url" ]]; then
        continue
    fi
    if ! grep -qxF "$(normalize <<< "$url")" <<< "$allowed"; then
        echo "error: package $url is not in allowed-packages.txt" >&2
        status=1
    fi
done <<< "$urls"

if [[ $status -eq 0 ]]; then
    echo "Dependencies OK"
fi
exit $status
