import SwiftUI

struct LayoutFixArt: View {
    let on: Bool
    var service: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let typing = [1.4, 0.35, 1.6, 0.6]
    private static let menu = [1.2, 0.15, 0.5, 0.7, 0.45, 0.2, 2.0]
    private static let click = CGPoint(x: 56, y: 40)

    private static let sample: (typed: String, word: String, from: String, to: String) = {
        let greetings = ["ru": "привет", "uk": "привіт", "bg": "здравей", "sr": "здраво", "mk": "здраво", "el": "γεια", "he": "שלום", "ar": "مرحبا", "fa": "سلام", "hi": "नमस्ते", "th": "สวัสดี", "ka": "გამარჯობა", "hy": "բարև"]
        let all = KeyboardLayouts.all
        for target in all {
            guard let word = greetings[String(target.language.prefix { $0 != "-" && $0 != "_" })], target.canType(word),
                  let source = all.first(where: { $0.language != target.language && $0.canType("a") }) else { continue }
            let typed = KeyboardLayouts.convert(word, from: target, to: source)
            if typed != word, !typed.contains(where: \.isWhitespace) { return (typed, word, LayoutFixArt.badge(source), LayoutFixArt.badge(target)) }
        }
        return ("ghbdtn", "привет", "EN", "RU")
    }()

    static func badge(_ layout: KeyboardLayout) -> String { String(layout.language.prefix(2)).uppercased() }

    var body: some View {
        if let service { menuScene(service) } else { typingScene }
    }

    private var typingScene: some View {
        IllustrationRow(loop: Self.typing) { tick in
            let step = reduceMotion ? 2 : tick % Self.typing.count
            let fixed = on && step >= 2
            Stage {
                field(fixed ? Self.sample.word : Self.sample.typed, badge: fixed ? Self.sample.to : Self.sample.from, flash: on && step == 2)
                    .position(x: 150, y: 40)
                ArtKey(down: step == 1, width: 120) { Text("Space") }
                    .position(x: 150, y: 96)
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: step)
        }
    }

    private func menuScene(_ service: String) -> some View {
        IllustrationRow(loop: Self.menu) { tick in
            let step = reduceMotion ? 6 : tick % Self.menu.count
            let click = Self.click
            let row = CGPoint(x: click.x + 40, y: click.y + 26)
            let item = CGPoint(x: click.x + 150, y: click.y + 26)
            Stage {
                field(step == 6 ? Self.sample.word : Self.sample.typed, badge: nil, selected: step < 6)
                    .position(x: 100, y: 40)
                if (2...5).contains(step) {
                    ArtMenu(width: 90) {
                        ArtMenuRow(width: 34)
                        ArtMenuRow(title: Text("Services"), active: step >= 3, submenu: true)
                        ArtMenuRow(width: 48)
                    }
                    .position(x: click.x + 45, y: click.y + 26)
                    .transition(.scale(scale: 0.85, anchor: .topLeading).combined(with: .opacity))
                }
                if (3...5).contains(step) {
                    ArtMenu(width: 150) {
                        ArtMenuRow(title: Text(verbatim: service), active: step >= 4)
                    }
                    .position(x: click.x + 163, y: click.y + 26)
                    .transition(.opacity)
                }
                if (1...2).contains(step) { ArtRipple().position(click) }
                if step == 5 { ArtRipple().position(item) }
                ArtCursor(pressed: step == 1 || step == 5)
                    .cursor(at: [CGPoint(x: 236, y: 104), click, click, row, item, item, item][step])
                    .opacity(step == 6 ? 0 : 1)
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: step)
        }
    }

    private func field(_ text: String, badge: String?, flash: Bool = false, selected: Bool = false) -> some View {
        HStack(spacing: 0) {
            Text(verbatim: text)
                .font(.system(size: 13))
                .background(selected ? Color.accentColor.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            if !selected {
                Rectangle().fill(Color.accentColor).frame(width: 1.5, height: 16)
            }
            Spacer(minLength: 0)
            if let badge {
                Text(verbatim: badge)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(flash ? Color.white : Color.primary)
                    .frame(width: 26, height: 16)
                    .background(flash ? Color.accentColor : Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 180, height: 34)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).hairline(Color.primary.opacity(0.18)))
    }
}
