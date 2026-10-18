import SwiftUI

// SwiftUI's own ways to draw a symbol, taking a case of Symbol instead of a name typed by hand

extension Image {
    init(_ symbol: Symbol) {
        self.init(systemName: symbol.rawValue)
    }
}

extension Label where Title == Text, Icon == Image {
    init(_ titleKey: LocalizedStringKey, symbol: Symbol) {
        self.init(titleKey, systemImage: symbol.rawValue)
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, symbol: Symbol) {
        self.init(title, systemImage: symbol.rawValue)
    }
}

extension Button where Label == SwiftUI.Label<Text, Image> {
    init(_ titleKey: LocalizedStringKey, symbol: Symbol, action: @escaping () -> Void) {
        self.init(titleKey, systemImage: symbol.rawValue, action: action)
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, symbol: Symbol, action: @escaping () -> Void) {
        self.init(title, systemImage: symbol.rawValue, action: action)
    }
}
