// Negative fixture for the zero-network SwiftLint rules in .swiftlint.yml (SPS-5).
// It is NOT compiled and lives outside SwiftLint's `included` paths. CI lints it on purpose and
// expects every custom rule below to fire. When you change a rule, keep one example per rule here.

import Network                       // no_network_frameworks
@preconcurrency import WebKit        // no_network_frameworks
import SafariServices                // no_network_frameworks
import CloudKit                      // no_network_frameworks

let session = URLSession.shared                          // no_network_apis
let config = URLSessionConfiguration.ephemeral           // no_network_apis
let request = URLRequest(url: URL(fileURLWithPath: "/")) // no_network_apis
let monitor = NWPathMonitor()                            // no_network_apis
let image = AsyncImage(url: nil)                         // no_network_apis

func configure(_ options: PHImageRequestOptions, allow: Bool) {
    options.isNetworkAccessAllowed = true    // no_icloud_downloads
    options.isNetworkAccessAllowed = allow   // no_icloud_downloads
}

let endpoint = "https://example.com/upload" // no_remote_url_literals
