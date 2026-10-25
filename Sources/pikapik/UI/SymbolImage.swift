import AppKit

// AppKit's own way to draw a symbol, taking a case of Symbol instead of a name typed by hand

extension NSImage {
    convenience init?(_ symbol: Symbol, accessibilityDescription: String?) {
        self.init(systemSymbolName: symbol.rawValue, accessibilityDescription: accessibilityDescription)
    }
}
