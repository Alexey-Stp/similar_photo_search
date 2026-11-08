#!/usr/bin/env bash
# Fails if a remote Swift package is declared that is not listed in allowed-packages.txt (CLAUDE.md rule #5).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
allowed_file="$root/allowed-packages.txt"
cd "$root"

allowed="$(grep -vE '^[[:space:]]*(#|$)' "$allowed_file" | tr -d '[:space:]' || true)"

# URLs from `.package(url: "...")` in manifests and `url:` entries in project.yml.
urls="$( { grep -hoE '\.package\([[:space:]]*url:[[:space:]]*"[^"]+"' Packages/*/Package.swift \
            | sed -E 's/.*"([^"]+)"/\1/' || true
          grep -hoE '^[[:space:]]+url:[[:space:]]*[^[:space:]]+' project.yml \
            | sed -E 's/.*url:[[:space:]]*//; s/["'\'']//g' || true
        } | sort -u )"

status=0
while IFS= read -r url; do
    if [[ -z "$url" ]]; then
        continue
    fi
    if ! grep -qxF "$url" <<< "$allowed"; then
        echo "error: package $url is not in allowed-packages.txt" >&2
        status=1
    fi
done <<< "$urls"

if [[ $status -eq 0 ]]; then
    echo "Dependencies OK"
fi
exit $status
