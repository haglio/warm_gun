import Foundation

extension Int {
    /// Swift's `%` keeps the sign of the dividend.
    func wrapped(into count: Int) -> Int {
        let remainder = self % count
        return remainder < 0 ? remainder + count : remainder
    }
}
