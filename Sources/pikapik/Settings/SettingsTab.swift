import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, battery, keepAwake, brightness, fans, temperatures, speedTest, ports, sound, keyboard, mouse, windows, dock, finder, animations, player, uninstaller, background, games, pet, permissions, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: TabTitle.general
        case .battery: TabTitle.battery
        case .keepAwake: TabTitle.keepAwake
        case .brightness: TabTitle.brightness
        case .fans: TabTitle.fans
        case .temperatures: TabTitle.temperatures
        case .speedTest: TabTitle.speedTest
        case .ports: TabTitle.ports
        case .sound: TabTitle.sound
        case .keyboard: TabTitle.keyboard
        case .mouse: TabTitle.mouse
        case .windows: TabTitle.windows
        case .dock: TabTitle.dock
        case .finder: TabTitle.finder
        case .animations: TabTitle.animations
        case .player: TabTitle.player
        case .uninstaller: TabTitle.uninstaller
        case .background: TabTitle.background
        case .games: TabTitle.games
        case .pet: TabTitle.pet
        case .permissions: TabTitle.permissions
        case .about: TabTitle.about
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
