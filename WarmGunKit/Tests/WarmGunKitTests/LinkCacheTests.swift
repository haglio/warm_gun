import Foundation
import Testing
@testable import WarmGunKit

/// `getfilelink` costs a round-trip the prefetcher would otherwise pay for
/// every clip in its window, so links are kept until they go stale. Every test
/// here fixes a clock rather than reading one: expiry is the whole subject.
@Suite struct LinkCacheTests {
    static let linkOne = URL(string: "https://edef1.pcloud.com/cBZ7q0Zwarmgun0ZclipOneZ/clip-one.mp4")!
    static let linkTwo = URL(string: "https://c210.pcloud.com/cBZ8r4Zwarmgun0ZclipTwoZ/clip-two.mp4")!
    /// Any instant will do as long as the tests share it; this one is a round
    /// number of seconds so the arithmetic in each test reads at a glance.
    static let noon = Date(timeIntervalSince1970: 1_787_654_400)

    @Test func handsBackALinkThatIsStillGood() {
        var cache = LinkCache()
        cache.store(url: Self.linkOne, for: 90_210, expires: Self.noon.addingTimeInterval(3600))
        #expect(cache.url(for: 90_210, now: Self.noon) == Self.linkOne)
    }
}

extension LinkCacheTests {
    @Test func purgeEvictsTheDeadLinksAndLeavesTheLiveOnesAlone() {
        var cache = LinkCache()
        cache.store(url: Self.linkOne, for: 90_210, expires: Self.noon.addingTimeInterval(-1))
        cache.store(url: Self.linkTwo, for: 90_211, expires: Self.noon.addingTimeInterval(3600))
        cache.purge(now: Self.noon)

        // Comparing the whole cache, not just asking for the links: an expired
        // entry that merely stops answering is still holding memory, and a
        // session that runs for hours re-links thousands of clips.
        var survivor = LinkCache()
        survivor.store(url: Self.linkTwo, for: 90_211, expires: Self.noon.addingTimeInterval(3600))
        #expect(cache == survivor)
        // Purge is about death, not the download margin — a link with seconds
        // left is still a link, and the caller's margin decides its usefulness.
        #expect(cache.url(for: 90_211, now: Self.noon) == Self.linkTwo)
    }
}

extension LinkCacheTests {
    @Test func dropsOneLinkOnDemandSoAFailedFetchCanReLinkAndRetry() {
        var cache = LinkCache()
        cache.store(url: Self.linkOne, for: 90_210, expires: Self.noon.addingTimeInterval(3600))
        // A download can fail on a link the cache still believes in — pCloud
        // can retire a host early. That means "ask again", not "clip is gone",
        // so the app throws this one link away and re-links.
        cache.forget(90_210)
        #expect(cache.url(for: 90_210, now: Self.noon) == nil)
        #expect(cache == LinkCache())
    }
}

extension LinkCacheTests {
    @Test func withholdsALinkThatWouldExpireMidDownload() {
        var cache = LinkCache()
        cache.store(url: Self.linkOne, for: 90_210, expires: Self.noon.addingTimeInterval(59))
        // A link with a minute left is not worth starting a fetch on: the
        // margin exists so a 2 MB download cannot outlive the URL it is using.
        #expect(cache.url(for: 90_210, now: Self.noon) == nil)
        // The margin is a caller's choice, though — a link good for another
        // 59 seconds is fine for someone who only wants to build a request.
        #expect(cache.url(for: 90_210, now: Self.noon, margin: 10) == Self.linkOne)
    }
}
