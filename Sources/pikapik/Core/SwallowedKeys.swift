/// The key-downs a tap swallowed. A key-up is swallowed only when its key-down was, so a key that was already down
/// when ⌘ went down still comes up in the app instead of staying held there.
struct SwallowedKeys {
    private var codes: Set<Int64> = []

    /// Returns `swallow` and remembers it for this key's key-up.
    mutating func down(_ code: Int64, swallow: Bool) -> Bool {
        if swallow { codes.insert(code) } else { codes.remove(code) }
        return swallow
    }

    /// True when this key's key-down was swallowed; the key is forgotten then.
    mutating func up(_ code: Int64) -> Bool {
        codes.remove(code) != nil
    }

    mutating func removeAll() {
        codes.removeAll()
    }
}
