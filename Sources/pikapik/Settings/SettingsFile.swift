import Foundation

struct SettingsFile {
    enum Action: Equatable {
        case apply, upload, none
    }

    static let app = AppConstants.legacyAppName
    static let name = "settings.json"
    static let maxSize = 2_000_000
    /// The time on an upload that no change on this Mac caused, for example the first one after sync is turned on while
    /// iCloud has not delivered the file yet. It lies in the first day of 1970, so it loses to every real file: the other
    /// Macs keep their settings and send them here instead of taking this Mac's. A later upload gets an earlier time, so of
    /// two Macs that turn sync on before iCloud has anything, the second takes the settings of the first.
    static func unclaimed(at date: Date = .now) -> Date {
        Date(timeIntervalSince1970: 86_400 - date.timeIntervalSince1970 / 100_000)
    }
    static let keys = Set([
        PreferenceKey.appearance, PreferenceKey.appleLanguages, PreferenceKey.openAtLogin, PreferenceKey.keepRunning, PreferenceKey.checkUpdates,
        PreferenceKey.commandKeysQuit, PreferenceKey.commandKeysClose, PreferenceKey.commandKeysQuitShortcut, PreferenceKey.commandKeysCloseShortcut,
        ToolID.inputSwitch, ToolID.keyRepeat, ToolID.homeEnd, PreferenceKey.homeEndExcluded,
        ToolID.layoutFix, PreferenceKey.layoutFixAuto, PreferenceKey.layoutFixShortcut, PreferenceKey.layoutFixExcluded,
        ToolID.linearPointer, PreferenceKey.linearPointerSpeed, ToolID.wheelLines, PreferenceKey.wheelLinesCount, PreferenceKey.wheelLinesMode, PreferenceKey.wheelLinesPixels,
        ToolID.wheelDirection, PreferenceKey.wheelDirectionNatural, PreferenceKey.wheelDirectionTrackpadNatural,
        ToolID.sideButtons, PreferenceKey.sideButtonsSwap, ToolID.hideApp, PreferenceKey.hideAppButton, ToolID.middleClick, PreferenceKey.middleClickFingers,
        ToolID.quitOnClose, PreferenceKey.quitOnCloseExcluded, ToolID.dockHide, PreferenceKey.dockHideAction, ToolID.dockDisplay, ToolID.windowZoom, PreferenceKey.windowZoomExcluded, ToolID.newFile, ToolID.compress, ToolID.convert,
        ToolID.archive, PreferenceKey.archiveFormat, PreferenceKey.archiveSplit,
        ToolID.finderOpen, ToolID.finderCut, ToolID.finderDelete,
        ToolID.gameMode, PreferenceKey.gameModeGames, PreferenceKey.gameModeNotGames, PreferenceKey.gameModeSystemShortcuts, PreferenceKey.gameModeFPS, PreferenceKey.gameModeFPSCorner,
        PreferenceKey.keepAwakeMode, PreferenceKey.keepAwakeDuration,
        PreferenceKey.keepAwakeDisplay, PreferenceKey.keepAwakeBattery,
        PreferenceKey.fansRPM, ToolID.brightnessKeys,
        PreferenceKey.animationsSpeed, PreferenceKey.animationsDockDelay, PreferenceKey.animationsDockSpeed, PreferenceKey.animationsMinimize, PreferenceKey.animationsBounce,
        PreferenceKey.animationsWindowOpen, PreferenceKey.animationsResize, PreferenceKey.animationsQuickLook, PreferenceKey.animationsFinderColumns, PreferenceKey.animationsFinder,
        ToolID.pet, PreferenceKey.petTalks, PreferenceKey.petRhythm, PreferenceKey.petBall, ToolID.uninstallerTrashWatch,
        ToolID.appVolume, PreferenceKey.appVolumeLevels, PreferenceKey.appVolumeMuted, PreferenceKey.appVolumeNames,
    ] + GameRule.allCases.map(\.key))

    var settings: [String: Any]
    var modified: Date
    var device: String

    init(settings: [String: Any], modified: Date, device: String) {
        self.settings = Self.filter(settings)
        self.modified = modified
        self.device = device
    }

    init?(data: Data) {
        guard data.count <= Self.maxSize,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              root["app"] as? String == Self.app,
              let settings = root["settings"] as? [String: Any]
        else { return nil }
        self.settings = Self.filter(settings)
        modified = Date(timeIntervalSince1970: (root["modified"] as? NSNumber)?.doubleValue ?? 0)
        device = root["device"] as? String ?? ""
    }

    func data() throws -> Data {
        let root: [String: Any] = [
            "app": Self.app,
            "version": 1,
            "modified": modified.timeIntervalSince1970,
            "device": device,
            "settings": settings,
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    static func filter(_ values: [String: Any]) -> [String: Any] {
        GameRules.migrated(values).filter { keys.contains($0.key) && isValid($0.value) }
    }

    static func isValid(_ value: Any) -> Bool {
        if value is String || value is NSNumber { return true }
        if let table = value as? [String: Any] { return table.values.allSatisfy { $0 is NSNumber || $0 is String } }
        guard let list = value as? [Any] else { return false }
        return list.allSatisfy { $0 is String }
    }

    /// The file at `url`; nil when there is none or it is damaged, so it may be replaced; or the error when it can't be read
    /// now, for example while iCloud downloads it or the Mac is offline. Nothing may replace it then.
    static func read(_ url: URL) -> Result<SettingsFile?, Error> {
        var result = Result<SettingsFile?, Error>.success(nil)
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { url in
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            do {
                let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
                if size <= maxSize {
                    let data = try Data(contentsOf: url)
                    result = .success(SettingsFile(data: data))
                }
            } catch {
                if !isMissing(error) { result = .failure(error) }
            }
        }
        if let error, !isMissing(error) { return .failure(error) }
        return result
    }

    private static func isMissing(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain && (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError)
    }

    static func merge(local: Date, remote: SettingsFile?, device: String) -> Action {
        guard let remote else { return .upload }
        if remote.modified == local { return .none }
        if remote.device == device { return .upload }
        return remote.modified > local ? .apply : .upload
    }

    static func onSave(_ changed: @escaping () -> Void) {
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { _ in
            if Thread.isMainThread { changed() } else { DispatchQueue.main.async(execute: changed) }
        }
    }

    static func moveFolder(from old: URL, to new: URL) {
        let manager = FileManager.default
        guard manager.fileExists(atPath: old.path) else { return }
        guard manager.fileExists(atPath: new.path) else {
            try? manager.moveItem(at: old, to: new)
            return
        }
        let source = old.appendingPathComponent(name), target = new.appendingPathComponent(name)
        if manager.fileExists(atPath: source.path) {
            guard let data = try? Data(contentsOf: source), let file = SettingsFile(data: data) else { return }
            var newer = true
            if manager.fileExists(atPath: target.path) {
                guard let current = (try? Data(contentsOf: target)).flatMap(SettingsFile.init(data:)) else { return }
                newer = file.modified > current.modified
            }
            if newer {
                do { try data.write(to: target, options: .atomic) } catch { return }
            }
        }
        guard let names = try? manager.contentsOfDirectory(atPath: old.path), names.allSatisfy([name, ".DS_Store"].contains) else { return }
        try? manager.removeItem(at: old)
    }

    static func same(_ a: [String: Any], _ b: [String: Any]) -> Bool {
        NSDictionary(dictionary: a).isEqual(to: b)
    }
}
