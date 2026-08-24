import Foundation

/// Just enough of the zip format to open what pCloud's getzip streams back: a
/// flat archive of small JSON files — central directory at the end, entries
/// stored or deflated, no zip64, no encryption. Inflation is injected as a
/// function because raw DEFLATE lives in Apple's Compression framework, which
/// the app links and this pure-Foundation package must not.
public enum ZipArchive {
    public struct Failure: Error, Equatable, Sendable {
        public let reason: String

        public init(reason: String) {
            self.reason = reason
        }
    }

    /// Every file entry, in central-directory order. `inflate` receives the
    /// compressed bytes and the advertised uncompressed size; returning nil
    /// fails the archive (a truncated body should never half-succeed).
    public static func entries(in data: Data,
                               inflate: (Data, Int) -> Data?) throws -> [(name: String, data: Data)] {
        // End-of-central-directory: scan back for its signature (the record
        // carries a variable-length comment, so it is not at a fixed offset).
        let data = data.startIndex == 0 ? data : Data(data)   // absolute indexing below
        let eocdSignature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
        guard data.count >= 22 else { throw Failure(reason: "too short for a zip") }
        var eocd = -1
        var probe = data.count - 22
        let floor = max(0, data.count - 22 - 65_535)
        while probe >= floor {
            if data[probe] == eocdSignature[0], data[probe + 1] == eocdSignature[1],
               data[probe + 2] == eocdSignature[2], data[probe + 3] == eocdSignature[3] {
                eocd = probe
                break
            }
            probe -= 1
        }
        guard eocd >= 0 else { throw Failure(reason: "no end-of-central-directory") }
        let count = Int(le16(data, eocd + 10))
        var offset = Int(le32(data, eocd + 16))

        var entries: [(name: String, data: Data)] = []
        for _ in 0..<count {
            guard offset + 46 <= data.count, le32(data, offset) == 0x0201_4B50 else {
                throw Failure(reason: "bad central-directory entry")
            }
            let method = Int(le16(data, offset + 10))
            let compressedSize = Int(le32(data, offset + 20))
            let uncompressedSize = Int(le32(data, offset + 24))
            let nameLength = Int(le16(data, offset + 28))
            let extraLength = Int(le16(data, offset + 30))
            let commentLength = Int(le16(data, offset + 32))
            let localOffset = Int(le32(data, offset + 42))
            guard offset + 46 + nameLength <= data.count,
                  let name = String(data: data.subdata(in: (offset + 46)..<(offset + 46 + nameLength)),
                                    encoding: .utf8) else {
                throw Failure(reason: "bad entry name")
            }
            offset += 46 + nameLength + extraLength + commentLength

            if name.hasSuffix("/") { continue }  // a folder row, no bytes
            // The local header repeats the name/extra lengths; the payload
            // follows them.
            guard localOffset + 30 <= data.count, le32(data, localOffset) == 0x0403_4B50 else {
                throw Failure(reason: "bad local header")
            }
            let localName = Int(le16(data, localOffset + 26))
            let localExtra = Int(le16(data, localOffset + 28))
            let payloadStart = localOffset + 30 + localName + localExtra
            guard payloadStart + compressedSize <= data.count else {
                throw Failure(reason: "truncated payload")
            }
            let payload = data.subdata(in: payloadStart..<(payloadStart + compressedSize))
            switch method {
            case 0:
                entries.append((name, payload))
            case 8:
                guard let inflated = inflate(payload, uncompressedSize),
                      inflated.count == uncompressedSize else {
                    throw Failure(reason: "inflate failed for \(name)")
                }
                entries.append((name, inflated))
            default:
                throw Failure(reason: "unsupported compression method \(method)")
            }
        }
        return entries
    }

    private static func le16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func le32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }
}
