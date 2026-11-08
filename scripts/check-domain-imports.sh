#!/usr/bin/env bash
# Fails if the Domain package imports a platform framework (CLAUDE.md: Domain is Foundation only).
# Accelerate is allowed only under Sources/Domain/Clustering/.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
domain="$root/Packages/Domain"

# Matches `import X`, `@testable import X`, `@preconcurrency import X`, `import struct X.Y`, `import X.Sub`.
prefix='^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+((typealias|struct|class|enum|protocol|let|var|func)[[:space:]]+)?'
forbidden='(Photos|PhotosUI|Vision|VisionKit|SwiftData|SwiftUI|UIKit|AppKit|CoreData|Combine)'
end='([[:space:].]|$)'

status=0

if hits="$(grep -rnE --include='*.swift' "${prefix}${forbidden}${end}" "$domain/Sources" "$domain/Tests")"; then
    echo "error: Domain must not import platform frameworks:" >&2
    echo "$hits" >&2
    status=1
fi

if hits="$(grep -rnE --include='*.swift' "${prefix}Accelerate${end}" "$domain/Sources" "$domain/Tests" \
    | grep -v "/Sources/Domain/Clustering/")"; then
    echo "error: Accelerate may only be imported in Packages/Domain/Sources/Domain/Clustering/:" >&2
    echo "$hits" >&2
    status=1
fi

if [[ $status -eq 0 ]]; then
    echo "Domain import boundary OK"
fi
exit $status
