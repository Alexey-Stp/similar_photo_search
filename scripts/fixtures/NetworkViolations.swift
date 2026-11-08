// Fixture for the zero-network SwiftLint rules in .swiftlint.yml (SPS-5).
// It is NOT compiled and lives outside SwiftLint's `included` paths. CI lints it on purpose with
// scripts/check-swiftlint-fixture.sh, which checks every line independently:
//   `// expect: <rule>[,<rule>]` - exactly these zero-network rules must fire on this line;
//   `// expect: none`             - none of them may fire (guards against false positives);
//   any other line                - none of them may fire.

import Network                       // expect: no_network_frameworks
@preconcurrency import WebKit        // expect: no_network_frameworks
import SafariServices                // expect: no_network_frameworks
import CloudKit                      // expect: no_network_frameworks
import Photos                        // expect: none

let session = URLSession.shared                          // expect: no_network_apis
let config = URLSessionConfiguration.ephemeral           // expect: no_network_apis
let request = URLRequest(url: URL(fileURLWithPath: "/")) // expect: no_network_apis
let monitor = NWPathMonitor()                            // expect: no_network_apis
let image = AsyncImage(url: nil)                         // expect: no_network_apis
let photoSession = PhotoSession()                        // expect: none

// Returns options configured the forbidden ways; each assignment is checked on its own line.
func configure(_ options: PHImageRequestOptions, allow: Bool) {
    options.isNetworkAccessAllowed = true                                     // expect: no_icloud_downloads
    options.isNetworkAccessAllowed = allow                                    // expect: no_icloud_downloads
    options.isNetworkAccessAllowed = !false                                   // expect: no_icloud_downloads
    options.isNetworkAccessAllowed = false || allow                           // expect: no_icloud_downloads
    options[keyPath: \PHImageRequestOptions.isNetworkAccessAllowed] = true   // expect: no_icloud_downloads
    options[keyPath: \.isNetworkAccessAllowed] = true                         // expect: no_icloud_downloads
    options.isNetworkAccessAllowed = false                                    // expect: none
    options.isNetworkAccessAllowed = false; options.isSynchronous = false     // expect: none
    assert(options.isNetworkAccessAllowed == false)                           // expect: none
}

let endpoint = "https://example.com/upload" // expect: no_remote_url_literals
let settings = "app-settings:"              // expect: none
