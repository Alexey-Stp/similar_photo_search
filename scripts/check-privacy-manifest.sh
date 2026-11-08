#!/usr/bin/env bash
# Validates the app's privacy manifest (SPS-5). Fails if:
#   - the manifest is not a valid plist;
#   - NSPrivacyTracking is not false, or NSPrivacyTrackingDomains / NSPrivacyCollectedDataTypes are not empty
#     (the App Store label must honestly read "Data Not Collected");
#   - a NSPrivacyAccessedAPITypes entry is malformed, has no reasons, or uses a reason code that is not
#     approved for its category (every entry is checked);
#   - the sources (Swift, C, Objective-C) use a required-reason API (scripts/required-reason-apis.txt) whose
#     category is not declared.
# Usage: scripts/check-privacy-manifest.sh [path/to/PrivacyInfo.xcprivacy]   (macOS: uses plutil; needs perl)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
manifest="${1:-$root/SimilarPhotos/PrivacyInfo.xcprivacy}"
table="$root/scripts/required-reason-apis.txt"

if [[ ! -f "$manifest" ]]; then
    echo "error: $manifest not found" >&2
    exit 1
fi

if ! plutil -lint "$manifest" >/dev/null; then
    echo "error: $manifest is not a valid property list" >&2
    exit 1
fi

status=0
# Reports a manifest problem ($*) and marks the run as failed without stopping it.
fail() {
    echo "error: $manifest: $*" >&2
    status=1
}

# --- "Data Not Collected" guarantees ------------------------------------------------------------
tracking="$(plutil -extract NSPrivacyTracking raw -o - "$manifest" 2>/dev/null || echo missing)"
if [[ "$(echo "$tracking" | tr -d '[:space:]')" != "false" ]]; then
    fail "NSPrivacyTracking must be false (got: $tracking)"
fi

for key in NSPrivacyTrackingDomains NSPrivacyCollectedDataTypes; do
    if ! xml="$(plutil -extract "$key" xml1 -o - "$manifest" 2>/dev/null)"; then
        fail "$key is missing (must be an empty array)"
    elif ! grep -q '<array/>' <<< "$xml"; then
        fail "$key must be an empty array: the app collects no data and contacts no domains"
    fi
done

# Prints the field ($2: 1 = category, 2 = approved reasons, 3 = regex) of every data row in the table.
table_field() {
    local line category rest
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        category="${line%%|*}"
        rest="${line#*|}"
        case "$1" in
            1) echo "$category" ;;
            2) echo "${rest%%|*}" ;;
            3) echo "${rest#*|}" ;;
        esac | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
    done < "$table"
}

# Prints the approved reason codes (space-separated) for the category in $1; prints nothing if unknown.
approved_reasons() {
    paste -d '|' <(table_field 1) <(table_field 2) | awk -F'|' -v c="$1" '$1 == c { print $2 }'
}

# --- Declared required-reason categories --------------------------------------------------------
# Walk every entry that exists. A malformed entry is reported and skipped; it does not stop the scan,
# so valid declarations after it are still found.
declared=()
i=0
while plutil -extract "NSPrivacyAccessedAPITypes.$i" xml1 -o - "$manifest" >/dev/null 2>&1; do
    # plutil prints its error text to stdout on a missing key, so discard the output when it fails.
    category="$(plutil -extract "NSPrivacyAccessedAPITypes.$i.NSPrivacyAccessedAPIType" raw -o - "$manifest" 2>/dev/null)" \
        || category=""
    category="$(echo "$category" | tr -d '[:space:]')"
    if [[ ! "$category" =~ ^NSPrivacyAccessedAPICategory[A-Za-z]+$ ]]; then
        fail "NSPrivacyAccessedAPITypes[$i] is malformed: NSPrivacyAccessedAPIType is missing or not a category name (got: '${category}')"
    else
        reasons_xml="$(plutil -extract "NSPrivacyAccessedAPITypes.$i.NSPrivacyAccessedAPITypeReasons" xml1 -o - "$manifest" 2>/dev/null || true)"
        reasons="$(grep -oE '<string>[^<]*</string>' <<< "$reasons_xml" | sed -E 's#</?string>##g' || true)"
        approved="$(approved_reasons "$category")"
        if [[ -z "$approved" ]]; then
            fail "NSPrivacyAccessedAPITypes[$i]: $category is not a known required-reason category (see scripts/required-reason-apis.txt)"
        elif [[ -z "$reasons" ]]; then
            fail "NSPrivacyAccessedAPITypes[$i] ($category) has no NSPrivacyAccessedAPITypeReasons"
        else
            while IFS= read -r reason; do
                if [[ " $approved " != *" $reason "* ]]; then
                    fail "NSPrivacyAccessedAPITypes[$i] ($category): '$reason' is not an approved reason code (approved: $approved)"
                fi
            done <<< "$reasons"
        fi
        declared+=("$category")
    fi
    i=$((i + 1))
done

# Returns success if the category name in $1 was declared in NSPrivacyAccessedAPITypes.
is_declared() {
    local wanted="$1" item
    for item in "${declared[@]+"${declared[@]}"}"; do
        [[ "$item" == "$wanted" ]] && return 0
    done
    return 1
}

# --- Drift check: APIs used in shipping sources must be declared -------------------------------
cd "$root"
sources=()
while IFS= read -r -d '' file; do
    sources+=("$file")
done < <(find SimilarPhotos Packages/*/Sources -not -path '*/.build/*' \
              \( -name '*.swift' -o -name '*.c' -o -name '*.h' -o -name '*.m' -o -name '*.mm' -o -name '*.cpp' \) \
              -type f -print0 2>/dev/null)

while IFS='|' read -r category pattern; do
    [[ ${#sources[@]} -eq 0 ]] && break

    hits="$(RE="$pattern" perl -ne 'print "  $ARGV:$.: $_" if /$ENV{RE}/; close ARGV if eof' "${sources[@]}")"
    if [[ -n "$hits" ]] && ! is_declared "$category"; then
        fail "sources use a $category API but the manifest does not declare it. Add an NSPrivacyAccessedAPITypes entry with the right reason code:"
        echo "$hits" >&2
    fi
done < <(paste -d '|' <(table_field 1) <(table_field 3))

if [[ $status -eq 0 ]]; then
    echo "Privacy manifest OK: $manifest (declared: ${declared[*]:-none})"
fi
exit $status
