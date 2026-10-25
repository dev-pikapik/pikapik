import Foundation

enum PermissionPolling {
    static let interval: TimeInterval = 1.5
    static let afterAllow: TimeInterval = 120

    static func continues(pageShown: Bool, askedUntil: Date, askedGranted: Bool, now: Date = .now) -> Bool {
        pageShown || (now < askedUntil && !askedGranted)
    }
}
