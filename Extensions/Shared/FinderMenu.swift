import AppKit

enum FinderMenu {
    static var shown: Bool {
        let own = Bundle.main.bundleIdentifier ?? ""
        let running = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        let extensions = MainCopyChoice.sameMenu(own, in: running.compactMap(\.bundleIdentifier))
        let hostIDs = Set(extensions.map(MainCopyChoice.hostID))
        let hosts = running.compactMap { app in
            app.bundleIdentifier.flatMap { hostIDs.contains($0) ? RunningCopy(pid: app.processIdentifier, bundleID: $0, launched: MainCopyChoice.started(app.processIdentifier) ?? .distantPast) : nil }
        }
        return MainCopyChoice.showsMenu(own, among: extensions, hosts: hosts)
    }
}
