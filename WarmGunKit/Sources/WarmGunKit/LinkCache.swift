import Foundation

public struct LinkCache: Equatable, Sendable {
    private struct Link: Equatable {
        let url: URL
        let expires: Date
    }

    private var links: [Int64: Link] = [:]

    public init() {}

    public mutating func store(url: URL, for fileID: Int64, expires: Date) {
        links[fileID] = Link(url: url, expires: expires)
    }

    public mutating func forget(_ fileID: Int64) {
        links[fileID] = nil
    }

    public func url(for fileID: Int64, now: Date, margin: TimeInterval = 60) -> URL? {
        guard let link = links[fileID], link.expires > now.addingTimeInterval(margin) else { return nil }
        return link.url
    }
}
