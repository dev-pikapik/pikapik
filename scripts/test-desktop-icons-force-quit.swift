import Foundation

@main
struct TestDesktopIconsForceQuit {
    static let key = "desktop-icons-original"

    static func copy(_ journal: UserDefaults, icons: @escaping () -> Bool, writeIcons: @escaping (Bool) -> Void) -> DesktopIconsHost {
        DesktopIconsHost(journal: journal, iconsHidden: icons, writeIcons: writeIcons, desktopMade: { true }, makeDesktop: {})
    }

    static func main() {
        let arguments = CommandLine.arguments
        if arguments.count == 3, arguments[1] == "hide" {
            DesktopIcons.hide(copy(UserDefaults(suiteName: arguments[2])!, icons: { false }, writeIcons: { _ in _exit(0) }))
            exit(1)
        }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("test-desktop-icons-force-quit-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("journal").path

        let killed = Process()
        killed.executableURL = Bundle.main.executableURL
        killed.arguments = ["hide", path]
        try! killed.run()
        killed.waitUntilExit()
        precondition(killed.terminationStatus == 0, "the copy must stop while it hides the icons")

        var icons = true
        var writes: [Bool] = []
        DesktopIcons.putBack(copy(UserDefaults(suiteName: path)!, icons: { icons }, writeIcons: { icons = $0; writes.append($0) }))
        precondition(writes == [false] && !icons, "the next launch must show the icons: \(writes)")
        precondition(NSDictionary(contentsOfFile: path + ".plist")?[key] == nil, "the next launch must forget the note")
        print("a copy force-quit while it hides the icons has already noted them, and the next launch brings them back: ok")
    }
}
