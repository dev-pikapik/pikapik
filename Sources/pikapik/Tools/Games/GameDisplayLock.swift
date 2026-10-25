import AppKit
import SwiftUI

#if !APPSTORE
enum CursorLock {
    private typealias Lock = @convention(c) (Int32, UnsafeRawPointer?) -> Int32
    private typealias Connection = @convention(c) () -> Int32
    private typealias Region = @convention(c) (UnsafePointer<CGRect>, Int) -> Unmanaged<AnyObject>?

    private static let library = dlopen(SystemPath.skyLightFramework, RTLD_LAZY)
    private static let lock = dlsym(library, "SLSSetCursorRegionLock").map { unsafeBitCast($0, to: Lock.self) }
    private static let connection = dlsym(library, "SLSMainConnectionID").map { unsafeBitCast($0, to: Connection.self) }
    private static let region = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGRegionCreateWithRects").map { unsafeBitCast($0, to: Region.self) }

    static func hold(_ rects: [CGRect]?) -> Bool {
        guard let lock, let connection, let region else { return false }
        let shape = rects.flatMap { region($0, $0.count) }
        defer { shape?.release() }
        return (rects == nil || shape != nil) && lock(connection(), shape?.toOpaque()) == 0
    }
}
#endif

final class CursorFence {
    let frame: CGRect?
    let blocksAll: Bool
    let except: Set<Int64>
    let corners: Set<Int>
    fileprivate var holding: Bool?
    fileprivate private(set) var tap: CFMachPort?
    private var loop: CFRunLoop?

    init(frame: CGRect?, blocksAll: Bool, except: Set<Int64>, corners: Set<Int>) {
        self.frame = frame
        self.blocksAll = blocksAll
        self.except = except
        self.corners = corners
        let mask = CGEventMask(blocksAll || !except.isEmpty ? 1 << 30 : 0)
        guard mask != 0, AXIsProcessTrusted() else { return }
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            if let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: cursorFenceCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
                self.tap = tap
                loop = CFRunLoopGetCurrent()
            }
            ready.signal()
            if tap != nil { CFRunLoopRun() }
        }
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let loop { CFRunLoopStop(loop) }
    }
}

enum GameHint {
    private static var panel: NSPanel?

    static func show() {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        let view = NSHostingView(rootView: Text("To leave the game, press \(CommandKeysTool.quit.text)")
            .font(.title3.weight(.medium))
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .glassCard(cornerRadius: 22)
            .padding(12))
        let size = view.fittingSize
        let panel = panel ?? NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = view
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height, width: size.width, height: size.height), display: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.panel = panel
        let fade = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.3
        panel.alphaValue = fade == 0 ? 1 : 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = fade; panel.animator().alphaValue = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            NSAnimationContext.runAnimationGroup { $0.duration = fade; panel.animator().alphaValue = 0 } completionHandler: { panel.orderOut(nil) }
        }
    }
}


private func cursorFenceCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let fence = Unmanaged<CursorFence>.fromOpaque(refcon).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        if let tap = fence.tap { CGEvent.tapEnable(tap: tap, enable: true) }
    default:
        if type.rawValue == 30, event.getIntegerValueField(CGEventField(rawValue: 110)!) == 23 {
            let gate = GameRules.dropsSwipe(
                phase: event.getIntegerValueField(CGEventField(rawValue: 132)!),
                motion: event.getIntegerValueField(CGEventField(rawValue: 123)!),
                blocksAll: fence.blocksAll, except: fence.except, holding: fence.holding
            )
            fence.holding = gate.holding
            if gate.drops { return nil }
        }
    }
    return Unmanaged.passUnretained(event)
}
