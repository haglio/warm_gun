import Foundation

public struct PCloudRequest: Equatable, Sendable {
    public let method: String
    public let query: [URLQueryItem]

    public init(method: String, query: [URLQueryItem]) {
        self.method = method
        self.query = query
    }

    public func url(origin: URL) -> URL {
        var components = URLComponents()
        components.scheme = origin.scheme ?? "https"
        components.host = origin.host
        components.port = origin.port
        components.path = "/" + method
        // URLComponents leaves "+" unescaped, and pCloud reads a raw "+" in a value as a space.
        components.percentEncodedQuery = query.isEmpty ? nil : query.map { item in
            let name = Self.escape(item.name)
            guard let value = item.value else { return name }
            return "\(name)=\(Self.escape(value))"
        }.joined(separator: "&")
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

/// `timeformat=timestamp` rides along because pCloud's default date is an RFC-1123 string.
public enum PCloudAPI {
    /// pCloud's new-device protection answers a bare `userinfo` login with 1022 and never sends the
    /// code; a `login` naming device, deviceid and os is let through.
    public static func login(username: String, password: String, code: String? = nil) -> PCloudRequest {
        var query = [
            URLQueryItem(name: "getauth", value: "1"),
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
            // Two years, pCloud's maximum.
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

    public static func tfaSendCodeViaNotification(token: String) -> PCloudRequest {
        PCloudRequest(method: "tfa_sendcodeviasysnotification", query: [URLQueryItem(name: "token", value: token)])
    }

    public static func listFolder(path: String, auth: String, recursive: Bool = true) -> PCloudRequest {
        listing(path: path, auth: auth, recursive: recursive, nofiles: false)
    }

    /// pCloud answers a recursive listing of the root with 1101.
    public static func listFolders(path: String, auth: String, recursive: Bool = true) -> PCloudRequest {
        listing(path: path, auth: auth, recursive: recursive, nofiles: true)
    }

    private static func listing(path: String, auth: String, recursive: Bool, nofiles: Bool) -> PCloudRequest {
        var query = [URLQueryItem(name: "path", value: path)]
        if recursive {
            query.append(URLQueryItem(name: "recursive", value: "1"))
        }
        if nofiles {
            query.append(URLQueryItem(name: "nofiles", value: "1"))
        }
        query.append(contentsOf: [
            URLQueryItem(name: "timeformat", value: "timestamp"),
            URLQueryItem(name: "auth", value: auth),
        ])
        return PCloudRequest(method: "listfolder", query: query)
    }

    public static func fileLink(fileID: Int64, auth: String) -> PCloudRequest {
        PCloudRequest(method: "getfilelink", query: [
            URLQueryItem(name: "fileid", value: String(fileID)),
            URLQueryItem(name: "timeformat", value: "timestamp"),
            URLQueryItem(name: "auth", value: auth),
        ])
    }

    /// pCloud treats move and rename as one operation, and `topath` is a whole path with the filename.
    public static func renameFile(path: String, toPath: String, auth: String) -> PCloudRequest {
        PCloudRequest(method: "renamefile", query: [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "topath", value: toPath),
            URLQueryItem(name: "timeformat", value: "timestamp"),
            URLQueryItem(name: "auth", value: auth),
        ])
    }

    public static func createFolderIfNotExists(path: String, auth: String) -> PCloudRequest {
        PCloudRequest(method: "createfolderifnotexists", query: [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "timeformat", value: "timestamp"),
            URLQueryItem(name: "auth", value: auth),
        ])
    }

    /// pCloud's `nopartial` discards a truncated upload; `renameifexists=0` overwrites rather than
    /// numbering copies.
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

    /// pCloud answers HTTP 200 to everything; only `result` says whether a call worked.
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        // Built per call: JSONDecoder is a class and the prefetcher decodes on several threads.
        let decoder = JSONDecoder()
        switch try decoder.decode(Envelope<T>.self, from: data) {
        case .success(let payload): return payload
        case .failure(let error): throw error
        }
    }

    private enum Envelope<Payload: Decodable>: Decodable {
        case success(Payload)
        case failure(PCloudError)

        private enum CodingKeys: String, CodingKey {
            case result, error, token, hasdevices
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let result = try container.decode(Int.self, forKey: .result)
            guard result == 0 else {
                let message = try container.decodeIfPresent(String.self, forKey: .error)
                self = .failure(PCloudError(code: result, message: message ?? "",
                                            token: try? container.decodeIfPresent(String.self, forKey: .token),
                                            hasDevices: try? container.decodeIfPresent(Bool.self, forKey: .hasdevices)))
                return
            }
            self = .success(try Payload(from: decoder))
        }
    }
}

public struct PCloudError: Error, LocalizedError, Equatable, Sendable {
    public let code: Int
    public let message: String
    public let token: String?
    public let hasDevices: Bool?

    /// Without this conformance Foundation shows "operation couldn't be completed".
    public var errorDescription: String? { "pCloud: \(message) (code \(code))" }

    public init(code: Int, message: String, token: String? = nil, hasDevices: Bool? = nil) {
        self.code = code
        self.message = message
        self.token = token
        self.hasDevices = hasDevices
    }

    /// pCloud's 1000 (no auth given) and 2000 (log in failed) both mean the token is no good.
    public var isLoginRequired: Bool { code == 1000 || code == 2000 }
}

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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hosts = try container.decode([String].self, forKey: .hosts)
        path = try container.decode(String.self, forKey: .path)
        expires = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .expires))
    }

    /// pCloud lists its nearest host first.
    public var url: URL? {
        guard let host = hosts.first else { return nil }
        // Foundation percent-encodes all but "#" and "?", which would re-shape the URL.
        let safePath = path
            .replacingOccurrences(of: "#", with: "%23")
            .replacingOccurrences(of: "?", with: "%3F")
        return URL(string: "https://\(host)\(safePath)")
    }
}

/// The field names are pCloud's wire shape.
public struct PCloudEntry: Decodable, Equatable, Sendable {
    public let name: String
    public let isfolder: Bool
    public let fileid: Int64?
    public let folderid: Int64?
    public let size: Int64?
    public let modified: Date?
    /// pCloud quotes it (`"5.03"`), so this reads a string or a number.
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
                files.append(LibraryFile(path: path,
                                         fileID: fileID,
                                         size: size,
                                         modified: entry.modified ?? .distantPast,
                                         duration: entry.duration,
                                         videoCodec: entry.videocodec,
                                         width: entry.width,
                                         height: entry.height))
            }
        }
    }
}

public struct ListFolderResponse: Decodable, Equatable, Sendable {
    public let metadata: PCloudEntry

    public init(metadata: PCloudEntry) {
        self.metadata = metadata
    }
}

public struct LoginResponse: Decodable, Equatable, Sendable {
    public let auth: String

    public init(auth: String) {
        self.auth = auth
    }
}
