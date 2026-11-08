#!/usr/bin/env bash
# Fails if the given Info.plist lacks any key listed in scripts/required-plist-keys.txt, or the value is empty.
# Usage: scripts/check-info-plist.sh SimilarPhotos/Info.plist   (macOS only: uses plutil)
set -euo pipefail

plist="${1:?usage: check-info-plist.sh <path/to/Info.plist>}"
keys_file="$(cd "$(dirname "$0")" && pwd)/required-plist-keys.txt"

if [[ ! -f "$plist" ]]; then
    echo "error: $plist not found" >&2
    exit 1
fi

status=0
while IFS= read -r line || [[ -n "$line" ]]; do
    key="$(echo "${line%%#*}" | tr -d '[:space:]')"
    if [[ -z "$key" ]]; then
        continue
    fi
    # plutil prints its error message to stdout on a missing key, so rely on the exit code.
    if ! value="$(plutil -extract "$key" raw -o - "$plist" 2>/dev/null)" \
        || [[ -z "$(echo "$value" | tr -d '[:space:]')" ]]; then
        echo "error: $plist is missing required key $key (or its value is empty)" >&2
        status=1
    fi
done < "$keys_file"

if [[ $status -eq 0 ]]; then
    echo "Info.plist usage keys OK: $plist"
fi
exit $status
