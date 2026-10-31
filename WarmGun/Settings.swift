import Foundation
import WarmGunKit

/// What the app keeps between launches, in UserDefaults; the pCloud token is
/// a secret and lives in the Keychain instead.
struct Settings: Codable, Equatable {
    var apiHost = "api.pcloud.com"
    var username = ""
    var libraryPath = ""
    var syncFolder = "/WarmGun"
    var browse = BrowseOptions(orientation: Platform.defaultOrientation)
    var loopClip = false
    var cacheCapMB = 2048
    var prefetchAhead = 12
    // Named for the direction it looks, in the spelling already written into
    // UserDefaults: this is the stored JSON key, and the synthesized decoder
    // throws on a key it cannot find, which would drop every other setting
    // back to its default. Renaming it needs a migration, not an edit.
    var prefetchBehind = 3
    var moveWeirdInCloud = true

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
