import AppKit
import SwiftUI

struct KeepAwakeSettings: View {
    @Bindable private var keepAwake = KeepAwake.shared

    private static var shortcutsIcon: NSImage {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts")
            .map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage()
    }

    private func until(_ now: Date) -> Text {
        keepAwake.lastMode == .indefinitely
            ? Text("If turned on now, stays on until you turn it off")
            : Text("If turned on now, ends \(KeepAwake.until(now.addingTimeInterval(TimeInterval(keepAwake.duration))))")
    }

    var body: some View {
        Form {
            SettingsHeader(tab: .keepAwake, text: String(localized: "Keep your Mac from falling asleep"))
            Section {
                KeepAwakeArt()
                LabeledContent {
                    Picker("Keep your Mac awake", selection: Binding(get: { keepAwake.mode }, set: { keepAwake.set($0) })) {
                        Text("Off").tag(KeepAwake.Mode.off)
                        Text("For a while").tag(KeepAwake.Mode.timed)
                        Text("Indefinitely").tag(KeepAwake.Mode.indefinitely)
                    }
                    .labelsHidden()
                    .fixedSize()
                } label: {
                    RowLabel(Text("Keep your Mac awake"), keepAwake.statusText)
                }
                .settingAnchor(String(localized: "Keep your Mac awake"))
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Duration")
                        if keepAwake.mode == .off {
                            TimelineView(.everyMinute) { context in
                                until(context.date)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    DurationPicker(seconds: $keepAwake.duration)
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 4)
                .disabled(keepAwake.mode == .indefinitely)
                .settingAnchor(String(localized: "Duration"))
                VStack(alignment: .leading, spacing: 10) {
                    RowLabel(Text("Display"), keepAwake.keepsDisplayOn ? Text("No dimming, screen saver or lock screen") : Text("Turns off on its own timer, your Mac keeps working"))
                    Picker("Display", selection: $keepAwake.keepsDisplayOn) {
                        Text("Always on").tag(true)
                        Text("Turns off as usual").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 4)
                .settingAnchor(String(localized: "Display"))
                LabeledContent {
                    Button("Turn Off") { KeepAwake.turnOffDisplay() }
                } label: {
                    RowLabel(Text("Turn off the display now"), Text("Your Mac keeps working. To bring the display back, move the mouse or press a key."), row: "display-off")
                }
                .settingAnchor(String(localized: "Turn off the display now"))
            }

            if keepAwake.hasLid {
                Section {
                    Toggle(isOn: $keepAwake.worksWithLidClosed) {
                        RowLabel(Text("Work with the lid closed"), Text("Mac stays awake with the lid closed"))
                    }
                    .help(Text("Mac won’t sleep when you close the lid. Keep it ventilated."))
                    .settingAnchor(String(localized: "Work with the lid closed"))
                    Toggle(isOn: $keepAwake.stopsOnLowBattery) {
                        RowLabel(Text("Stop when battery is below \(0.2.formatted(.percent))"), Text("Lets the Mac sleep before the battery runs out"))
                    }
                    .disabled(!keepAwake.worksWithLidClosed)
                    .settingAnchor(String(localized: "Stop when battery is below \(0.2.formatted(.percent))"))
                    if let error = keepAwake.lidError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                } footer: {
                    Text("macOS will ask for your administrator password.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Section {
                ShortcutLink(title: String(localized: "Keep Awake"), path: "keep-awake")
                ShortcutLink(title: String(localized: "Keep the display on"), path: "display")
                if keepAwake.hasLid {
                    ShortcutLink(title: String(localized: "Work with the lid closed"), path: "lid-closed")
                }
                LabeledContent {
                    Button("Open Shortcuts", systemImage: "arrow.up.forward.app") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(nsImage: Self.shortcutsIcon)
                            .resizable()
                            .frame(width: SettingsTab.iconSize + 4, height: SettingsTab.iconSize + 4)
                            .accessibilityHidden(true)
                        Text("Shortcuts")
                    }
                }
            } header: {
                Text("Buttons in Control Center and widgets")
            } footer: {
                Text("Add the Open URLs action in Shortcuts, with a link.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .settingAnchor(String(localized: "Buttons in Control Center and widgets"))
            RestoreDefaultsSection(
                message: String(localized: "Keep Awake will turn off, and the duration and options will go back to how they were."),
                isDefault: keepAwake.isDefault
            ) {
                keepAwake.reset()
            }
        }
        .formStyle(.grouped)
        .settingsPage()
    }
}


private struct KeepAwakeArt: View {
    private let keepAwake = KeepAwake.shared

    var body: some View {
        KeepAwakeScene(
            on: keepAwake.mode != .off,
            bright: keepAwake.keepsDisplayOn,
            closed: keepAwake.hasLid && keepAwake.worksWithLidClosed,
            hasLid: keepAwake.hasLid,
            remaining: keepAwake.remaining
        )
    }
}

struct KeepAwakeScene: View {
    let on: Bool
    let bright: Bool
    let closed: Bool
    let hasLid: Bool
    let remaining: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Look: Equatable {
        let on: Bool
        let bright: Bool
        let closed: Bool
    }

    var body: some View {
        let glow = on ? (bright ? 1.0 : 0.6) : 0
        let monitor = closed || !hasLid
        IllustrationRow {
            ZStack(alignment: .bottom) {
                if hasLid {
                    ArtLaptop(lid: closed ? 1 : 0, glow: closed ? 0 : glow) { face }
                        .offset(x: closed ? -80 : 0)
                }
                ArtMonitor(glow: glow) { face }
                    .offset(x: hasLid ? 76 : 0)
                    .scaleEffect(monitor ? 1 : 0.85, anchor: .bottom)
                    .opacity(monitor ? 1 : 0)
            }
            .padding(.bottom, 22)
            .spring(Look(on: on, bright: bright, closed: closed), reduceMotion: reduceMotion)
        }
    }

    private var face: some View {
        ZStack {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.4))
                .opacity(on ? 0 : 1)
            Group {
                if let remaining {
                    Text(verbatim: remaining)
                } else {
                    Image(systemName: "infinity")
                }
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(.black.opacity(0.35), in: Capsule())
            .opacity(on ? 1 : 0)
        }
    }
}

struct ShortcutLink: View {
    let title: String
    let path: String
    @State private var copied = false

    private var link: String {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        let scheme = (types?.first?["CFBundleURLSchemes"] as? [String])?.first ?? "pikapik"
        return "\(scheme)://\(path)"
    }

    var body: some View {
        LabeledContent {
            Button(copied ? LocalizedStringKey("Copied") : "Copy Link", systemImage: copied ? "checkmark" : "link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    copied = false
                }
            }
            .contentTransition(.symbolEffect(.replace))
            .animation(.snappy, value: copied)
        } label: {
            RowLabel(Text(title), Text(verbatim: link))
                .textSelection(.enabled)
        }
    }
}
