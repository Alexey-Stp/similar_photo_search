#!/usr/bin/env bash
# Self-test for the zero-network SwiftLint custom rules (SPS-5). Lints the annotated fixture and compares,
# line by line, the zero-network violations SwiftLint reports with the `// expect:` annotations:
#   `// expect: rule_a[,rule_b]` - exactly these rules must fire on the line;
#   `// expect: none` or no annotation - none of the rules may fire.
# So every forbidden form is proven independently, and the allowed forms prove there are no false positives.
# Usage: scripts/check-swiftlint-fixture.sh [fixture] [config]   (needs swiftlint)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
fixture="${1:-$root/scripts/fixtures/NetworkViolations.swift}"
config="${2:-$root/.swiftlint.yml}"
rules='no_network_apis|no_network_frameworks|no_socket_calls|no_icloud_downloads|no_remote_url_literals'

if [[ ! -f "$fixture" ]]; then
    echo "error: fixture $fixture not found" >&2
    exit 1
fi

output="$(swiftlint lint --no-cache --config "$config" "$fixture" 2>&1 || true)"

# "<line> <rule>" for every zero-network violation SwiftLint reported.
actual="$(sed -nE "s/^.*:([0-9]+):[0-9]+: (error|warning): .*\(($rules)\)\$/\1 \3/p" <<< "$output" | sort -u)"

# "<line> <rule>" for every rule named in an `// expect:` annotation.
expected="$(grep -nE '// expect: [a-z_, ]+$' "$fixture" \
    | sed -E 's/^([0-9]+):.*\/\/ expect: ([a-z_, ]+)$/\1 \2/' \
    | while read -r line list; do
        for rule in ${list//,/ }; do
            if [[ "$rule" != none ]]; then
                echo "$line $rule"
            fi
        done
      done | sort -u)"

if [[ -z "$expected" ]]; then
    echo "error: $fixture has no '// expect: <rule>' annotations" >&2
    exit 1
fi

missing="$(comm -23 <(echo "$expected") <(echo "$actual"))"
unexpected="$(comm -13 <(echo "$expected") <(echo "$actual"))"

if [[ -n "$missing" || -n "$unexpected" ]]; then
    echo "$output"
    [[ -n "$missing" ]] && echo "error: rules that did not fire (line rule):"$'\n'"$missing" >&2
    [[ -n "$unexpected" ]] && echo "error: rules that fired where they must not (line rule):"$'\n'"$unexpected" >&2
    exit 1
fi

echo "SwiftLint zero-network rules OK: $(wc -l <<< "$expected" | tr -d ' ') expected violations, no false positives"
