#!/usr/bin/env bash
# Fails if a concrete Data implementation is referenced outside the composition root
# (SimilarPhotos/AppContainer.swift), or if Presentation depends on the Data package.
# Usage: scripts/check-concrete-construction.sh [root]   (root defaults to the repository; used by the CI self-tests)
set -euo pipefail

root="$(cd "${1:-$(dirname "$0")/..}" && pwd)"
composition_root="SimilarPhotos/AppContainer.swift"
status=0
cd "$root"

# A missing folder or manifest makes grep fail, which would read as "no hits": refuse instead of passing silently.
for path in Packages/Data/Sources SimilarPhotos Packages/Presentation Packages/Domain \
    Packages/Presentation/Package.swift Packages/Domain/Package.swift; do
    if [[ ! -e "$path" ]]; then
        echo "error: $root/$path not found" >&2
        exit 1
    fi
done

# Public concrete types declared in the Data package.
types="$(grep -rhoE --include='*.swift' \
    '^[[:space:]]*public[[:space:]]+(final[[:space:]]+)?(actor|class|struct)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' \
    Packages/Data/Sources | awk '{print $NF}' | sort -u | paste -sd '|' -)"

if [[ -z "$types" ]]; then
    echo "error: no concrete types found in Packages/Data/Sources" >&2
    exit 1
fi

if hits="$(grep -rnwE --include='*.swift' "($types)" SimilarPhotos Packages/Presentation Packages/Domain \
    | grep -v "^${composition_root}:")"; then
    echo "error: concrete Data types may only be referenced in ${composition_root}:" >&2
    echo "$hits" >&2
    status=1
fi

if hits="$(grep -rnE --include='*.swift' '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+DataLayer([[:space:].]|$)' \
    SimilarPhotos Packages/Presentation Packages/Domain | grep -v "^${composition_root}:")"; then
    echo "error: only ${composition_root} may import DataLayer:" >&2
    echo "$hits" >&2
    status=1
fi

for manifest in Packages/Presentation/Package.swift Packages/Domain/Package.swift; do
    if grep -nE '\.\./Data"' "$manifest" >/dev/null; then
        echo "error: $manifest must not depend on the Data package" >&2
        status=1
    fi
done

if [[ $status -eq 0 ]]; then
    echo "Composition root boundary OK"
fi
exit $status
