import Foundation

extension Int {
    /// This value as a place on a ring of *count* places. Swift's `%` keeps the
    /// sign of the dividend, which would put a step back off the front.
    func wrapped(into count: Int) -> Int {
        let remainder = self % count
        return remainder < 0 ? remainder + count : remainder
    }
}
