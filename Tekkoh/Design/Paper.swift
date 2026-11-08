import SwiftUI

/// Tekkoh's look, after a Hobonichi Techo: cream paper with a fine grid,
/// serif dates, a vermillion accent for the day and the streak stamp, and
/// the weekday in Japanese as a small printed mark.
enum Ink {
    static let paper = Color(light: 0xF6F1E7, dark: 0x1B1A17)
    static let paperEdge = Color(light: 0xECE5D6, dark: 0x13120F)
    static let grid = Color(light: 0xD5DCDD, dark: 0x2C2A26)
    static let text = Color(light: 0x26231F, dark: 0xE9E3D6)
    static let muted = Color(light: 0x8A8377, dark: 0x8F887B)
    static let faint = Color(light: 0xB9B2A5, dark: 0x5A554C)
    static let vermillion = Color(light: 0xC8432B, dark: 0xE0634A)
    static let indigo = Color(light: 0x3E6A9A, dark: 0x7FA4CC)
    static let card = Color(light: 0xFFFDF8, dark: 0x262420)

    /// Grid pitch: Hobonichi's 3.7 mm squares, a touch larger for a phone.
    static let pitch: CGFloat = 12
    /// A line of writing spans two squares.
    static let line: CGFloat = 24
}

extension Font {
    static func serif(_ size: CGFloat, _ weight: Weight = .regular) -> Font { .system(size: size, weight: weight, design: .serif) }
    /// Small printed labels in the margin.
    static func label(_ size: CGFloat = 10) -> Font { .system(size: size, weight: .medium, design: .monospaced) }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

/// Graph paper, with the grid's origin at the view's top leading corner.
struct GridPaper: View {
    var inset: CGFloat = 0

    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            var x = inset
            while x <= size.width - inset {
                p.move(to: CGPoint(x: x, y: inset)); p.addLine(to: CGPoint(x: x, y: size.height - inset))
                x += Ink.pitch
            }
            var y = inset
            while y <= size.height - inset {
                p.move(to: CGPoint(x: inset, y: y)); p.addLine(to: CGPoint(x: size.width - inset, y: y))
                y += Ink.pitch
            }
            ctx.stroke(p, with: .color(Ink.grid), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A page: paper with a soft edge, as on a notebook.
struct PageBackground: View {
    var body: some View {
        Ink.paper.ignoresSafeArea()
    }
}

/// The streak as a hanko stamp: vermillion, slightly worn, a little askew.
struct StreakStamp: View {
    let days: Int
    var size: CGFloat = 46
    var lit = true

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(lit ? Ink.vermillion : Ink.faint, lineWidth: size * 0.06)
            Circle()
                .strokeBorder((lit ? Ink.vermillion : Ink.faint).opacity(0.45), style: StrokeStyle(lineWidth: 0.6, dash: [1.5, 2.5]))
                .padding(size * 0.11)
            VStack(spacing: -size * 0.04) {
                Text("\(days)")
                    .font(.system(size: size * (days > 99 ? 0.3 : 0.38), weight: .bold, design: .serif))
                    .monospacedDigit()
                Text("連続")
                    .font(.system(size: size * 0.16, weight: .semibold, design: .serif))
            }
            .foregroundStyle(lit ? Ink.vermillion : Ink.faint)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(-8))
        .opacity(lit ? 0.92 : 0.7)
        .accessibilityElement()
        .accessibilityLabel("\(days)-day streak")
    }
}

/// An ensō: Tekkoh's mark, a brush circle left open.
struct Enso: View {
    var size: CGFloat = 120
    var color: Color = Ink.vermillion

    var body: some View {
        Canvas { ctx, s in
            let c = CGPoint(x: s.width / 2, y: s.height / 2)
            let r = min(s.width, s.height) * 0.4
            // Built from strokes of falling width, like a brush lifting.
            let steps = 140
            for i in 0..<steps {
                let t0 = Double(i) / Double(steps), t1 = Double(i + 1) / Double(steps)
                let a0 = Angle.degrees(-70 + 330 * t0), a1 = Angle.degrees(-70 + 330 * t1)
                var p = Path()
                p.addArc(center: c, radius: r + CGFloat(sin(t0 * 9)) * r * 0.012, startAngle: a0, endAngle: a1, clockwise: false)
                let w = r * (0.2 - 0.17 * t0) * (t0 < 0.05 ? CGFloat(t0 / 0.05) * 0.6 + 0.4 : 1)
                ctx.stroke(p, with: .color(color.opacity(0.88 - 0.25 * t0)), style: StrokeStyle(lineWidth: max(w, 1), lineCap: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

enum Weekday {
    static let kanji = ["日", "月", "火", "水", "木", "金", "土"]

    static func of(_ day: String) -> Int { Calendar(identifier: .gregorian).component(.weekday, from: Day.date(day)) - 1 }

    /// Sundays red, Saturdays blue, as Japanese calendars print them.
    static func color(_ day: String) -> Color {
        switch of(day) {
        case 0: return Ink.vermillion
        case 6: return Ink.indigo
        default: return Ink.text
        }
    }
}
