import SwiftUI

struct DisplayScaleSettings: View {
    private let model = DisplayScale.shared

    var body: some View {
        Form {
            SettingsHeader(tab: .displays, text: String(localized: "Make everything on a monitor larger and keep it sharp"))
            // A monitor that stayed off after getting its own sizes is not listed, so its card cannot say so.
            if let failure = model.failure, case .dark = failure.problem, !model.monitors.contains(where: { $0.id == failure.monitor }) {
                Section {
                    Label { Text(MonitorSection.message(failure)) } icon: { Image(.exclamationmarkTriangleFill).foregroundStyle(.orange) }
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if model.monitors.isEmpty {
                Section {
                    Text("Connect a monitor to choose its size.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .settingAnchor(SettingTitle.displayScale)
                }
            } else {
                ForEach(model.monitors) { monitor in
                    MonitorSection(
                        monitor: monitor,
                        anchor: monitor.id == model.monitors.first?.id ? SettingTitle.displayScale : "display-scale-\(monitor.id)"
                    )
                }
            }
            if model.hasBuiltIn {
                Section {
                    SystemSettingsRow(
                        title: String(localized: "Built-in display"),
                        subtitle: Text("Its size is set in System Settings › Displays"),
                        url: SystemPane.displays
                    )
                }
            }
        }
        .formStyle(.grouped)
        .settingsPage()
        .environment(\.inSettings, true)
        .whileShown { if $0 { model.refresh() } }
    }
}

private struct MonitorSection: View {
    let monitor: DisplayScale.Monitor
    let anchor: String
    private let model = DisplayScale.shared
    @State private var selected: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(monitor: DisplayScale.Monitor, anchor: String) {
        self.monitor = monitor
        self.anchor = anchor
        _selected = State(initialValue: Self.size(for: monitor, failure: DisplayScale.shared.failure))
    }

    /// The size the card shows: the one a failure names, so its button tries that size again, or else the one in use.
    private static func size(for monitor: DisplayScale.Monitor, failure: DisplayScale.Failure?) -> Int {
        if let failure, failure.monitor == monitor.id, monitor.steps.contains(failure.percent) { return failure.percent }
        return monitor.steps.min { abs($0 - monitor.current) < abs($1 - monitor.current) } ?? 100
    }

    private var name: String { monitor.name.isEmpty ? String(localized: "Monitor") : monitor.name }

    private var caption: String {
        let resolution = "\(monitor.nativeWidth.formatted(.number.grouping(.never))) × \(monitor.nativeHeight.formatted(.number.grouping(.never)))"
        guard monitor.millimeters.width > 0, monitor.millimeters.height > 0 else { return resolution }
        let inches = Measurement(value: hypot(monitor.millimeters.width, monitor.millimeters.height) / 25.4, unit: UnitLength.inches)
        return inches.formatted(.measurement(width: .narrow, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))) + " · " + resolution
    }

    /// Why the slider has a size such as 135 %: it stands in for a step the monitor's port can't show sharply.
    private var substitution: String? {
        guard let offered = monitor.steps.first(where: { !DisplayScaleMath.steps.contains($0) }),
              let missing = DisplayScaleMath.steps.filter({ $0 > 100 && $0 < offered && !monitor.steps.contains($0) }).max() else { return nil }
        let (shown, closest) = (missing.formatted(.percent), offered.formatted(.percent))
        // Another port helps only when the step fits the widest pipe there is.
        return DisplayScaleMath.steps(nativeWidth: monitor.nativeWidth, nativeHeight: monitor.nativeHeight).contains(missing)
            ? String(localized: "Through this port the Mac can’t show \(shown) sharply, so pikapik offers \(closest), the closest sharp size. Another port on the Mac may allow \(shown).")
            : String(localized: "The Mac can’t show this monitor at \(shown) sharply, so pikapik offers \(closest), the closest sharp size.")
    }

    var body: some View {
        Section {
            if monitor.available {
                VStack(spacing: 0) {
                    DisplayScalePreview(nativeWidth: monitor.nativeWidth, nativeHeight: monitor.nativeHeight, percent: selected)
                        .frame(maxWidth: 460, maxHeight: 250)
                        .padding(.top, 10)
                    readout
                        .padding(.top, 18)
                    if monitor.steps.count > 1 {
                        ScaleSlider(steps: monitor.steps, selected: $selected, name: name)
                            .padding(.top, 22)
                        if let substitution {
                            Text(substitution)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: 460)
                                .padding(.top, 12)
                        }
                        apply
                            .padding(.top, 22)
                    } else {
                        SystemSettingsRow(
                            title: String(localized: "No larger sizes for this monitor"),
                            subtitle: Text("Its size is set in System Settings › Displays"),
                            url: SystemPane.displays
                        )
                        .padding(.top, 22)
                    }
                    // The one text here that asks for something: as strong as the rest, not faint.
                    if let failure = model.failure, failure.monitor == monitor.id {
                        Label { Text(Self.message(failure)) } icon: { Image(.exclamationmarkTriangleFill).foregroundStyle(.orange) }
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 14)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .settingAnchor(anchor)
            } else {
                VStack {
                    SystemSettingsRow(
                        title: String(localized: "Shows the same picture as another screen"),
                        subtitle: Text("To choose its size here, set “Use as” to “Extended display” in System Settings › Displays"),
                        url: SystemPane.displays
                    )
                }
                .settingAnchor(anchor)
            }
        } header: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(name)
                // The feature is new, not each monitor: one tag, on the first monitor, where search leads.
                if anchor == SettingTitle.displayScale { NewRowTag(row: ToolID.displayScale) }
                Spacer(minLength: 12)
                Text(verbatim: caption)
                    .fontWeight(.regular)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            if monitor.available && selected != monitor.usual {
                VStack(alignment: .leading, spacing: 4) {
                    Text("pikapik keeps this size while it runs, also in the background. When pikapik quits completely, the monitor goes back to its usual size.")
                    if monitor.virtualSteps.contains(selected) { Text("Some video apps may show a black picture at this size.") }
                    if monitor.virtualSteps.contains(selected), !FanControl.isInstalled, HelperAccess.isAdmin(getuid()) {
                        Text("To show this size without the extra screen, turn on Administrator access in Settings › Permissions. macOS will ask for your password once.")
                    }
                    if let virtual = monitor.virtualName, monitor.virtualSteps.contains(selected) {
                        Text("In System Settings › Displays you’ll see one more screen, “\(virtual)”: that’s how pikapik makes everything larger, and you don’t need to do anything with it.")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: monitor) { old, new in
            if old.current != new.current || !new.steps.contains(selected) { selected = Self.size(for: new, failure: model.failure) }
        }
        .onChange(of: model.failure) { _, failure in
            guard let failure, failure.monitor == monitor.id else { return }
            selected = Self.size(for: monitor, failure: failure)
            NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [
                .announcement: Self.message(failure),
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
        }
    }

    private var readout: some View {
        VStack(spacing: 4) {
            Text(selected, format: .percent)
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText(value: Double(selected)))
                .animation(reduceMotion ? nil : .snappy, value: selected)
            let size = monitor.looksLike(selected)
            Text("Looks like \(size.width.formatted(.number.grouping(.never))) × \(size.height.formatted(.number.grouping(.never)))")
                .font(.title3)
                .foregroundStyle(.secondary)
            if !monitor.steps.contains(monitor.current) {
                Text("In use now: \(monitor.current.formatted(.percent))")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }

    private var apply: some View {
        let isCurrent = selected == monitor.current
        let inUse = isCurrent && model.busy != monitor.id
        return Button {
            model.choose(selected, for: monitor.id)
        } label: {
            HStack(spacing: 8) {
                if model.busy == monitor.id { ProgressView().controlSize(.small) }
                if isCurrent { Text("In Use") } else { Text("Use \(selected.formatted(.percent))") }
            }
            .frame(minWidth: 140)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isCurrent || !MainCopy.canAct || model.pending != nil || model.busy != nil)
        // The size in use reads as plain text with a check, not as a dimmed button that is hard to read; the hidden
        // button keeps its room, so the card does not move when the slider leaves that size.
        .opacity(inUse ? 0 : 1)
        .accessibilityHidden(inUse)
        .overlay {
            if inUse {
                Label { Text("In Use") } icon: { Image(.checkmarkCircleFill).foregroundStyle(.green) }
                    .font(.title3)
            }
        }
    }

    static func message(_ failure: DisplayScale.Failure) -> String {
        let percent = failure.percent.formatted(.percent)
        return switch failure.problem {
        case .unavailable: String(localized: "This Mac can’t show the monitor at \(percent) right now. Try another size.")
        case .refused: String(localized: "macOS didn’t switch the monitor to \(percent). Nothing changed. Try again.")
        case .lost: String(localized: "The monitor didn’t stay at \(percent) and went back. Try again.")
        case .notBack: String(localized: "The monitor couldn’t go back to \(percent). Choose a size again.")
        case .dark(let name): String(localized: "The “\(name)” screen didn’t come back. Unplug its cable and plug it in again.")
        }
    }
}

/// The steps on a slider: tick marks named by their percent, a small "A" at the "More space" end and a large one at
/// the "Larger text" end. The arrow keys move one step.
private struct ScaleSlider: View {
    let steps: [Int]
    @Binding var selected: Int
    let name: String
    @State private var track: CGFloat = 16

    var body: some View {
        let index = Binding<Double>(
            get: { Double(steps.firstIndex(of: selected) ?? 0) },
            set: { selected = steps[min(max(Int($0.rounded()), 0), steps.count - 1)] }
        )
        let half = track / 2
        VStack(spacing: 8) {
            HStack(alignment: .sliderTrack, spacing: 12) {
                Image(.textformatSizeSmaller)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Group {
                    if #available(macOS 26, *) {
                        Slider(value: index, in: 0...Double(steps.count - 1), step: 1) {
                            Text(verbatim: "\(SettingTitle.displayScale), \(name)")
                        } tick: { value in
                            SliderTick(value) { Text(steps[Int(value)], format: .percent).font(.callout) }
                        }
                    } else {
                        Slider(value: index, in: 0...Double(steps.count - 1), step: 1) {
                            Text(verbatim: "\(SettingTitle.displayScale), \(name)")
                        }
                    }
                }
                .labelsHidden()
                .accessibilityValue(Text(selected, format: .percent))
                .alignmentGuide(.sliderTrack) { $0[.top] + half }
                Image(.textformatSizeLarger)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            HStack {
                Text("More space")
                Spacer(minLength: 12)
                Text("Larger text")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: 460)
        .background {
            // A slider's track sits in its top part, as tall as a slider without tick labels.
            Slider(value: .constant(0.5))
                .labelsHidden()
                .hidden()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { track = $0 }
        }
    }
}

private extension VerticalAlignment {
    private enum SliderTrack: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context[VerticalAlignment.center] }
    }

    static let sliderTrack = VerticalAlignment(SliderTrack.self)
}
