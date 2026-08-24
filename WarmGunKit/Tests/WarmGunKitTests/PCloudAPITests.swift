import Foundation
import Testing
@testable import WarmGunKit

@Suite struct PCloudAPITests {
    @Test func buildsTheMethodURLAndSurvivesTheCharactersAPasswordCanCarry() throws {
        let request = PCloudRequest(method: "userinfo", query: [
            URLQueryItem(name: "username", value: "gunner@example.test"),
            URLQueryItem(name: "password", value: "a&b+c d"),
        ])
        let url = request.url(host: "api.pcloud.com")
        #expect(url.scheme == "https")
        #expect(url.host == "api.pcloud.com")
        #expect(url.path == "/userinfo")
        // A "+" left raw would reach pCloud as a space and a "&" as a field
        // break, so both have to come back out of the wire form unchanged.
        let parsed = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parsed.queryItems == request.query)
        let encoded = try #require(parsed.percentEncodedQuery)
        #expect(encoded.contains("%2B"))
        #expect(encoded.contains("%26"))
    }
}

extension PCloudAPITests {
    @Test func logsInAsAClientWithADeviceIdentityAndNeverKeepsThePassword() {
        // The `login` method, not `userinfo?getauth=1`: pCloud's new-device
        // protection answers the latter with "provide 'code'" and never sends
        // the code anywhere, while a login that introduces itself as a client
        // (device, deviceid, os) is let straight through — measured against the
        // real API, 2026-08-24.
        let request = PCloudAPI.login(username: "gunner@example.test", password: "a&b+c d")
        #expect(request.method == "login")
        #expect(request.query == [
            URLQueryItem(name: "getauth", value: "1"),
            URLQueryItem(name: "username", value: "gunner@example.test"),
            URLQueryItem(name: "password", value: "a&b+c d"),
            // Two years is pCloud's ceiling: the phone is away from home for
            // weeks at a time and a re-login needs a password we do not store.
            URLQueryItem(name: "authexpire", value: "63072000"),
            URLQueryItem(name: "device", value: "WarmGun"),
            URLQueryItem(name: "deviceid", value: "warmgun-phone"),
            URLQueryItem(name: "os", value: "4"),
            URLQueryItem(name: "timeformat", value: "timestamp"),
        ])
    }
}

extension PCloudAPITests {
    @Test func checksAStoredTokenWithTheBarestUserinfoCall() {
        let request = PCloudAPI.userInfo(auth: "token-abc")
        #expect(request.method == "userinfo")
        #expect(request.query == [
            URLQueryItem(name: "timeformat", value: "timestamp"),
            URLQueryItem(name: "auth", value: "token-abc"),
        ])
    }
}

extension PCloudAPITests {
    @Test func pullsTheWholeLibraryTreeInOneRecursiveListing() {
        let request = PCloudAPI.listFolder(path: "/lib/AI", auth: "token-abc")
        #expect(request.method == "listfolder")
        #expect(request.query == [
            URLQueryItem(name: "path", value: "/lib/AI"),
            // One recursive call is the whole index: it also carries each
            // clip's size, duration, codec and dimensions, so nothing is probed.
            URLQueryItem(name: "recursive", value: "1"),
            URLQueryItem(name: "timeformat", value: "timestamp"),
            URLQueryItem(name: "auth", value: "token-abc"),
        ])
    }
}

extension PCloudAPITests {
    @Test func asksForADownloadLinkByFileIDRatherThanByPath() {
        // File ids survive a rename; paths do not, and the weird gesture renames.
        let request = PCloudAPI.fileLink(fileID: 90_210, auth: "token-abc")
        #expect(request.method == "getfilelink")
        #expect(request.query == [
            URLQueryItem(name: "fileid", value: "90210"),
            URLQueryItem(name: "timeformat", value: "timestamp"),
            URLQueryItem(name: "auth", value: "token-abc"),
        ])
    }
}

extension PCloudAPITests {
    @Test func movesAnUpscaleByGivingRenamefileAWholeDestinationPath() {
        // This is the weird gesture on the wire, and it is as irreversible here
        // as it is on the desktop: `topath` carries the filename, not just the
        // folder, so the move and the rename are one call.
        let request = PCloudAPI.renameFile(fileID: 90_210,
                                           toPath: "/lib/2_outbox/kinda_weird/clip-one_topaz.mp4",
                                           auth: "token-abc")
        #expect(request.method == "renamefile")
        #expect(request.query == [
            URLQueryItem(name: "fileid", value: "90210"),
            URLQueryItem(name: "topath", value: "/lib/2_outbox/kinda_weird/clip-one_topaz.mp4"),
            URLQueryItem(name: "timeformat", value: "timestamp"),
            URLQueryItem(name: "auth", value: "token-abc"),
        ])
    }
}

extension PCloudAPITests {
    @Test func makesTheJournalFolderWithoutCaringWhetherItIsAlreadyThere() {
        let request = PCloudAPI.createFolderIfNotExists(path: "/WarmGun", auth: "token-abc")
        #expect(request.method == "createfolderifnotexists")
        #expect(request.query == [
            URLQueryItem(name: "path", value: "/WarmGun"),
            URLQueryItem(name: "timeformat", value: "timestamp"),
            URLQueryItem(name: "auth", value: "token-abc"),
        ])
    }
}

extension PCloudAPITests {
    @Test func uploadsTheJournalWholeAndOverTheOldOneRatherThanBesideIt() {
        let request = PCloudAPI.uploadFile(folderPath: "/WarmGun", filename: "warm-gun-journal.jsonl", auth: "token-abc")
        #expect(request.method == "uploadfile")
        #expect(request.query == [
            URLQueryItem(name: "path", value: "/WarmGun"),
            URLQueryItem(name: "filename", value: "warm-gun-journal.jsonl"),
            // nopartial: a truncated upload is discarded rather than stored, so
            // the journal is never half a file. renameifexists=0: replace the
            // previous upload instead of accumulating "(1)" copies beside it.
            URLQueryItem(name: "nopartial", value: "1"),
            URLQueryItem(name: "renameifexists", value: "0"),
            URLQueryItem(name: "timeformat", value: "timestamp"),
            URLQueryItem(name: "auth", value: "token-abc"),
        ])
    }
}

extension PCloudAPITests {
    @Test func readsTheTokenOutOfASuccessfulLoginEnvelope() throws {
        let json = Data("""
        {"result": 0, "auth": "tok-9f3c", "email": "gunner@example.test", "userid": 4820199, "emailverified": true}
        """.utf8)
        let response = try PCloudAPI.decode(LoginResponse.self, from: json)
        #expect(response == LoginResponse(auth: "tok-9f3c", email: "gunner@example.test", userid: 4_820_199))
    }
}

extension PCloudAPITests {
    @Test func turnsAFailedResultIntoAnErrorEvenThoughTheHTTPStatusWas200() throws {
        let json = Data(#"{"result": 2000, "error": "Log in failed."}"#.utf8)
        let error = try #require(throws: PCloudError.self) {
            try PCloudAPI.decode(LoginResponse.self, from: json)
        }
        #expect(error == PCloudError(code: 2000, message: "Log in failed."))
        // 2000 is the app's cue to send the owner back to the login screen rather
        // than to retry, which is what it would do for anything else.
        #expect(error.isLoginRequired)
        #expect(!error.isRateLimited)
    }
}

extension PCloudAPITests {
    @Test func assemblesADownloadURLOutOfTheHostAndPathGetfilelinkHandsBack() throws {
        // getfilelink answers with the pieces, never the URL: a host list to
        // choose from and a path that is only valid on one of them.
        let json = Data("""
        {"result": 0, "dwltag": "7Qm2vXpLrK", "hash": 4471209983314, "size": 2295611,
         "expires": 1787654400, "path": "/cBZ7q0Zwarmgun0ZclipOneZ/clip-one.mp4",
         "hosts": ["edef1.pcloud.com", "c210.pcloud.com"]}
        """.utf8)
        let response = try PCloudAPI.decode(FileLinkResponse.self, from: json)
        #expect(response.hosts == ["edef1.pcloud.com", "c210.pcloud.com"])
        #expect(response.path == "/cBZ7q0Zwarmgun0ZclipOneZ/clip-one.mp4")
        // timeformat=timestamp, so the expiry arrives as plain unix seconds.
        #expect(response.expires == Date(timeIntervalSince1970: 1_787_654_400))
        #expect(response.url == URL(string: "https://edef1.pcloud.com/cBZ7q0Zwarmgun0ZclipOneZ/clip-one.mp4"))
    }
}

extension PCloudAPITests {
    /// One recursive `listfolder` body, shaped the way the library is: sources
    /// under the root, orientations under each source, clips under those, with
    /// a stray non-video sitting where the sorter left it.
    static let listing = Data("""
    {"result": 0, "metadata": {"name": "AI", "isfolder": true, "folderid": 10100, "contents": [
      {"name": "alpha", "isfolder": true, "folderid": 10101, "contents": [
        {"name": "portrait", "isfolder": true, "folderid": 10102, "contents": [
          {"name": "clip-one.mp4", "isfolder": false, "fileid": 90210, "size": 2295611,
           "modified": 1723456789, "contenttype": "video/mp4", "category": 2,
           "duration": "5.03", "videocodec": "h264", "width": 720, "height": 1280},
          {"name": "clip-two.mp4", "isfolder": false, "fileid": 90211, "size": 1884210,
           "modified": 1723456999, "contenttype": "video/mp4", "category": 2,
           "videocodec": "h264", "width": 720, "height": 1280}
        ]}
      ]},
      {"name": "beta", "isfolder": true, "folderid": 10103, "contents": [
        {"name": "landscape", "isfolder": true, "folderid": 10104, "contents": [
          {"name": "clip-three.mp4", "isfolder": false, "fileid": 90212, "size": 3120044,
           "modified": 1723457400, "contenttype": "video/mp4", "category": 2,
           "duration": "9.5", "videocodec": "hevc", "width": 1920, "height": 1080}
        ]}
      ]},
      {"name": "sorter-notes.txt", "isfolder": false, "fileid": 90213, "size": 84,
       "modified": 1723457500, "contenttype": "text/plain", "category": 0}
    ]}}
    """.utf8)

    @Test func readsTheWholeListingTreeIncludingTheDurationPCloudSendsAsAString() throws {
        let response = try PCloudAPI.decode(ListFolderResponse.self, from: Self.listing)
        let root = response.metadata
        #expect(root.name == "AI")
        #expect(root.isfolder)
        #expect(root.folderid == 10100)
        #expect(root.fileid == nil)
        #expect(root.contents?.count == 3)

        let clip = try #require(root.contents?.first?.contents?.first?.contents?.first)
        #expect(clip.name == "clip-one.mp4")
        #expect(!clip.isfolder)
        #expect(clip.fileid == 90_210)
        #expect(clip.size == 2_295_611)
        #expect(clip.modified == Date(timeIntervalSince1970: 1_723_456_789))
        // pCloud quotes the duration — "5.03", not 5.03 — which a plain
        // `Double?` would reject outright and take the whole listing down with it.
        #expect(clip.duration == 5.03)
        #expect(clip.videocodec == "h264")
        #expect(clip.width == 720)
        #expect(clip.height == 1280)

        // No duration on this one: pCloud omits the field for anything it did
        // not manage to probe, and that is not a reason to drop the clip.
        let second = try #require(root.contents?.first?.contents?.first?.contents?.last)
        #expect(second.duration == nil)
    }
}

extension PCloudAPITests {
    @Test func flattensTheTreeIntoLibraryRelativePathsInListingOrder() throws {
        let response = try PCloudAPI.decode(ListFolderResponse.self, from: Self.listing)
        let files = response.metadata.flattenedFiles()
        // Depth-first, in the order pCloud listed it, and relative to the
        // folder that was listed — the root's own name is not part of any path,
        // because the library root is a setting and the paths outlive it.
        #expect(files.map(\.path) == [
            "alpha/portrait/clip-one.mp4",
            "alpha/portrait/clip-two.mp4",
            "beta/landscape/clip-three.mp4",
            "sorter-notes.txt",
        ])
        #expect(files.first == LibraryFile(path: "alpha/portrait/clip-one.mp4",
                                           fileID: 90_210,
                                           size: 2_295_611,
                                           modified: Date(timeIntervalSince1970: 1_723_456_789),
                                           duration: 5.03,
                                           videoCodec: "h264",
                                           width: 720,
                                           height: 1280))
    }
}

extension PCloudAPITests {
    @Test func leavesOutWhatCannotBeFetchedAndDatesTheUndatedToTheDawnOfTime() {
        let root = PCloudEntry(name: "AI", isfolder: true, folderid: 10100, contents: [
            PCloudEntry(name: "gamma", isfolder: true, folderid: 10105, contents: [
                PCloudEntry(name: "clip-four.mp4", isfolder: false, size: 1_000_000),
                PCloudEntry(name: "clip-five.mp4", isfolder: false, fileid: 90_214),
                PCloudEntry(name: "clip-six.mp4", isfolder: false, fileid: 90_215, size: 2_000_000),
            ]),
            PCloudEntry(name: "delta", isfolder: true, folderid: 10106),
        ])
        // Without an id there is nothing to ask pCloud for, and without a size
        // the cache cannot budget for it, so neither is a library file.
        #expect(root.flattenedFiles().map(\.path) == ["gamma/clip-six.mp4"])
        // Undated sorts oldest under "Latest" instead of leading it.
        #expect(root.flattenedFiles().first?.modified == Date.distantPast)
    }
}

extension PCloudAPITests {
    @Test func hasNoURLToOfferWhenTheLinkCameBackWithoutAHost() {
        // The downloader treats a missing URL as "ask for the link again",
        // which is why this is nil rather than a URL that would 404 on fetch.
        let response = FileLinkResponse(hosts: [], path: "/cBZ7q0Zwarmgun0ZclipOneZ/clip-one.mp4",
                                        expires: Date(timeIntervalSince1970: 1_787_654_400))
        #expect(response.url == nil)
    }
}

extension PCloudAPITests {
    @Test func sortsTheCodesIntoTheTwoBucketsTheAppBranchesOn() {
        // Only two questions are ever asked of a failure: go back to login, or
        // wait and try the same call again. Everything else is just an error,
        // and mistaking a rate limit for a dead token would log the owner out
        // mid-trip over a burst of prefetches.
        #expect(PCloudError(code: 1000, message: "").isLoginRequired)
        #expect(!PCloudError(code: 1000, message: "").isRateLimited)
        #expect(PCloudError(code: 4000, message: "").isRateLimited)
        #expect(PCloudError(code: 4999, message: "").isRateLimited)
        #expect(!PCloudError(code: 5001, message: "").isRateLimited)
        #expect(!PCloudError(code: 5001, message: "").isLoginRequired)
    }
}

extension PCloudAPITests {
    @Test func buildsAgainstAnyOriginSoTheLocalStandInWorksToo() throws {
        // The transport may point at the real API (https, bare host) or at
        // tools/fake_pcloud.py (http://localhost:8765): the request takes the
        // origin's scheme, host and port rather than assuming https.
        let request = PCloudAPI.userInfo(auth: "token-a")
        let local = request.url(origin: try #require(URL(string: "http://localhost:8765")))
        #expect(local.absoluteString.hasPrefix("http://localhost:8765/userinfo?"))
        let real = request.url(origin: try #require(URL(string: "https://api.pcloud.com")))
        #expect(real == request.url(host: "api.pcloud.com"))
    }
}

extension PCloudAPITests {
    @Test func aBareUserinfoReplyCarriesNoTokenAndStillDecodes() throws {
        // Only `getauth=1` earns a token; the launch-time check of a stored one
        // gets back email and id alone, and must not read as a failure.
        let json = Data(#"{"result":0,"email":"jane@example.test","emailverified":true,"userid":42,"quota":100,"usedquota":10}"#.utf8)
        let info = try PCloudAPI.decode(UserInfoResponse.self, from: json)
        #expect(info == UserInfoResponse(email: "jane@example.test", userid: 42))
    }
}

extension PCloudAPITests {
    @Test func datesDecodeAsUnixSecondsWhateverDecoderReadsThem() throws {
        // The timestamps are a property of the types, not of one decoder's
        // configuration: read with a plain JSONDecoder (a cache replay, a test,
        // a future helper), the same integer must not silently land in 2057.
        let link = try JSONDecoder().decode(FileLinkResponse.self, from: Data(
            #"{"hosts":["cdn.example.test"],"path":"/a/clip-one.mp4","expires":1787654400}"#.utf8))
        #expect(link.expires == Date(timeIntervalSince1970: 1_787_654_400))

        let entry = try JSONDecoder().decode(PCloudEntry.self, from: Data(
            #"{"name":"clip-one.mp4","isfolder":false,"modified":1700000000}"#.utf8))
        #expect(entry.modified == Date(timeIntervalSince1970: 1_700_000_000))
    }
}

extension PCloudAPITests {
    @Test func everyBuilderCarriesTimeformatSoAnyDateComesBackAsSeconds() {
        // The date rule above holds only if no call can come back with pCloud's
        // default RFC-1123 strings — so the parameter rides on every request,
        // not just the ones whose responses carry dates today.
        let requests = [
            PCloudAPI.userInfo(auth: "t"),
            PCloudAPI.renameFile(fileID: 1, toPath: "/lib/2_outbox/kinda_weird/clip-one_topaz.mp4", auth: "t"),
            PCloudAPI.createFolderIfNotExists(path: "/Sync", auth: "t"),
            PCloudAPI.uploadFile(folderPath: "/Sync", filename: "journal.jsonl", auth: "t"),
        ]
        for request in requests {
            #expect(request.query.contains(URLQueryItem(name: "timeformat", value: "timestamp")),
                    "\(request.method) lacks timeformat")
        }
    }

    @Test func aDownloadPathWithAQueryDelimiterSurvivesIntoTheURL() {
        // A raw "#" or "?" in the path must not be read as a fragment or query
        // and silently truncate the download URL into a 404.
        let link = FileLinkResponse(hosts: ["cdn.example.test"], path: "/a/clip#one?.mp4",
                                    expires: Date(timeIntervalSince1970: 1))
        #expect(link.url?.absoluteString == "https://cdn.example.test/a/clip%23one%3F.mp4")
    }

    @Test func durationReadsFromANumberAndRefusesTheUnreadable() throws {
        // The three rungs of the ladder, pinned: a JSON number, a numeric
        // string (already covered), and the unreadable shapes — which must read
        // as absent, never sink the listing.
        let number = try PCloudAPI.decode(PCloudEntry.self, from: Data(
            #"{"result":0,"name":"clip-one.mp4","isfolder":false,"duration":5}"#.utf8))
        #expect(number.duration == 5.0)
        for bad in [#""abc""#, #""""#, "null", "true"] {
            let entry = try PCloudAPI.decode(PCloudEntry.self, from: Data(
                #"{"result":0,"name":"clip-one.mp4","isfolder":false,"duration":"#.utf8
                + Data(bad.utf8) + Data("}".utf8)))
            #expect(entry.duration == nil, "duration \(bad) should read as absent")
        }
    }
}

extension PCloudAPITests {
    @Test func movesAnUpscaleByPathWhenNoFileIDIsAtHand() {
        // The index keeps ids only for the originals it plays; the upscale the
        // weird gesture moves is named by path, and renamefile takes either.
        let request = PCloudAPI.renameFile(path: "/lib/2_outbox/upscaled_by_orientation/portrait/alpha/clip-one_topaz.mp4",
                                           toPath: "/lib/2_outbox/kinda_weird/clip-one_topaz.mp4",
                                           auth: "token-abc")
        #expect(request.method == "renamefile")
        #expect(request.query == [
            URLQueryItem(name: "path", value: "/lib/2_outbox/upscaled_by_orientation/portrait/alpha/clip-one_topaz.mp4"),
            URLQueryItem(name: "topath", value: "/lib/2_outbox/kinda_weird/clip-one_topaz.mp4"),
            URLQueryItem(name: "timeformat", value: "timestamp"),
            URLQueryItem(name: "auth", value: "token-abc"),
        ])
    }
}

extension PCloudAPITests {
    @Test func aPCloudErrorSpeaksTheServersOwnWords() {
        // Surfaced straight to the login screen: `localizedDescription` must be
        // the server's message, not Foundation's "operation couldn't be
        // completed" shrug — the message is the only clue the user gets.
        let error: Error = PCloudError(code: 2000, message: "Log in failed.")
        #expect(error.localizedDescription == "pCloud: Log in failed. (code 2000)")
    }
}

extension PCloudAPITests {
    @Test func aLoginCanCarryTheVerificationCodeTheServerAskedFor() {
        // Error 1022 ("Please provide 'code'.") is pCloud asking for a second
        // factor — an authenticator or emailed code. The retry is the same
        // login with `code` riding along; without a code the query is unchanged.
        let plain = PCloudAPI.login(username: "gunner@example.test", password: "pw")
        #expect(plain == PCloudAPI.login(username: "gunner@example.test", password: "pw", code: nil))
        let coded = PCloudAPI.login(username: "gunner@example.test", password: "pw", code: "123456")
        #expect(coded.query.contains(URLQueryItem(name: "code", value: "123456")))
        #expect(coded.method == "login")
    }
}

extension PCloudAPITests {
    @Test func aTwoFactorChallengeCarriesItsTokenOutOfTheErrorEnvelope() throws {
        // A 2FA account answers the password with an error that ALSO carries a
        // token (and the factor type); the app exchanges that token plus a code
        // via tfa_login. Dropping those fields is what made the challenge look
        // like a dead end.
        let json = Data(#"{"result": 2297, "error": "TFA login required.", "token": "tfa-tok-1", "tfatype": 1, "hasdevices": true}"#.utf8)
        let error = try #require(throws: PCloudError.self) {
            try PCloudAPI.decode(LoginResponse.self, from: json)
        }
        #expect(error.token == "tfa-tok-1")
        #expect(error.tfaType == 1)
        #expect(error.hasDevices == true)
        let plain = try #require(throws: PCloudError.self) {
            try PCloudAPI.decode(LoginResponse.self, from: Data(#"{"result": 2000, "error": "Log in failed."}"#.utf8))
        }
        #expect(plain.token == nil)
    }

    @Test func theSecondLegExchangesTheChallengeTokenAndACode() {
        let request = PCloudAPI.tfaLogin(token: "tfa-tok-1", code: "123456", trustDevice: true, isRecovery: false)
        #expect(request.method == "tfa_login")
        #expect(request.query == [
            URLQueryItem(name: "getauth", value: "1"),
            URLQueryItem(name: "token", value: "tfa-tok-1"),
            URLQueryItem(name: "code", value: "123456"),
            URLQueryItem(name: "trustdevice", value: "1"),
            URLQueryItem(name: "authexpire", value: "63072000"),
            URLQueryItem(name: "device", value: "WarmGun"),
            URLQueryItem(name: "timeformat", value: "timestamp"),
        ])
        #expect(PCloudAPI.tfaLogin(token: "t", code: "c", trustDevice: false, isRecovery: true).method
                == "tfa_loginwithrecoverycode")
    }

    @Test func aCodeCanBeSentBySMSOrToTheOtherLoggedInDevices() {
        let sms = PCloudAPI.tfaSendCodeViaSMS(token: "tfa-tok-1")
        #expect(sms.method == "tfa_sendcodeviasms")
        #expect(sms.query == [URLQueryItem(name: "token", value: "tfa-tok-1")])
        let push = PCloudAPI.tfaSendCodeViaNotification(token: "tfa-tok-1")
        #expect(push.method == "tfa_sendcodeviasysnotification")
        #expect(push.query == [URLQueryItem(name: "token", value: "tfa-tok-1")])
    }
}

extension PCloudAPITests {
    @Test func asksForTheFolderSkeletonAloneWhenHuntingForTheLibrary() {
        let request = PCloudAPI.listFolders(path: "/", auth: "token-abc")
        #expect(request.method == "listfolder")
        #expect(request.query == [
            URLQueryItem(name: "path", value: "/"),
            URLQueryItem(name: "recursive", value: "1"),
            URLQueryItem(name: "nofiles", value: "1"),
            URLQueryItem(name: "timeformat", value: "timestamp"),
            URLQueryItem(name: "auth", value: "token-abc"),
        ])
        // pCloud refuses recursive listings of the ROOT with 1101 (a 2025-era
        // server change, see rclone#9315), so the hunt must be able to descend
        // one shallow rung at a time.
        let shallow = PCloudAPI.listFolders(path: "/", auth: "token-abc", recursive: false)
        #expect(shallow.query == [
            URLQueryItem(name: "path", value: "/"),
            URLQueryItem(name: "nofiles", value: "1"),
            URLQueryItem(name: "timeformat", value: "timestamp"),
            URLQueryItem(name: "auth", value: "token-abc"),
        ])
    }
}

extension PCloudAPITests {
    @Test func fetchesTheWholeSidecarCorpusAsOneZip() {
        // 1,341 sidecars are 1.5 MB but would be 2,682 round-trips fetched one
        // by one; getzip streams the folder as a single body.
        let request = PCloudAPI.getZip(path: "/lib/videos/metadata/2D/AI", auth: "token-abc")
        #expect(request.method == "getzip")
        #expect(request.query == [
            URLQueryItem(name: "path", value: "/lib/videos/metadata/2D/AI"),
            URLQueryItem(name: "timeformat", value: "timestamp"),
            URLQueryItem(name: "auth", value: "token-abc"),
        ])
    }
}
