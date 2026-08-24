import Foundation
import WarmGunKit

/// The transport to pCloud: turns the Kit's request descriptions into HTTP,
/// and its response types back out of the JSON. Nothing here decides what to
/// fetch — that is the prefetcher's — and nothing here knows the library's
/// shape — that is the Kit's.
actor PCloudClient {
    enum Failure: Error, LocalizedError {
        case badOrigin(String)
        case http(Int)
        case noLink

        var errorDescription: String? {
            switch self {
            case .badOrigin(let s): return "Not a usable API host: \(s)"
            case .http(let code): return "HTTP \(code)"
            case .noLink: return "pCloud returned no download host"
            }
        }
    }

    private let origin: URL
    private let auth: String
    private let session: URLSession

    /// `apiHost` is either a bare pCloud host (`api.pcloud.com`, reached over
    /// https) or a full origin such as `http://localhost:8765` for the local
    /// stand-in server used in development.
    init(apiHost: String, auth: String) throws {
        let text = apiHost.contains("://") ? apiHost : "https://\(apiHost)"
        guard let url = URL(string: text), url.host != nil else { throw Failure.badOrigin(apiHost) }
        origin = url
        self.auth = auth
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
    }

    static func login(apiHost: String, username: String, password: String) async throws -> LoginResponse {
        let client = try PCloudClient(apiHost: apiHost, auth: "")
        return try await client.call(PCloudAPI.login(username: username, password: password), as: LoginResponse.self)
    }

    func userInfo() async throws -> UserInfoResponse {
        try await call(PCloudAPI.userInfo(auth: auth), as: UserInfoResponse.self)
    }

    func listLibrary(path: String) async throws -> [LibraryFile] {
        let listing = try await call(PCloudAPI.listFolder(path: path, auth: auth), as: ListFolderResponse.self)
        return listing.metadata.flattenedFiles()
    }

    func fileLink(fileID: Int64) async throws -> FileLinkResponse {
        try await call(PCloudAPI.fileLink(fileID: fileID, auth: auth), as: FileLinkResponse.self)
    }

    func renameFile(fileID: Int64, toPath: String) async throws {
        _ = try await call(PCloudAPI.renameFile(fileID: fileID, toPath: toPath, auth: auth), as: Acknowledged.self)
    }

    func renameFile(path: String, toPath: String) async throws {
        _ = try await call(PCloudAPI.renameFile(path: path, toPath: toPath, auth: auth), as: Acknowledged.self)
    }

    func createFolderIfNotExists(path: String) async throws {
        _ = try await call(PCloudAPI.createFolderIfNotExists(path: path, auth: auth), as: Acknowledged.self)
    }

    /// Uploads `data` as `filename` into `folderPath`, replacing any file of
    /// that name (pCloud's `renameifexists=0`).
    func upload(data: Data, folderPath: String, filename: String) async throws {
        let url = PCloudAPI.uploadFile(folderPath: folderPath, filename: filename, auth: auth).url(origin: origin)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "warm-gun-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        let (response, http) = try await session.upload(for: request, from: body)
        try Self.check(http)
        _ = try PCloudAPI.decode(Acknowledged.self, from: response)
    }

    /// Downloads a content URL whole to a temporary file and returns it.
    /// The caller moves it into the cache; a partial file never lands there.
    func download(_ url: URL) async throws -> URL {
        let (tmp, response) = try await session.download(from: localized(url))
        do {
            try Self.check(response)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw error
        }
        return tmp
    }

    /// pCloud's content links are always https; the local stand-in serves the
    /// same links over plain http, so a link back to the origin's own host
    /// takes the origin's scheme.
    private func localized(_ url: URL) -> URL {
        guard origin.scheme == "http", url.host == origin.host,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.scheme = "http"
        return components.url ?? url
    }

    private func call<T: Decodable>(_ request: PCloudRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await session.data(from: request.url(origin: origin))
        try Self.check(response)
        return try PCloudAPI.decode(type, from: data)
    }

    private static func check(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.http(http.statusCode)
        }
    }

    /// A response whose only content of interest is `result == 0`.
    private struct Acknowledged: Decodable {}
}
