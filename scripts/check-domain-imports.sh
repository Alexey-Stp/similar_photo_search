#!/usr/bin/env bash
# Fails if the Domain package imports a platform framework (CLAUDE.md: Domain is Foundation only).
# Accelerate is allowed only under Sources/Domain/Clustering/.
# Usage: scripts/check-domain-imports.sh [root]   (root defaults to the repository; used by the CI self-tests)
set -euo pipefail

root="$(cd "${1:-$(dirname "$0")/..}" && pwd)"
cd "$root"
domain="Packages/Domain"

# A missing folder makes grep fail, which would read as "no hits": refuse instead of passing silently.
if [[ ! -d "$domain/Sources" ]]; then
    echo "error: $root/$domain/Sources not found" >&2
    exit 1
fi
dirs=("$domain/Sources")
if [[ -d "$domain/Tests" ]]; then
    dirs+=("$domain/Tests")
fi

# Matches `import X`, `@testable import X`, `@preconcurrency import X`, `import struct X.Y`, `import X.Sub`.
prefix='^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+((typealias|struct|class|enum|protocol|let|var|func)[[:space:]]+)?'
forbidden='(Photos|PhotosUI|Vision|VisionKit|SwiftData|SwiftUI|UIKit|AppKit|CoreData|Combine)'
end='([[:space:].]|$)'

status=0

if hits="$(grep -rnE --include='*.swift' "${prefix}${forbidden}${end}" "${dirs[@]}")"; then
    echo "error: Domain must not import platform frameworks:" >&2
    echo "$hits" >&2
    status=1
fi

if hits="$(grep -rnE --include='*.swift' "${prefix}Accelerate${end}" "${dirs[@]}" \
    | grep -v "^$domain/Sources/Domain/Clustering/")"; then
    echo "error: Accelerate may only be imported in Packages/Domain/Sources/Domain/Clustering/:" >&2
    echo "$hits" >&2
    status=1
fi

if [[ $status -eq 0 ]]; then
    echo "Domain import boundary OK"
fi
exit $status
