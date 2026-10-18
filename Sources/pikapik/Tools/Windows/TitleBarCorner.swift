import CoreGraphics
import Foundation

/// The window buttons sit in a corner of the title bar: top left, or top right in right-to-left languages.
enum TitleBarCorner {
    static let width: CGFloat = 120
    static let height: CGFloat = 60

    /// The app whose front window under the point has the point in a title bar corner. `windows` is the on-screen list,
    /// front to back, as `CGWindowListCopyWindowInfo` returns it. Windows above the normal level (menus, the Dock,
    /// overlays that let clicks through) and invisible ones are skipped.
    static func owner(at point: CGPoint, in windows: [[String: Any]], except me: pid_t = getpid()) -> pid_t? {
        for info in windows {
            guard info[kCGWindowLayer as String] as? Int == 0, (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  info[kCGWindowOwnerName as String] as? String != "Dock",
                  let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) }),
                  bounds.contains(point)
            else { continue }
            guard point.y - bounds.minY < height, point.x - bounds.minX < width || bounds.maxX - point.x < width,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != me
            else { return nil }
            return pid
        }
        return nil
    }
}
