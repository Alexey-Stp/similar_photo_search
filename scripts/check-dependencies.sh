#!/usr/bin/env bash
# Fails if a remote Swift package is declared or resolved that is not listed in allowed-packages.txt
# (CLAUDE.md rule #5, SPS-5). Checks:
#   - `.package(url: "...")` in Packages/*/Package.swift
#   - `url:` entries in project.yml
#   - every Package.resolved (v1 `repositoryURL`, v2/v3 `location`), which also lists transitive packages:
#     Packages/*/Package.resolved and the Xcode project/workspace swiftpm folders (present after
#     `xcodegen generate` + `xcodebuild -resolvePackageDependencies`).
# URLs are compared case-insensitively, ignoring a trailing ".git" or "/".
# Usage: scripts/check-dependencies.sh [root]   (root defaults to the repository; used by the CI self-test)
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
root="$(cd "${1:-$repo}" && pwd)"
allowed_file="$repo/allowed-packages.txt"
cd "$root"
shopt -s nullglob

normalize() {
    tr '[:upper:]' '[:lower:]' | sed -E 's#/+$##; s#\.git$##'
}

allowed="$(grep -vE '^[[:space:]]*(#|$)' "$allowed_file" | tr -d '[:space:]' | normalize || true)"

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
