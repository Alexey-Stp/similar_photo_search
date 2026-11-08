#!/usr/bin/env bash
# Fails if any entitlements file in the repository grants a networking entitlement (zero-network policy,
# CLAUDE.md rule #1, SPS-5). Checks:
#   - every *.entitlements file wherever it lives (app folder, Config/, ...);
#   - every file configured as the target's entitlements, whatever its extension: `path:` inside an
#     `entitlements:` mapping or `CODE_SIGN_ENTITLEMENTS` in project.yml, and `CODE_SIGN_ENTITLEMENTS` in
#     xcconfig files. `$(SRCROOT)`, `$(PROJECT_DIR)` and `$(SOURCE_ROOT)` are resolved to the project root.
# Each file is parsed as a plist (plutil), so only real entitlement keys count; keys mentioned in XML
# comments are ignored.
# Usage: scripts/check-entitlements.sh [root]   (root defaults to the repository; used by the CI self-tests)
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

# Prints the `path:` values of every `entitlements:` mapping in a project.yml ($1). The whole mapping is read,
# however long, and reading stops at the first line indented at or above the `entitlements:` key.
entitlement_paths_in_project_yml() {
    awk '
        function indent(s) { match(s, /^[ ]*/); return RLENGTH }
        /^[ ]*entitlements:[ ]*$/ { in_map = 1; map_indent = indent($0); child_indent = -1; next }
        in_map {
            if ($0 ~ /^[ ]*(#.*)?$/) next
            if (indent($0) <= map_indent) { in_map = 0; next }
            if (child_indent < 0) child_indent = indent($0)
            if (indent($0) == child_indent && $0 ~ /^[ ]*path:/) {
                sub(/^[ ]*path:[ ]*/, ""); gsub(/["\047]/, ""); sub(/[ ]+#.*$/, ""); print
            }
        }
    ' "$1"
}

# Resolves the build settings that point at the project root in a configured path ($1); prints the result.
resolve_build_settings() {
    local path="$1" name
    for name in SRCROOT PROJECT_DIR SOURCE_ROOT; do
        path="${path//\$($name)/$root}"
        path="${path//\$\{$name\}/$root}"
    done
    echo "$path"
}

configured=()
while IFS= read -r path; do
    [[ -n "$path" ]] && configured+=("$path")
done < <( {
    if [[ -f project.yml ]]; then
        entitlement_paths_in_project_yml project.yml
        grep -hoE '^[[:space:]]*CODE_SIGN_ENTITLEMENTS:[[:space:]]*[^[:space:]#]+' project.yml \
            | sed -E 's/.*CODE_SIGN_ENTITLEMENTS:[[:space:]]*//; s/["'\'']//g' || true
    fi
    while IFS= read -r -d '' xcconfig; do
        grep -hoE '^[[:space:]]*CODE_SIGN_ENTITLEMENTS[^=]*=[[:space:]]*[^[:space:]]+' "$xcconfig" \
            | sed -E 's/.*=[[:space:]]*//' || true
    done < <(find . -path ./scripts/fixtures -prune -o -name '*.xcconfig' -type f -print0)
} | sort -u )

for path in "${configured[@]+"${configured[@]}"}"; do
    resolved="$(resolve_build_settings "$path")"
    if [[ "$resolved" == *'$('* || "$resolved" == *'${'* ]]; then
        echo "error: configured entitlements path $path uses a build setting this check cannot resolve" >&2
        exit 1
    fi
    if [[ ! -f "$resolved" ]]; then
        echo "error: configured entitlements file $path does not exist" >&2
        exit 1
    fi
    files+=("${resolved#"$root"/}")
done

status=0
checked=0
if [[ ${#files[@]} -eq 0 ]]; then
    echo "Entitlements OK (no entitlements files)"
    exit 0
fi
while IFS= read -r -d '' file; do
    checked=$((checked + 1))
    # Converting to XML drops comments and fails on an invalid plist.
    if ! xml="$(plutil -convert xml1 -o - "$file" 2>/dev/null)"; then
        echo "error: $file is not a valid property list" >&2
        status=1
        continue
    fi
    if keys="$(grep -oE '<key>com\.apple\.(developer\.networking[^<]*|security\.network[^<]*)</key>' <<< "$xml")"; then
        echo "$keys" >&2
        echo "error: $file grants a networking entitlement (zero-network policy)" >&2
        status=1
    fi
done < <(printf '%s\0' "${files[@]}" | sort -zu)

if [[ $status -eq 0 ]]; then
    echo "Entitlements OK ($checked file(s) checked)"
fi
exit $status
