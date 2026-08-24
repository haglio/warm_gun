import Foundation

/// One call to the pCloud HTTP JSON API, built but not sent: every method is a
/// GET on `https://<host>/<method>?<query>`, so a request is fully described by
/// its method name and its query. Keeping it a value means the whole API
/// surface is testable without a network — the app's transport takes it from
/// here and only chooses the host (`api.pcloud.com` US / `eapi.pcloud.com` EU).
public struct PCloudRequest: Equatable, Sendable {
    public let method: String
    public let query: [URLQueryItem]

    public init(method: String, query: [URLQueryItem]) {
        self.method = method
        self.query = query
    }

    public func url(host: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        return finish(&components)
    }

    /// The same request against an arbitrary origin — the real API is https on
    /// a bare host, but the local stand-in (`tools/fake_pcloud.py`) serves the
    /// same methods on `http://localhost:<port>`, and the request should not be
    /// the thing that knows the difference.
    public func url(origin: URL) -> URL {
        var components = URLComponents()
        components.scheme = origin.scheme ?? "https"
        components.host = origin.host
        components.port = origin.port
        return finish(&components)
    }

    private func finish(_ components: inout URLComponents) -> URL {
        components.path = "/" + method
        // Not `queryItems`: URLComponents leaves "+" unescaped, and pCloud reads
        // a raw "+" in a value as a space — which silently corrupts any password
        // containing one. Encoding the pairs ourselves, with the sub-delimiters
        // that mean something in a query string removed from the allowed set,
        // is the only way a password survives the wire intact.
        components.percentEncodedQuery = query.isEmpty ? nil : query.map { item in
            let name = Self.escape(item.name)
            guard let value = item.value else { return name }
            return "\(name)=\(Self.escape(value))"
        }.joined(separator: "&")
        // Force-unwrap is safe: scheme, host and path are all set from values we
        // control, and the query is already percent-encoded.
        return components.url!
    }

    private static let valueAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?#")
        return allowed
    }()

    private static func escape(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: valueAllowed) ?? text
    }
}

/// Every call Warm Gun makes, as a request it can build without a network — so the
/// query shape of each one is pinned by a test rather than discovered against
/// the live account. `timeformat=timestamp` rides along wherever a date can
/// come back, because pCloud's default is an RFC-1123 string that `Date` would
/// have to be taught to parse.
public enum PCloudAPI {
    /// The one call that takes a password. The token it returns is what the
    /// Keychain keeps; the password is used here and forgotten.
    ///
    /// The method is `login`, not `userinfo?getauth=1`, and the difference is
    /// not cosmetic: pCloud's new-device protection answers a bare userinfo
    /// login with 1022 ("Please provide 'code'.") and never dispatches that
    /// code anywhere, while a login that introduces itself the way pCloud's
    /// own clients do — device, deviceid, os — is let straight through
    /// (measured against the real API, 2026-08-24). `code` still rides along
    /// when a challenge does come back.
    public static func login(username: String, password: String, code: String? = nil) -> PCloudRequest {
        var query = [
            URLQueryItem(name: "getauth", value: "1"),
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
            // 63072000 seconds — two years, pCloud's maximum. The phone is away
            // from home for weeks and a re-login needs a password we do not keep.
            URLQueryItem(name: "authexpire", value: "63072000"),
            URLQueryItem(name: "device", value: "WarmGun"),
            URLQueryItem(name: "deviceid", value: "warmgun-phone"),
            URLQueryItem(name: "os", value: "4"),
            URLQueryItem(name: "timeformat", value: "timestamp"),
        ]
        if let code {
            query.append(URLQueryItem(name: "code", value: code))
        }
        return PCloudRequest(method: "login", query: query)
    }

    /// The second leg of a two-factor login: the challenge token from the
    /// first leg's error, plus the code the user got — from their authenticator
    /// app, an SMS, or a notification pushed to another logged-in pCloud app.
    /// `trustDevice` asks pCloud not to challenge this phone again.
    public static func tfaLogin(token: String, code: String, trustDevice: Bool, isRecovery: Bool) -> PCloudRequest {
        PCloudRequest(method: isRecovery ? "tfa_loginwithrecoverycode" : "tfa_login", query: [
            URLQueryItem(name: "getauth", value: "1"),
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "trustdevice", value: trustDevice ? "1" : "0"),
            URLQueryItem(name: "authexpire", value: "63072000"),
            URLQueryItem(name: "device", value: "WarmGun"),
            URLQueryItem(name: "timeformat", value: "timestamp"),
        ])
    }

    public static func tfaSendCodeViaSMS(token: String) -> PCloudRequest {
        PCloudRequest(method: "tfa_sendcodeviasms", query: [URLQueryItem(name: "token", value: token)])
    }

    /// Pushes the code to every OTHER logged-in pCloud app — the desktop drive
    /// on the Mac or PC — which is the channel that still works when neither
    /// SMS nor an authenticator is at hand.
    public static func tfaSendCodeViaNotification(token: String) -> PCloudRequest {
        PCloudRequest(method: "tfa_sendcodeviasysnotification", query: [URLQueryItem(name: "token", value: token)])
    }

    /// Does the token still work? The one call the app makes on launch before
    /// it trusts what the Keychain handed it.
    public static func userInfo(auth: String) -> PCloudRequest {
        PCloudRequest(method: "userinfo", query: [
            URLQueryItem(name: "timeformat", value: "timestamp"),
            URLQueryItem(name: "auth", value: auth),
        ])
    }

    /// The whole index in one call. Recursive because the library is a fixed
    /// three-deep tree and a per-folder walk would be hundreds of round-trips
    /// on a phone connection; the listing already carries every clip's size,
    /// duration, codec and dimensions, so nothing is ever probed afterwards.
    public static func listFolder(path: String, auth: String) -> PCloudRequest {
        PCloudRequest(method: "listfolder", query: [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "recursive", value: "1"),
            URLQueryItem(name: "timeformat", value: "timestamp"),
            URLQueryItem(name: "auth", value: auth),
        ])
    }

    /// The folder skeleton alone — no files — which is all library discovery
    /// needs and a fraction of the full listing's size. Non-recursive when the
    /// server refuses depth: pCloud answers a recursive listing of the ROOT
    /// with 1101 "Invalid request" (a 2025-era server change), so the hunt
    /// descends one shallow rung at a time from there.
    public static func listFolders(path: String, auth: String, recursive: Bool = true) -> PCloudRequest {
        var query = [URLQueryItem(name: "path", value: path)]
        if recursive {
            query.append(URLQueryItem(name: "recursive", value: "1"))
        }
        query.append(contentsOf: [
            URLQueryItem(name: "nofiles", value: "1"),
            URLQueryItem(name: "timeformat", value: "timestamp"),
            URLQueryItem(name: "auth", value: auth),
        ])
        return PCloudRequest(method: "listfolder", query: query)
    }

    /// A short-lived direct download URL. Keyed by file id, not path, because
    /// the weird gesture renames files out from under any path we cached.
    public static func fileLink(fileID: Int64, auth: String) -> PCloudRequest {
        PCloudRequest(method: "getfilelink", query: [
            URLQueryItem(name: "fileid", value: String(fileID)),
            URLQueryItem(name: "timeformat", value: "timestamp"),
            URLQueryItem(name: "auth", value: auth),
        ])
    }

    /// The weird gesture: move a clip's upscale into `2_outbox/kinda_weird`,
    /// which is what arms the desktop's purge of the original on its next run.
    /// `topath` is a full destination path including the filename — pCloud
    /// treats move and rename as the same operation.
    public static func renameFile(fileID: Int64, toPath: String, auth: String) -> PCloudRequest {
        PCloudRequest(method: "renamefile", query: [
            URLQueryItem(name: "fileid", value: String(fileID)),
            URLQueryItem(name: "topath", value: toPath),
            URLQueryItem(name: "timeformat", value: "timestamp"),
            URLQueryItem(name: "auth", value: auth),
        ])
    }

    /// The same move named by path, for the one file the index keeps no id
    /// for: the upscale twin the weird gesture parks. pCloud's renamefile takes
    /// either identity.
    public static func renameFile(path: String, toPath: String, auth: String) -> PCloudRequest {
        PCloudRequest(method: "renamefile", query: [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "topath", value: toPath),
            URLQueryItem(name: "timeformat", value: "timestamp"),
            URLQueryItem(name: "auth", value: auth),
        ])
    }

    /// Idempotent by design: the journal folder is created on every upload
    /// rather than remembered, so a fresh install and a hundredth run take the
    /// same path and neither has to ask whether it exists.
    public static func createFolderIfNotExists(path: String, auth: String) -> PCloudRequest {
        PCloudRequest(method: "createfolderifnotexists", query: [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "timeformat", value: "timestamp"),
            URLQueryItem(name: "auth", value: auth),
        ])
    }

    /// The query half of an upload; the multipart body is the app's, because a
    /// file's bytes are exactly the thing this package has no business holding.
    /// `nopartial` makes a truncated upload vanish rather than land half-written,
    /// and `renameifexists=0` overwrites the previous journal instead of piling
    /// numbered copies next to it.
    public static func uploadFile(folderPath: String, filename: String, auth: String) -> PCloudRequest {
        PCloudRequest(method: "uploadfile", query: [
            URLQueryItem(name: "path", value: folderPath),
            URLQueryItem(name: "filename", value: filename),
            URLQueryItem(name: "nopartial", value: "1"),
            URLQueryItem(name: "renameifexists", value: "0"),
            URLQueryItem(name: "timeformat", value: "timestamp"),
            URLQueryItem(name: "auth", value: auth),
        ])
    }

    /// The whole sidecar corpus in one body: getzip streams a folder as a
    /// single zip, where fetching its files one by one would be thousands of
    /// round-trips for a megabyte and a half.
    public static func getZip(path: String, auth: String) -> PCloudRequest {
        PCloudRequest(method: "getzip", query: [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "timeformat", value: "timestamp"),
            URLQueryItem(name: "auth", value: auth),
        ])
    }

    /// Unwrap one response. pCloud answers HTTP 200 to everything, so the only
    /// thing that says whether a call worked is the `result` field inside the
    /// body — which makes this the single door every response comes through.
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        // Dates need no decoder strategy: every request carries
        // timeformat=timestamp and the response types read their own fields as
        // unix seconds, so they are correct through ANY decoder. The decoder is
        // built per call because JSONDecoder is a class and the prefetcher
        // decodes on several threads at once.
        let decoder = JSONDecoder()
        switch try decoder.decode(Envelope<T>.self, from: data) {
        case .success(let payload): return payload
        case .failure(let error): throw error
        }
    }

    /// The `result` field and the payload share one JSON object, so they are read
    /// in one pass: the recursive listing is megabytes, and parsing it twice —
    /// once to check `result`, once for the contents — would double the most
    /// expensive decode the app ever does.
    private enum Envelope<Payload: Decodable>: Decodable {
        case success(Payload)
        case failure(PCloudError)

        private enum CodingKeys: String, CodingKey {
            case result, error, token, tfatype, hasdevices
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let result = try container.decode(Int.self, forKey: .result)
            guard result == 0 else {
                let message = try container.decodeIfPresent(String.self, forKey: .error)
                self = .failure(PCloudError(code: result, message: message ?? "",
                                            token: try? container.decodeIfPresent(String.self, forKey: .token),
                                            tfaType: try? container.decodeIfPresent(Int.self, forKey: .tfatype),
                                            hasDevices: try? container.decodeIfPresent(Bool.self, forKey: .hasdevices)))
                return
            }
            self = .success(try Payload(from: decoder))
        }
    }
}

/// A pCloud call that answered HTTP 200 and still failed. The code is the
/// four-digit one from the body; the two questions the app actually asks of it
/// are whether to re-login and whether to back off, so they are properties here
/// rather than magic numbers scattered through the transport.
public struct PCloudError: Error, LocalizedError, Equatable, Sendable {
    public let code: Int
    public let message: String
    /// A two-factor challenge rides inside the error envelope: the token to
    /// exchange via `tfa_login`, which factor the account uses, and whether
    /// other logged-in pCloud apps exist to push a code to.
    public let token: String?
    public let tfaType: Int?
    public let hasDevices: Bool?

    /// The server's own words, because they are the only clue the user gets —
    /// without this conformance Foundation shows "operation couldn't be
    /// completed", which reads as nothing happening at all.
    public var errorDescription: String? { "pCloud: \(message) (code \(code))" }

    public init(code: Int, message: String,
                token: String? = nil, tfaType: Int? = nil, hasDevices: Bool? = nil) {
        self.code = code
        self.message = message
        self.token = token
        self.tfaType = tfaType
        self.hasDevices = hasDevices
    }

    /// 1000 (no auth given) and 2000 (log in failed) both mean the token is no
    /// good: retrying with it can only fail again, so the app goes to login.
    public var isLoginRequired: Bool { code == 1000 || code == 2000 }

    /// The whole 4xxx band is pCloud saying "too many, too fast" — the one
    /// class of failure where the same call will work if it simply waits.
    public var isRateLimited: Bool { (4000...4999).contains(code) }
}

/// Where one clip can be fetched from, until it can't. pCloud hands back the
/// pieces rather than a URL — a list of hosts serving the file and a path that
/// is only meaningful on one of them — and the link stops working at `expires`,
/// which is why the cache that holds it has to know when to stop trusting it.
public struct FileLinkResponse: Decodable, Equatable, Sendable {
    public let hosts: [String]
    public let path: String
    public let expires: Date

    public init(hosts: [String], path: String, expires: Date) {
        self.hosts = hosts
        self.path = path
        self.expires = expires
    }

    private enum CodingKeys: String, CodingKey { case hosts, path, expires }

    /// `expires` is unix seconds on the wire (`timeformat=timestamp` rides on
    /// every request) and is read as such HERE, not via a decoder setting: a
    /// link decoded by any plain JSONDecoder must not silently land thirty-one
    /// years out and never expire.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hosts = try container.decode([String].self, forKey: .hosts)
        path = try container.decode(String.self, forKey: .path)
        expires = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .expires))
    }

    /// The first host is the one pCloud considers nearest; the rest are
    /// fallbacks the app has no reason to use unless the first refuses.
    public var url: URL? {
        guard let host = hosts.first else { return nil }
        // Foundation percent-encodes what it must, except the two characters
        // that would re-shape the URL: a raw "#" reads as a fragment and a raw
        // "?" as a query, silently truncating the path into a 404.
        let safePath = path
            .replacingOccurrences(of: "#", with: "%23")
            .replacingOccurrences(of: "?", with: "%3F")
        return URL(string: "https://\(host)\(safePath)")
    }
}

/// One node of a `listfolder` tree — a folder with `contents`, or a file with
/// everything pCloud already knows about it. The field names are pCloud's, not
/// Swift's, deliberately: this type is the wire shape, and the moment it is
/// renamed the mapping to `LibraryFile` stops being obvious. Nearly everything
/// is optional because pCloud sends only what applies to the node at hand.
public struct PCloudEntry: Decodable, Equatable, Sendable {
    public let name: String
    public let isfolder: Bool
    public let fileid: Int64?
    public let folderid: Int64?
    public let size: Int64?
    public let modified: Date?
    /// Seconds of video. pCloud quotes it — `"5.03"` — so this is read from a
    /// string or a number, and is nil when it is missing or unreadable rather
    /// than failing the whole listing over one clip it could not probe.
    public let duration: Double?
    public let videocodec: String?
    public let width: Int?
    public let height: Int?
    public let contents: [PCloudEntry]?

    public init(name: String, isfolder: Bool, fileid: Int64? = nil, folderid: Int64? = nil,
                size: Int64? = nil, modified: Date? = nil, duration: Double? = nil,
                videocodec: String? = nil, width: Int? = nil, height: Int? = nil,
                contents: [PCloudEntry]? = nil) {
        self.name = name
        self.isfolder = isfolder
        self.fileid = fileid
        self.folderid = folderid
        self.size = size
        self.modified = modified
        self.duration = duration
        self.videocodec = videocodec
        self.width = width
        self.height = height
        self.contents = contents
    }

    private enum CodingKeys: String, CodingKey {
        case name, isfolder, fileid, folderid, size, modified, duration, videocodec, width, height, contents
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        isfolder = try container.decode(Bool.self, forKey: .isfolder)
        fileid = try container.decodeIfPresent(Int64.self, forKey: .fileid)
        folderid = try container.decodeIfPresent(Int64.self, forKey: .folderid)
        size = try container.decodeIfPresent(Int64.self, forKey: .size)
        // Unix seconds read directly (see FileLinkResponse.init(from:)): the
        // date must be right through any decoder, not just the one decode()
        // builds. A malformed value reads as absent rather than sinking the
        // whole multi-megabyte listing.
        modified = (try? container.decodeIfPresent(Double.self, forKey: .modified))
            .flatMap { $0 }.map(Date.init(timeIntervalSince1970:))
        if let seconds = try? container.decodeIfPresent(Double.self, forKey: .duration) {
            duration = seconds
        } else if let text = try? container.decodeIfPresent(String.self, forKey: .duration) {
            duration = Double(text)
        } else {
            duration = nil
        }
        videocodec = try container.decodeIfPresent(String.self, forKey: .videocodec)
        width = try container.decodeIfPresent(Int.self, forKey: .width)
        height = try container.decodeIfPresent(Int.self, forKey: .height)
        contents = try container.decodeIfPresent([PCloudEntry].self, forKey: .contents)
    }
}

public extension PCloudEntry {
    /// The tree as a flat list of files, which is the only shape the index ever
    /// wants. Paths are relative to whatever folder was listed — the receiver's
    /// own name is left out — so the library root stays a setting the app can
    /// change without rewriting every stored path, favorite and watch count.
    func flattenedFiles() -> [LibraryFile] {
        var files: [LibraryFile] = []
        collectFiles(under: "", into: &files)
        return files
    }

    private func collectFiles(under prefix: String, into files: inout [LibraryFile]) {
        for entry in contents ?? [] {
            let path = prefix.isEmpty ? entry.name : "\(prefix)/\(entry.name)"
            if entry.isfolder {
                entry.collectFiles(under: path, into: &files)
            } else if let fileID = entry.fileid, let size = entry.size {
                // No id or no size means nothing can be fetched or budgeted for
                // this entry, so it is not a library file however it is named.
                files.append(LibraryFile(path: path,
                                         fileID: fileID,
                                         size: size,
                                         // A missing timestamp sorts oldest under
                                         // "Latest" rather than jumping the queue.
                                         modified: entry.modified ?? .distantPast,
                                         duration: entry.duration,
                                         videoCodec: entry.videocodec,
                                         width: entry.width,
                                         height: entry.height))
            }
        }
    }
}

/// The whole index in one body: `listfolder` wraps the tree in `metadata`.
public struct ListFolderResponse: Decodable, Equatable, Sendable {
    public let metadata: PCloudEntry

    public init(metadata: PCloudEntry) {
        self.metadata = metadata
    }
}

/// What a bare `userinfo` (no `getauth`) answers for a stored token: the
/// account, but no token — pCloud only mints one when `getauth=1` is asked for,
/// so decoding this as `LoginResponse` would read every valid token as failure.
public struct UserInfoResponse: Decodable, Equatable, Sendable {
    public let email: String?
    public let userid: Int64

    public init(email: String?, userid: Int64) {
        self.email = email
        self.userid = userid
    }
}

/// What a successful `userinfo?getauth=1` hands back. The token is the whole
/// point; the email and id are what the settings screen shows so the owner can
/// see which account the phone is actually talking to.
public struct LoginResponse: Decodable, Equatable, Sendable {
    public let auth: String
    public let email: String?
    public let userid: Int64

    public init(auth: String, email: String?, userid: Int64) {
        self.auth = auth
        self.email = email
        self.userid = userid
    }
}
