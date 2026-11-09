import Foundation

/// A compact, stable summary of a session's membership, stored with the session's results so a later scan can tell
/// whether those results still apply.
///
/// Two sessions have equal `content` exactly when they hold the same photos (IDs) with the same modification dates
/// and favorite flags (up to a 64-bit hash collision). The session ID alone is not enough: it names only the newest
/// photo, so an older photo joining or leaving a session keeps the ID.
public struct SessionFingerprint: Sendable, Hashable, Codable {
    /// The membership summary that is compared.
    public struct Content: Sendable, Hashable, Codable {
        /// The number of photos.
        public let memberCount: Int
        /// FNV-1a 64-bit hash over every photo's ID, modification date and favorite flag, in `PhotoAsset.libraryOrder`.
        public let digest: UInt64

        /// Creates a content value, for example when reading a stored fingerprint.
        public init(memberCount: Int, digest: UInt64) {
            self.memberCount = memberCount
            self.digest = digest
        }
    }

    /// `PhotoSession.id` of the session.
    public let sessionID: String
    /// What is compared between scans.
    public let content: Content

    /// Creates a fingerprint from stored values.
    public init(sessionID: String, content: Content) {
        self.sessionID = sessionID
        self.content = content
    }

    /// The fingerprint of `session`. Deterministic across launches and devices (it does not use `Hasher`).
    public init(_ session: PhotoSession) {
        var hash = FNV1a64()
        for asset in session.assets {
            hash.combine(asset.id)
            hash.combine(UInt8(0x1F))
            if let modified = asset.modificationDate {
                hash.combine(UInt8(0x01))
                hash.combine(Int64(exactly: (modified.timeIntervalSince1970 * 1_000).rounded()) ?? 0)
            } else {
                hash.combine(UInt8(0x00))
            }
            hash.combine(UInt8(asset.isFavorite ? 0x01 : 0x00))
            hash.combine(UInt8(0x1E))
        }
        self.init(sessionID: session.id, content: Content(memberCount: session.assets.count, digest: hash.value))
    }
}

/// The 64-bit FNV-1a hash, chosen because it is tiny, stable and good enough to detect changed sessions.
struct FNV1a64 {
    private(set) var value: UInt64 = 0xcbf2_9ce4_8422_2325
    private static let prime: UInt64 = 0x0000_0100_0000_01b3

    /// Mixes one byte into the hash.
    mutating func combine(_ byte: UInt8) {
        value ^= UInt64(byte)
        value &*= Self.prime
    }

    /// Mixes the UTF-8 bytes of `string`.
    mutating func combine(_ string: String) {
        for byte in string.utf8 {
            combine(byte)
        }
    }

    /// Mixes the 8 bytes of `number`, little-endian.
    mutating func combine(_ number: Int64) {
        var bits = UInt64(bitPattern: number)
        for _ in 0..<8 {
            combine(UInt8(truncatingIfNeeded: bits))
            bits >>= 8
        }
    }
}
