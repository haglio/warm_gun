import Foundation
import WarmGunKit

struct Settings: Codable, Equatable {
    var apiHost = "api.pcloud.com"
    var username = ""
    var libraryPath = ""
    var syncFolder = "/WarmGun"
    var filters = Filters(shape: Platform.defaultShape)
    var loopVideo = false
    var cacheCapMB = 2048
    var prefetchAhead = 12
    // The JSON key stored in UserDefaults: the synthesized decoder throws on a key it cannot find, so
    // renaming this needs a migration.
    var prefetchBehind = 3

    private enum CodingKeys: String, CodingKey {
        case apiHost, username, libraryPath, syncFolder, cacheCapMB, prefetchAhead, prefetchBehind
        case filters = "browse"
        case loopVideo = "loopClip"
    }

    var cacheCapBytes: Int64 { Int64(cacheCapMB) * 1_000_000 }

    private static let key = "warm-gun.settings"

    static func load(from defaults: UserDefaults = .standard) -> Settings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
