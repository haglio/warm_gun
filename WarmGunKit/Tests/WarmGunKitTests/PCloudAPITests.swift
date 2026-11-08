import Foundation
import Testing
@testable import WarmGunKit

@Suite struct PCloudAPITests {
    @Test func buildsTheMethodURLAndSurvivesTheCharactersAPasswordCanCarry() throws {
        let request = PCloudRequest(method: "userinfo", query: [
            URLQueryItem(name: "username", value: "gunner@example.test"),
            URLQueryItem(name: "password", value: "a&b+c d"),
        ])
        let url = request.url(origin: try #require(URL(string: "https://api.pcloud.com")))
        #expect(url.scheme == "https")
        #expect(url.host == "api.pcloud.com")
        #expect(url.path == "/userinfo")
        let parsed = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parsed.queryItems == request.query)
        let encoded = try #require(parsed.percentEncodedQuery)
        #expect(encoded.contains("%2B"))
        #expect(encoded.contains("%26"))
    }
}

extension PCloudAPITests {
    @Test func logsInAsAClientWithADeviceIdentityAndNeverKeepsThePassword() {
        let request = PCloudAPI.login(username: "gunner@example.test", password: "a&b+c d")
        #expect(request.method == "login")
        #expect(request.query == [
            URLQueryItem(name: "getauth", value: "1"),
            URLQueryItem(name: "username", value: "gunner@example.test"),
            URLQueryItem(name: "password", value: "a&b+c d"),
            URLQueryItem(name: "authexpire", value: "63072000"),
            URLQueryItem(name: "device", value: "WarmGun"),
            URLQueryItem(name: "deviceid", value: "warmgun-phone"),
            URLQueryItem(name: "os", value: "4"),
            URLQueryItem(name: "timeformat", value: "timestamp"),
        ])
    }
}

extension PCloudAPITests {
    @Test func pullsTheWholeLibraryTreeInOneRecursiveListing() {
        let request = PCloudAPI.listFolder(path: "/lib/AI", auth: "token-abc")
        #expect(request.method == "listfolder")
        #expect(request.query == [
            URLQueryItem(name: "path", value: "/lib/AI"),
            URLQueryItem(name: "recursive", value: "1"),
            URLQueryItem(name: "timeformat", value: "timestamp"),
            URLQueryItem(name: "auth", value: "token-abc"),
        ])
    }
}

extension PCloudAPITests {
    @Test func asksForADownloadLinkByFileIDRatherThanByPath() {
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
        #expect(response == LoginResponse(auth: "tok-9f3c"))
    }
}

extension PCloudAPITests {
    @Test func turnsAFailedResultIntoAnErrorEvenThoughTheHTTPStatusWas200() throws {
        let json = Data(#"{"result": 2000, "error": "Log in failed."}"#.utf8)
        let error = try #require(throws: PCloudError.self) {
            try PCloudAPI.decode(LoginResponse.self, from: json)
        }
        #expect(error == PCloudError(code: 2000, message: "Log in failed."))
        #expect(error.isLoginRequired)
    }
}

extension PCloudAPITests {
    @Test func assemblesADownloadURLOutOfTheHostAndPathGetfilelinkHandsBack() throws {
        let json = Data("""
        {"result": 0, "dwltag": "7Qm2vXpLrK", "hash": 4471209983314, "size": 2295611,
         "expires": 1787654400, "path": "/cBZ7q0Zwarmgun0ZvideoOneZ/video-one.mp4",
         "hosts": ["edef1.pcloud.com", "c210.pcloud.com"]}
        """.utf8)
        let response = try PCloudAPI.decode(FileLinkResponse.self, from: json)
        #expect(response.hosts == ["edef1.pcloud.com", "c210.pcloud.com"])
        #expect(response.path == "/cBZ7q0Zwarmgun0ZvideoOneZ/video-one.mp4")
        #expect(response.expires == Date(timeIntervalSince1970: 1_787_654_400))
        #expect(response.url == URL(string: "https://edef1.pcloud.com/cBZ7q0Zwarmgun0ZvideoOneZ/video-one.mp4"))
    }
}

extension PCloudAPITests {
    static let listing = Data("""
    {"result": 0, "metadata": {"name": "AI", "isfolder": true, "folderid": 10100, "contents": [
      {"name": "alpha", "isfolder": true, "folderid": 10101, "contents": [
        {"name": "portrait", "isfolder": true, "folderid": 10102, "contents": [
          {"name": "video-one.mp4", "isfolder": false, "fileid": 90210, "size": 2295611,
           "modified": 1723456789, "contenttype": "video/mp4", "category": 2,
           "duration": "5.03", "videocodec": "h264", "width": 720, "height": 1280},
          {"name": "video-two.mp4", "isfolder": false, "fileid": 90211, "size": 1884210,
           "modified": 1723456999, "contenttype": "video/mp4", "category": 2,
           "videocodec": "h264", "width": 720, "height": 1280}
        ]}
      ]},
      {"name": "beta", "isfolder": true, "folderid": 10103, "contents": [
        {"name": "landscape", "isfolder": true, "folderid": 10104, "contents": [
          {"name": "video-three.mp4", "isfolder": false, "fileid": 90212, "size": 3120044,
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

        let video = try #require(root.contents?.first?.contents?.first?.contents?.first)
        #expect(video.name == "video-one.mp4")
        #expect(!video.isfolder)
        #expect(video.fileid == 90_210)
        #expect(video.size == 2_295_611)
        #expect(video.modified == Date(timeIntervalSince1970: 1_723_456_789))
        #expect(video.duration == 5.03)
        #expect(video.videocodec == "h264")
        #expect(video.width == 720)
        #expect(video.height == 1280)

        let second = try #require(root.contents?.first?.contents?.first?.contents?.last)
        #expect(second.duration == nil)
    }
}

extension PCloudAPITests {
    @Test func flattensTheTreeIntoLibraryRelativePathsInListingOrder() throws {
        let response = try PCloudAPI.decode(ListFolderResponse.self, from: Self.listing)
        let files = response.metadata.flattenedFiles()
        #expect(files.map(\.path) == [
            "alpha/portrait/video-one.mp4",
            "alpha/portrait/video-two.mp4",
            "beta/landscape/video-three.mp4",
            "sorter-notes.txt",
        ])
        #expect(files.first == LibraryFile(path: "alpha/portrait/video-one.mp4",
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
                PCloudEntry(name: "video-four.mp4", isfolder: false, size: 1_000_000),
                PCloudEntry(name: "video-five.mp4", isfolder: false, fileid: 90_214),
                PCloudEntry(name: "video-six.mp4", isfolder: false, fileid: 90_215, size: 2_000_000),
            ]),
            PCloudEntry(name: "delta", isfolder: true, folderid: 10106),
        ])
        #expect(root.flattenedFiles().map(\.path) == ["gamma/video-six.mp4"])
        #expect(root.flattenedFiles().first?.modified == Date.distantPast)
    }
}

extension PCloudAPITests {
    @Test func hasNoURLToOfferWhenTheLinkCameBackWithoutAHost() {
        let response = FileLinkResponse(hosts: [], path: "/cBZ7q0Zwarmgun0ZvideoOneZ/video-one.mp4",
                                        expires: Date(timeIntervalSince1970: 1_787_654_400))
        #expect(response.url == nil)
    }
}

extension PCloudAPITests {
    @Test func onlyARefusedTokenSendsTheViewerBackToLogin() {
        #expect(PCloudError(code: 1000, message: "").isLoginRequired)
        #expect(!PCloudError(code: 4000, message: "").isLoginRequired)
        #expect(!PCloudError(code: 5001, message: "").isLoginRequired)
    }
}

extension PCloudAPITests {
    @Test func buildsAgainstAnyOriginSoTheLocalStandInWorksToo() throws {
        let request = PCloudAPI.listFolder(path: "/lib", auth: "token-a")
        let local = request.url(origin: try #require(URL(string: "http://localhost:8765")))
        #expect(local.absoluteString.hasPrefix("http://localhost:8765/listfolder?"))
        let real = request.url(origin: try #require(URL(string: "https://api.pcloud.com")))
        #expect(real.absoluteString.hasPrefix("https://api.pcloud.com/listfolder?"))
    }
}

extension PCloudAPITests {
    @Test func datesDecodeAsUnixSecondsWhateverDecoderReadsThem() throws {
        let link = try JSONDecoder().decode(FileLinkResponse.self, from: Data(
            #"{"hosts":["cdn.example.test"],"path":"/a/video-one.mp4","expires":1787654400}"#.utf8))
        #expect(link.expires == Date(timeIntervalSince1970: 1_787_654_400))

        let entry = try JSONDecoder().decode(PCloudEntry.self, from: Data(
            #"{"name":"video-one.mp4","isfolder":false,"modified":1700000000}"#.utf8))
        #expect(entry.modified == Date(timeIntervalSince1970: 1_700_000_000))
    }
}

extension PCloudAPITests {
    @Test func everyBuilderCarriesTimeformatSoAnyDateComesBackAsSeconds() {
        let requests = [
            PCloudAPI.renameFile(path: "/lib/2_outbox/upscaled_by_orientation/portrait/alpha/video-one_topaz.mp4",
                                 toPath: "/lib/2_outbox/trash/video-one_topaz.mp4", auth: "t"),
            PCloudAPI.createFolderIfNotExists(path: "/Sync", auth: "t"),
            PCloudAPI.uploadFile(folderPath: "/Sync", filename: "journal.jsonl", auth: "t"),
        ]
        for request in requests {
            #expect(request.query.contains(URLQueryItem(name: "timeformat", value: "timestamp")),
                    "\(request.method) lacks timeformat")
        }
    }

    @Test func aDownloadPathWithAQueryDelimiterSurvivesIntoTheURL() {
        let link = FileLinkResponse(hosts: ["cdn.example.test"], path: "/a/video#one?.mp4",
                                    expires: Date(timeIntervalSince1970: 1))
        #expect(link.url?.absoluteString == "https://cdn.example.test/a/video%23one%3F.mp4")
    }

    @Test func durationReadsFromANumberAndRefusesTheUnreadable() throws {
        let number = try PCloudAPI.decode(PCloudEntry.self, from: Data(
            #"{"result":0,"name":"video-one.mp4","isfolder":false,"duration":5}"#.utf8))
        #expect(number.duration == 5.0)
        for bad in [#""abc""#, #""""#, "null", "true"] {
            let body = #"{"result":0,"name":"video-one.mp4","isfolder":false,"duration":"# + bad + "}"
            let entry = try PCloudAPI.decode(PCloudEntry.self, from: Data(body.utf8))
            #expect(entry.duration == nil, "duration \(bad) should read as absent")
        }
    }
}

extension PCloudAPITests {
    @Test func movesAnUpscaleByGivingRenamefileItsPathAndAWholeDestination() {
        let request = PCloudAPI.renameFile(path: "/lib/2_outbox/upscaled_by_orientation/portrait/alpha/video-one_topaz.mp4",
                                           toPath: "/lib/2_outbox/trash/video-one_topaz.mp4",
                                           auth: "token-abc")
        #expect(request.method == "renamefile")
        #expect(request.query == [
            URLQueryItem(name: "path", value: "/lib/2_outbox/upscaled_by_orientation/portrait/alpha/video-one_topaz.mp4"),
            URLQueryItem(name: "topath", value: "/lib/2_outbox/trash/video-one_topaz.mp4"),
            URLQueryItem(name: "timeformat", value: "timestamp"),
            URLQueryItem(name: "auth", value: "token-abc"),
        ])
    }
}

extension PCloudAPITests {
    @Test func aPCloudErrorSpeaksTheServersOwnWords() {
        let error: Error = PCloudError(code: 2000, message: "Log in failed.")
        #expect(error.localizedDescription == "pCloud: Log in failed. (code 2000)")
    }
}

extension PCloudAPITests {
    @Test func aLoginCanCarryTheVerificationCodeTheServerAskedFor() {
        let plain = PCloudAPI.login(username: "gunner@example.test", password: "pw")
        #expect(plain == PCloudAPI.login(username: "gunner@example.test", password: "pw", code: nil))
        let coded = PCloudAPI.login(username: "gunner@example.test", password: "pw", code: "123456")
        #expect(coded.query.contains(URLQueryItem(name: "code", value: "123456")))
        #expect(coded.method == "login")
    }
}

extension PCloudAPITests {
    @Test func aTwoFactorChallengeCarriesItsTokenOutOfTheErrorEnvelope() throws {
        let json = Data(#"{"result": 2297, "error": "TFA login required.", "token": "tfa-tok-1", "tfatype": 1, "hasdevices": true}"#.utf8)
        let error = try #require(throws: PCloudError.self) {
            try PCloudAPI.decode(LoginResponse.self, from: json)
        }
        #expect(error.token == "tfa-tok-1")
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
        let shallow = PCloudAPI.listFolders(path: "/", auth: "token-abc", recursive: false)
        #expect(shallow.query == [
            URLQueryItem(name: "path", value: "/"),
            URLQueryItem(name: "nofiles", value: "1"),
            URLQueryItem(name: "timeformat", value: "timestamp"),
            URLQueryItem(name: "auth", value: "token-abc"),
        ])
    }
}
