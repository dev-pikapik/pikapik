import AppKit
import UniformTypeIdentifiers

protocol DefaultAppSystem {
    func handler(of type: UTType) -> URL?
    func handlers(of type: UTType) -> [URL]
    func app(withID id: String) -> URL?
    func assign(_ app: URL, to type: UTType) async throws
}

extension NSWorkspace: DefaultAppSystem {
    func handler(of type: UTType) -> URL? { urlForApplication(toOpen: type) }
    func handlers(of type: UTType) -> [URL] { urlsForApplications(toOpen: type) }
    func app(withID id: String) -> URL? { urlForApplication(withBundleIdentifier: id) }
    func assign(_ app: URL, to type: UTType) async throws { try await setDefaultApplication(at: app, toOpen: type) }
}

@Observable
final class DefaultApps {
    static let retiredKeys = ["player-video-previous-apps", "player-music-previous-apps", "player-image-previous-apps", "archive-previous-apps"]

    private let types: [UTType]
    let target: URL
    private let system: DefaultAppSystem

    private var current: [String: URL] = [:]
    private var choices: [String: [URL]] = [:]
    private(set) var busy = false

    init(types: [UTType], target: URL, system: DefaultAppSystem = NSWorkspace.shared, defaults: UserDefaults = .standard) {
        self.types = types
        self.target = target
        self.system = system
        Self.retiredKeys.forEach(defaults.removeObject)
        refresh()
    }

    /// The app that opens these types now. pikapik only when it opens all of them, so a type it lacks is never hidden.
    func owner(of types: [UTType]) -> URL? {
        let apps = types.map { current[$0.identifier] }
        if let other = apps.lazy.compactMap({ $0 }).first(where: { $0 != self.target }) { return other }
        return apps.isEmpty || apps.contains(nil) ? nil : target
    }

    /// The apps that can open every one of these types, pikapik first.
    func choices(for types: [UTType]) -> [URL] {
        guard let first = types.first else { return [] }
        return (choices[first.identifier] ?? []).filter { app in types.allSatisfy { choices[$0.identifier]?.contains(app) == true } }
    }

    func refresh() {
        var current: [String: URL] = [:]
        var choices: [String: [URL]] = [:]
        for type in types {
            current[type.identifier] = system.handler(of: type).flatMap(app)
            var apps = [target]
            for app in system.handlers(of: type).compactMap(app) where !apps.contains(app) { apps.append(app) }
            choices[type.identifier] = apps
        }
        self.current = current
        self.choices = choices
    }

    /// macOS asks about each type: a refusal stops here, "Keep" moves on to the next one.
    @discardableResult
    func open(_ types: [UTType], with app: URL) -> Task<Void, Never> {
        Task { @MainActor in
            busy = true
            for type in types where current[type.identifier] != app {
                guard await assign(app, to: type) else { break }
                refresh()
            }
            busy = false
            refresh()
        }
    }

    @MainActor
    private func assign(_ app: URL, to type: UTType) async -> Bool {
        var answer: Bool?
        Task { @MainActor in
            do { try await system.assign(app, to: type); answer = true } catch { answer = ((error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError)?.code == Int(userCanceledErr) }
        }
        await Task.yield()
        let deadline = Date.now.addingTimeInterval(60)
        while answer == nil, !handles(type, app), Date.now < deadline {
            try? await Task.sleep(for: .milliseconds(200))
        }
        return answer ?? handles(type, app)
    }

    private func handles(_ type: UTType, _ app: URL) -> Bool { system.handler(of: type).flatMap(self.app) == app }

    private var targetID: String? { Bundle(url: target)?.bundleIdentifier }

    /// One URL per app. Every copy of the player is the player itself, even one deleted from a build folder that
    /// LaunchServices still lists; a deleted copy of another app is gone; other copies become the one macOS prefers.
    private func app(_ url: URL) -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return url.lastPathComponent == target.lastPathComponent ? target : nil }
        guard let id = Bundle(url: url)?.bundleIdentifier else { return url }
        return id == targetID ? target : system.app(withID: id) ?? url
    }
}
