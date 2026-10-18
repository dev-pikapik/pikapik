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

    private var symbol: Symbol {
        switch self {
        case .general: .gearshapeFill
        case .battery: .battery100percent
        case .keepAwake: .cupAndSaucerFill
        case .brightness: .sunMaxFill
        case .fans: .fan
        case .temperatures: .thermometerMedium
        case .speedTest: .speedometer
        case .ports: .network
        case .sound: .speakerWave2Fill
        case .keyboard: .keyboardFill
        case .mouse: .computermouseFill
        case .windows: .macwindowOnRectangle
        case .dock: .dockRectangle
        case .finder: .folderFill
        case .animations: .hareFill
        case .player: .playRectangleFill
        case .uninstaller: .xmarkBinFill
        case .background: .gearshape2Fill
        case .games: .gamecontrollerFill
        case .pet: .pawprintFill
        case .permissions: .handRaisedFill
        case .about: .infoCircleFill
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
