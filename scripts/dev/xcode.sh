#!/usr/bin/env bash
# Developer commands for building, running and testing SimilarPhotos from the terminal or from the VS Code tasks
# (.vscode/tasks.json). Not used by CI.
#
# Usage: scripts/dev/xcode.sh <command> [argument]
#
#   generate             xcodegen generate (the .xcodeproj is not committed)
#   open                 generate, then open the project in Xcode
#   build                Debug build for the simulator
#   run-sim              build, install and launch on the simulator
#   run-device           build, install and launch on a connected iPhone
#   test                 app + all package tests on the simulator (same flags as CI)
#   test-only <id>       one target, suite or test on the simulator, e.g. DomainTests/SessionSegmenterTests
#   test-package <name>  swift test for Packages/Domain or Packages/Data on the macOS host
#   device-perf [id]     device-only performance tests on a connected iPhone (SPS-29); default: all six suites
#   calibration-extract  SPS-28 fixture extraction on a connected iPhone; exports the JSON attachment
#   build-release        Release build for a connected iPhone (Instruments, SPS-29)
#   archive              Release archive for a generic iOS device (privacy report, zero-network QA)
#   guards               the architecture and privacy guard scripts that CI runs
#   lint                 swiftlint --strict
#   size-check           changed Swift files: lines over 120 characters and file lengths (CLAUDE.md)
#   ci                   guards, lint, package tests and simulator tests (not the self-tests or device build)
#   logs                 stream the app's os.Logger output from the booted simulator
#   reset-photos         reset the simulator's photo-library permission for the app (re-test onboarding)
#   clean                delete the local DerivedData and test results
#
# Environment:
#   SIMULATOR          simulator name (default "iPhone 17"); the newest runtime with that name is used
#   DEVICE_ID          device UDID for the device commands (default: the first paired iPhone)
#   DEVELOPMENT_TEAM   signing team for the device commands (default: whatever Xcode has configured)
set -euo pipefail

cd "$(dirname "$0")/../.."

readonly PROJECT=SimilarPhotos.xcodeproj
readonly SCHEME=SimilarPhotos
readonly BUNDLE_ID=com.similarphotos.SimilarPhotos
readonly DERIVED_DATA=.build/DerivedData
readonly RESULTS=.build/TestResults
readonly SIMULATOR="${SIMULATOR:-iPhone 17}"
# Lets xcodebuild create certificates and profiles and register a new iPhone (needs the Apple ID in Xcode → Accounts).
readonly DEVICE_SIGNING=(-allowProvisioningUpdates -allowProvisioningDeviceRegistration)
# The device-only suites SPS-29 runs with RUN_DEVICE_PERFORMANCE_TESTS=1.
readonly DEVICE_PERF_SUITES=(
    DataTests/PhotoLibraryPerformanceTests
    DataTests/ImageLoadingPerformanceTests
    DataTests/VisionFeaturePrintDeviceTests
    DataTests/AnalysisCachePerformanceTests
    DomainTests/ClusteringPerformanceTests
    DataTests/QualityScoringDeviceTests
)

die() { echo "error: $*" >&2; exit 1; }
step() { echo "==> $*"; }

generate() {
    if command -v xcodegen >/dev/null; then
        xcodegen generate --quiet
    elif [[ -d "$PROJECT" ]]; then
        echo "warning: xcodegen not installed (brew install xcodegen); using the existing $PROJECT" >&2
    else
        die "xcodegen not installed and $PROJECT missing; run: brew install xcodegen"
    fi
}

# Prints the UDID of the simulator named $SIMULATOR on the newest iOS runtime that has one.
simulator_udid() {
    local udid
    udid=$(xcrun simctl list devices available --json | jq -r --arg name "$SIMULATOR" '
        [.devices | to_entries[] | select(.key | contains("SimRuntime.iOS")) | .value[] | select(.name == $name)]
        | last | .udid // empty')
    [[ -n "$udid" ]] || die "no available simulator named '$SIMULATOR' (xcrun simctl list devices available)"
    echo "$udid"
}

# Prints $DEVICE_ID, or the UDID of the first paired iPhone that is reachable.
device_udid() {
    if [[ -n "${DEVICE_ID:-}" ]]; then echo "$DEVICE_ID"; return; fi
    local json udid
    json=$(mktemp)
    xcrun devicectl list devices --quiet --json-output "$json" >/dev/null
    udid=$(jq -r '[.result.devices[]
        | select(.hardwareProperties.platform == "iOS" and .connectionProperties.pairingState == "paired"
                 and .connectionProperties.tunnelState != "unavailable")]
        | first | .hardwareProperties.udid // empty' "$json")
    rm -f "$json"
    [[ -n "$udid" ]] || die "no paired iPhone connected (connect one, trust this Mac, enable Developer Mode)"
    echo "$udid"
}

# xcodebuild with the project, scheme and local DerivedData; extra arguments are passed through.
xcb() {
    local signing=()
    [[ -n "${DEVELOPMENT_TEAM:-}" ]] && signing=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -derivedDataPath "$DERIVED_DATA" "$@" ${signing[@]+"${signing[@]}"}
}

result_bundle() {
    mkdir -p "$RESULTS"
    echo "$RESULTS/$1-$(date +%Y%m%d-%H%M%S).xcresult"
}

boot_simulator() {
    local udid=$1
    xcrun simctl boot "$udid" 2>/dev/null || true
    open -a Simulator --args -CurrentDeviceUDID "$udid"
    xcrun simctl bootstatus "$udid" >/dev/null
}

run_sim() {
    generate
    local udid
    udid=$(simulator_udid)
    step "Building for $SIMULATOR ($udid)"
    xcb -configuration Debug -destination "platform=iOS Simulator,id=$udid" -quiet build
    boot_simulator "$udid"
    step "Installing and launching"
    xcrun simctl install "$udid" "$DERIVED_DATA/Build/Products/Debug-iphonesimulator/SimilarPhotos.app"
    xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID"
}

run_device() {
    generate
    local udid
    udid=$(device_udid)
    step "Building for device $udid"
    xcb -configuration Debug -destination "platform=iOS,id=$udid" "${DEVICE_SIGNING[@]}" -quiet build
    step "Installing and launching"
    xcrun devicectl device install app --device "$udid" "$DERIVED_DATA/Build/Products/Debug-iphoneos/SimilarPhotos.app"
    xcrun devicectl device process launch --device "$udid" --terminate-existing "$BUNDLE_ID"
}

# Tests on the simulator with CI's flags. Arguments: result-bundle name, then extra xcodebuild arguments.
test_sim() {
    local name=$1; shift
    generate
    local udid bundle
    udid=$(simulator_udid)
    bundle=$(result_bundle "$name")
    step "Testing on $SIMULATOR ($udid); results: $bundle"
    xcb -destination "platform=iOS Simulator,id=$udid" -resultBundlePath "$bundle" \
        SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES CODE_SIGNING_ALLOWED=NO \
        "$@" test
}

device_perf() {
    generate
    local udid bundle only=()
    udid=$(device_udid)
    bundle=$(result_bundle device-perf)
    if [[ -n "${1:-}" ]]; then
        only=("-only-testing:$1")
    else
        for suite in "${DEVICE_PERF_SUITES[@]}"; do only+=("-only-testing:$suite"); done
    fi
    step "Device performance tests on $udid; results: $bundle"
    # xcodebuild passes TEST_RUNNER_<NAME> to the test process as <NAME>.
    TEST_RUNNER_RUN_DEVICE_PERFORMANCE_TESTS=1 \
        xcb -destination "platform=iOS,id=$udid" "${DEVICE_SIGNING[@]}" -resultBundlePath "$bundle" \
        "${only[@]}" test
    echo "Record the device model and iOS version with every number (SPS-29)."
}

calibration_extract() {
    generate
    local udid bundle out
    udid=$(device_udid)
    bundle=$(result_bundle calibration)
    out="${bundle%.xcresult}-attachments"
    step "SPS-28 calibration extraction on $udid; results: $bundle"
    TEST_RUNNER_RUN_CALIBRATION_EXTRACTION=1 \
        xcb -destination "platform=iOS,id=$udid" "${DEVICE_SIGNING[@]}" -resultBundlePath "$bundle" \
        -only-testing:DataTests/CalibrationFixtureExtractionTests test
    xcrun xcresulttool export attachments --path "$bundle" --output-path "$out"
    echo "Attachments exported to $out (manifest.json maps them to calibration-rev2.json)."
}

guards() {
    bash scripts/check-domain-imports.sh
    bash scripts/check-concrete-construction.sh
    bash scripts/check-dependencies.sh
    bash scripts/check-info-plist.sh SimilarPhotos/Info.plist
    bash scripts/check-entitlements.sh
    bash scripts/check-privacy-manifest.sh
    echo "All guards passed."
}

lint() {
    command -v swiftlint >/dev/null || die "swiftlint not installed; run: brew install swiftlint"
    swiftlint --strict
}

size_check() {
    local files
    files=$( { git diff --name-only --diff-filter=d main...HEAD -- '*.swift'
               git diff --name-only --diff-filter=d --cached -- '*.swift'
               git diff --name-only --diff-filter=d -- '*.swift'
               git ls-files --others --exclude-standard -- '*.swift'; } | sort -u \
             | while IFS= read -r file; do [[ -f "$file" ]] && echo "$file"; done || true)
    [[ -n "$files" ]] || { echo "No changed Swift files."; return; }
    # shellcheck disable=SC2086 # one path per line, no spaces in this repo's Swift paths
    awk 'length > 120 { print FILENAME ":" FNR ": line longer than 120 characters" }' $files
    # shellcheck disable=SC2086
    wc -l $files | awk '$2 != "total" && $1 > 350 { print $2 ": " $1 " lines (aim for <= 350, limit 400)" }'
    echo "Checked $(wc -l <<< "$files" | tr -d ' ') changed Swift files."
}

ci() {
    guards
    lint
    local status=0
    swift test --package-path Packages/Domain -Xswiftc -warnings-as-errors || status=1
    swift test --package-path Packages/Data -Xswiftc -warnings-as-errors || status=1
    [[ $status -eq 0 ]] || die "package tests failed"
    test_sim test
}

main() {
    local command=${1:-} udid
    case "$command" in
        generate) generate ;;
        open) generate && open "$PROJECT" ;;
        build)
            generate
            udid=$(simulator_udid)
            xcb -configuration Debug -destination "platform=iOS Simulator,id=$udid" -quiet build ;;
        run-sim) run_sim ;;
        run-device) run_device ;;
        test) test_sim test ;;
        test-only)
            [[ -n "${2:-}" ]] || die "usage: test-only <Target[/Suite[/test]]>"
            test_sim test-only "-only-testing:$2" ;;
        test-package)
            # Presentation only builds for iOS; it is tested by `test` (xcodebuild), as in CI.
            [[ "${2:-}" == Domain || "${2:-}" == Data ]] || die "usage: test-package Domain|Data"
            swift test --package-path "Packages/$2" -Xswiftc -warnings-as-errors ;;
        device-perf) device_perf "${2:-}" ;;
        calibration-extract) calibration_extract ;;
        build-release)
            generate
            udid=$(device_udid)
            xcb -configuration Release -destination "platform=iOS,id=$udid" "${DEVICE_SIGNING[@]}" \
                -quiet build ;;
        archive)
            generate
            xcb -configuration Release -destination 'generic/platform=iOS' -allowProvisioningUpdates \
                -archivePath .build/SimilarPhotos.xcarchive archive
            echo "Archive: .build/SimilarPhotos.xcarchive (open it in Xcode Organizer for the privacy report)." ;;
        guards) guards ;;
        lint) lint ;;
        size-check) size_check ;;
        ci) ci ;;
        logs)
            xcrun simctl spawn booted log stream --level debug --style compact \
                --predicate 'subsystem == "com.similarphotos"' ;;
        reset-photos)
            udid=$(simulator_udid)
            xcrun simctl privacy "$udid" reset photos "$BUNDLE_ID" ;;
        clean) rm -rf "$DERIVED_DATA" "$RESULTS" .build/SimilarPhotos.xcarchive && echo "Cleaned .build/" ;;
        *) awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"; [[ -z "$command" ]] || exit 64 ;;
    esac
}

main "$@"
