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
import MultipeerConnectivity         // expect: no_network_frameworks
import Photos                        // expect: none

let session = URLSession.shared                          // expect: no_network_apis
let config = URLSessionConfiguration.ephemeral           // expect: no_network_apis
let request = URLRequest(url: URL(fileURLWithPath: "/")) // expect: no_network_apis
let monitor = NWPathMonitor()                            // expect: no_network_apis
let image = AsyncImage(url: nil)                         // expect: no_network_apis
let webView = WKWebView()                                // expect: no_network_apis
let photoSession = PhotoSession()                        // expect: none

// Mutates the option every forbidden way; each line is checked on its own.
func configure(_ options: PHImageRequestOptions, allow: Bool) {
    options.isNetworkAccessAllowed = true                                     // expect: no_icloud_downloads
    options.isNetworkAccessAllowed = allow                                    // expect: no_icloud_downloads
    options.isNetworkAccessAllowed = !false                                   // expect: no_icloud_downloads
    options.isNetworkAccessAllowed = false || allow                           // expect: no_icloud_downloads
    options.isNetworkAccessAllowed = false /* see below */ || allow           // expect: no_icloud_downloads
    options[keyPath: \PHImageRequestOptions.isNetworkAccessAllowed] = true   // expect: no_icloud_downloads
    options[keyPath: \.isNetworkAccessAllowed] = true                         // expect: no_icloud_downloads
    options.isNetworkAccessAllowed = false; options.isNetworkAccessAllowed.toggle() // expect: no_icloud_downloads
    self.store.options.isNetworkAccessAllowed.toggle()                        // expect: no_icloud_downloads
    flip(&options.isNetworkAccessAllowed)                                     // expect: no_icloud_downloads
    options.isNetworkAccessAllowed = false                                    // expect: none
    options.isNetworkAccessAllowed = false // never download originals        // expect: none
    options.isNetworkAccessAllowed = false; options.isSynchronous = false     // expect: none
    assert(options.isNetworkAccessAllowed == false)                           // expect: none
    if allow && options.isNetworkAccessAllowed == false { return }            // expect: none
}

let endpoint = "https://example.com/upload" // expect: no_remote_url_literals
let upper = "HTTP://EXAMPLE.COM/"           // expect: no_remote_url_literals
let socket = "wss://example.com/live"       // expect: no_remote_url_literals
let files = "ftp://example.com/pub"         // expect: no_remote_url_literals
let settings = "app-settings:"              // expect: none

// Justified exemption: the privacy-policy link only opens in Safari; the app itself never loads it.
// swiftlint:disable:next no_remote_url_literals
let policy = "https://example.com/privacy"  // expect: none
let afterExemption = "https://example.com/" // expect: no_remote_url_literals

// Direct BSD socket and resolver calls (SPS-30).
func openSocket(address: UnsafePointer<sockaddr>, length: socklen_t) {
    let fd = socket(AF_INET, SOCK_STREAM, 0)                            // expect: no_socket_calls
    let fd6 = Darwin.socket(AF_INET6, SOCK_DGRAM, 0)                    // expect: no_socket_calls
    _ = connect(fd, address, length)                                    // expect: no_socket_calls
    _ = Glibc.connect(fd6, address, length)                             // expect: no_socket_calls
    _ = connect (fd, address, length)                                   // expect: no_socket_calls
    _ = getaddrinfo("example.com", "443", &hints, &info)                // expect: no_socket_calls
    let host = gethostbyname("localhost")                               // expect: no_socket_calls
    let host6 = gethostbyname2("localhost", AF_INET6)                   // expect: no_socket_calls
    let peer = gethostbyaddr(&raw, socklen_t(4), AF_INET)               // expect: no_socket_calls
    _ = getnameinfo(address, length, &name, 64, nil, 0, 0)              // expect: no_socket_calls
    _ = sendto(fd, buffer, count, 0, address, length)                   // expect: no_socket_calls
    _ = recvfrom(fd, buffer, count, 0, nil, nil)                        // expect: no_socket_calls
    _ = connect(fd, sockaddrPointer(&storage), socklen_t(MemoryLayout<sockaddr_in>.size)) // expect: no_socket_calls
    _ = connect(                                                        // expect: no_socket_calls
        fd, address, length
    )
}

// Look-alikes that must not fire.
final class LibraryClient {
    func connect(to host: String) {}                                    // expect: none
    func connect() {}                                                   // expect: none
    func refresh(client: LibraryClient, publisher: Publisher) {
        client.connect(to: "library")                                   // expect: none
        connect(to: "library")                                          // expect: none
        connect(1)                                                      // expect: none
        connect(fd, address)                                            // expect: none
        _ = gethostbyname2("library")                                   // expect: none
        self.connect()                                                  // expect: none
        let cancellable = publisher.autoconnect()                       // expect: none
        reconnect(fd, address, length)                                  // expect: none
        let pair = socketPair(count: 2)                                 // expect: none
        // Calls socket(AF_INET, SOCK_STREAM, 0) in a comment           // expect: none
        let note = "socket(AF_INET, SOCK_STREAM, 0) and connect(fd, a)" // expect: none
    }
}

enum Transport {
    case socket(Int32)                                                  // expect: none
    case connect(String)                                                // expect: none
}
