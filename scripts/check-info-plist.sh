#!/usr/bin/env bash
# Checks the app's Info.plist and entitlements. Fails if:
#   - a key listed in scripts/required-plist-keys.txt is missing or its value is empty;
#   - a key (or array value) listed in scripts/forbidden-plist-keys.txt is present (zero-network, SPS-5).
# Networking entitlements are checked separately by scripts/check-entitlements.sh.
# Usage: scripts/check-info-plist.sh SimilarPhotos/Info.plist   (macOS only: uses plutil)
set -euo pipefail

plist="${1:?usage: check-info-plist.sh <path/to/Info.plist>}"
scripts_dir="$(cd "$(dirname "$0")" && pwd)"
required_file="$scripts_dir/required-plist-keys.txt"
forbidden_file="$scripts_dir/forbidden-plist-keys.txt"

if [[ ! -f "$plist" ]]; then
    echo "error: $plist not found" >&2
    exit 1
fi

# Prints the entries of a key list file ($1), one per line: comments and blank lines removed, whitespace trimmed.
entries() {
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(echo "${line%%#*}" | tr -d '[:space:]')"
        [[ -n "$line" ]] && echo "$line"
    done < "$1"
}

status=0

while IFS= read -r key; do
    # plutil prints its error message to stdout on a missing key, so rely on the exit code.
    if ! value="$(plutil -extract "$key" raw -o - "$plist" 2>/dev/null)" \
        || [[ -z "$(echo "$value" | tr -d '[:space:]')" ]]; then
        echo "error: $plist is missing required key $key (or its value is empty)" >&2
        status=1
    fi
done < <(entries "$required_file")

while IFS= read -r entry; do
    key="${entry%%=*}"
    if [[ "$entry" == *=* ]]; then
        value="${entry#*=}"
        if xml="$(plutil -extract "$key" xml1 -o - "$plist" 2>/dev/null)" \
            && grep -qF "<string>$value</string>" <<< "$xml"; then
            echo "error: $plist must not contain $value in $key (zero-network policy)" >&2
            status=1
        fi
    elif plutil -extract "$key" xml1 -o - "$plist" >/dev/null 2>&1; then
        echo "error: $plist must not contain $key (zero-network policy)" >&2
        status=1
    fi
done < <(entries "$forbidden_file")

if [[ $status -eq 0 ]]; then
    echo "Info.plist OK: $plist"
fi
exit $status
