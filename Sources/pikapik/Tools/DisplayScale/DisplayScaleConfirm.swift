import AppKit
import SwiftUI

/// The small panel that asks to keep a new size, in the middle of the monitor that changed. Doing nothing for
/// 15 seconds puts the old size back, so a size that leaves the screen unreadable undoes itself.
@MainActor enum DisplayScaleConfirm {
    private static var panel: NSPanel?
    private static var screens: NSObjectProtocol?

    static func show() {
        guard let pending = DisplayScale.shared.pending else { return }
        let panel = Self.panel ?? makePanel()
        let controller = NSHostingController(rootView: DisplayScaleConfirmView(pending: pending))
        // Measured once: the content never changes size. With .preferredContentSize AppKit asks SwiftUI for the size in
        // every constraints pass, and while the screens change under the panel that loops until AppKit throws.
        controller.sizingOptions = []
        panel.contentViewController = controller
        panel.setContentSize(controller.sizeThatFits(in: NSSize(width: CGFloat.infinity, height: .infinity)))
        Self.panel = panel
        place(panel)
        if screens == nil {
            screens = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { if let panel = DisplayScaleConfirm.panel { place(panel) } }
            }
        }
        NSApp.bringForward()
        panel.makeKeyAndOrderFront(nil)
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [
            .announcement: String(localized: "Keep this size?") + " " + String(localized: "If you do nothing, the display goes back to \(pending.from.formatted(.percent))."),
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    static func hide() {
        if let screens { NotificationCenter.default.removeObserver(screens) }
        screens = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private static func makePanel() -> NSPanel {
        // Titled without close, minimize or zoom: rounded corners and a shadow, and no window buttons.
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = String(localized: "Keep this size?")
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    /// The middle of the monitor that changed, wherever it shows now; the screens move while the size changes.
    private static func place(_ panel: NSPanel) {
        guard let id = DisplayScale.shared.pending?.monitor, let area = DisplayScale.shared.screen(for: id)?.visibleFrame else {
            panel.center()
            return
        }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: (area.midX - size.width / 2).rounded(), y: (area.midY - size.height / 2).rounded()))
    }
}

struct DisplayScaleConfirmView: View {
    let pending: DisplayScale.Pending
    private let model = DisplayScale.shared

    var body: some View {
        VStack(spacing: 0) {
            Countdown(deadline: pending.deadline)
            Text("Keep this size?")
                .font(.title2.bold())
                .padding(.top, 18)
            // What happens next, for someone who cannot read the screen at this size: as strong as the question.
            Text("If you do nothing, the display goes back to \(pending.from.formatted(.percent)).")
                .font(.title3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            HStack(spacing: 12) {
                Button { model.goBack() } label: { Text("Go Back").frame(maxWidth: .infinity) }
                    .glassButtons()
                    .keyboardShortcut(.cancelAction)
                Button { model.keep() } label: { Text("Keep").frame(maxWidth: .infinity) }
                    .glassProminentButtons()
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.top, 24)
        }
        .padding(EdgeInsets(top: 30, leading: 28, bottom: 24, trailing: 28))
        .frame(width: 360)
        // The hidden title bar keeps no room: the padding above is the whole margin.
        .ignoresSafeArea()
    }
}

/// A ring that empties over the 15 seconds, with the seconds left in it. With Reduce Motion it moves once a second.
private struct Countdown: View {
    let deadline: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let length: TimeInterval = 15

    var body: some View {
        Group {
            if reduceMotion {
                TimelineView(.periodic(from: deadline.addingTimeInterval(-Self.length), by: 1)) { ring(at: $0.date) }
            } else {
                TimelineView(.animation) { ring(at: $0.date) }
            }
        }
        .frame(width: 68, height: 68)
    }

    private func ring(at date: Date) -> some View {
        let left = min(max(deadline.timeIntervalSince(date), 0), Self.length)
        let seconds = Int(left.rounded(.up))
        return ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 6)
            Circle()
                .trim(from: 0, to: left / Self.length)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(seconds, format: .number)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .padding(3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Time left"))
        .accessibilityValue(Text(Duration.seconds(seconds).formatted(.units(allowed: [.seconds], width: .wide))))
    }
}
