import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, battery, keepAwake, brightness, fans, temperatures, speedTest, ports, sound, keyboard, mouse, windows, dock, finder, animations, player, uninstaller, background, games, pet, permissions, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .battery: String(localized: "Battery")
        case .keepAwake: String(localized: "Keep Awake")
        case .brightness: String(localized: "Brightness")
        case .fans: String(localized: "Fans")
        case .temperatures: String(localized: "Temperature")
        case .speedTest: String(localized: "Speed Test")
        case .ports: String(localized: "Ports")
        case .sound: String(localized: "Sound")
        case .keyboard: String(localized: "Keyboard")
        case .mouse: String(localized: "Mouse")
        case .windows: String(localized: "Windows")
        case .dock: String(localized: "Dock")
        case .finder: String(localized: "Finder")
        case .animations: String(localized: "Animations")
        case .player: String(localized: "Player")
        case .uninstaller: String(localized: "Uninstaller")
        case .background: String(localized: "Background Tasks")
        case .games: String(localized: "Games")
        case .pet: String(localized: "Pet")
        case .permissions: String(localized: "Permissions")
        case .about: String(localized: "About")
        }
    }

    private var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .battery: "battery.100percent"
        case .keepAwake: "cup.and.saucer.fill"
        case .brightness: "sun.max.fill"
        case .fans: "fan"
        case .temperatures: "thermometer.medium"
        case .speedTest: "speedometer"
        case .ports: "network"
        case .sound: "speaker.wave.2.fill"
        case .keyboard: "keyboard.fill"
        case .mouse: "computermouse.fill"
        case .windows: "macwindow.on.rectangle"
        case .dock: "dock.rectangle"
        case .finder: "folder.fill"
        case .animations: "hare.fill"
        case .player: "play.rectangle.fill"
        case .uninstaller: "xmark.bin.fill"
        case .background: "gearshape.2.fill"
        case .games: "gamecontroller.fill"
        case .pet: "pawprint.fill"
        case .permissions: "hand.raised.fill"
        case .about: "info.circle.fill"
        }
    }

    private var color: Color {
        switch self {
        case .general, .dock, .about: .gray
        case .keyboard, .mouse, .permissions: .blue
        case .windows: .indigo
        case .finder: .cyan
        case .games: .purple
        case .animations, .sound: .pink
        case .uninstaller: .brown
        case .background: .mint
        case .keepAwake, .player: .orange
        case .brightness: .yellow
        case .fans: .teal
        case .pet, .temperatures: .red
        case .speedTest, .battery: .green
        case .ports: .blue
        }
    }

    var isAvailable: Bool {
        if self == .battery { return Battery.isPresent }
        if self == .sound, #unavailable(macOS 14.2) { return false }
        #if APPSTORE
        return ![.fans, .uninstaller, .dock, .ports, .player].contains(self)
        #else
        return true
        #endif
    }

    static var iconSize: CGFloat {
        switch UserDefaults.standard.integer(forKey: "NSTableViewDefaultSizeMode") {
        case 1: 18
        case 3: 24
        default: 20
        }
    }

    func icon(size: CGFloat = iconSize) -> some View {
        SectionIcon(symbol: symbol, color: color, size: size)
    }
}
