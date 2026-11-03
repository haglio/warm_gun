import Foundation
import Testing
@testable import WarmGunKit

@Suite struct LinkCacheTests {
    static let linkOne = URL(string: "https://edef1.pcloud.com/cBZ7q0Zwarmgun0ZvideoOneZ/video-one.mp4")!
    static let noon = Date(timeIntervalSince1970: 1_787_654_400)

    @Test func handsBackALinkThatIsStillGood() {
        var cache = LinkCache()
        cache.store(url: Self.linkOne, for: 90_210, expires: Self.noon.addingTimeInterval(3600))
        #expect(cache.url(for: 90_210, now: Self.noon) == Self.linkOne)
    }
}

extension LinkCacheTests {
    @Test func dropsOneLinkOnDemandSoAFailedFetchCanReLinkAndRetry() {
        var cache = LinkCache()
        cache.store(url: Self.linkOne, for: 90_210, expires: Self.noon.addingTimeInterval(3600))
        cache.forget(90_210)
        #expect(cache.url(for: 90_210, now: Self.noon) == nil)
        #expect(cache == LinkCache())
    }
}

extension LinkCacheTests {
    @Test func withholdsALinkThatWouldExpireMidDownload() {
        var cache = LinkCache()
        cache.store(url: Self.linkOne, for: 90_210, expires: Self.noon.addingTimeInterval(59))
        #expect(cache.url(for: 90_210, now: Self.noon) == nil)
        #expect(cache.url(for: 90_210, now: Self.noon, margin: 10) == Self.linkOne)
    }
}
