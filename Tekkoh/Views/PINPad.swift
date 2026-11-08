import SwiftUI

/// Six digits, entered on a quiet keypad: circles fill as you type.
struct PINPad: View {
    let title: String
    var subtitle: String = ""
    var error: String?
    let done: (String) -> Void
    @State private var digits = ""
    @State private var shake = 0

    var body: some View {
        VStack(spacing: 26) {
            VStack(spacing: 8) {
                Text(title).font(.serif(22)).foregroundStyle(Ink.text).multilineTextAlignment(.center)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.serif(14)).foregroundStyle(Ink.muted).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 16) {
                ForEach(0..<6, id: \.self) { i in
                    Circle()
                        .fill(i < digits.count ? Ink.vermillion : .clear)
                        .overlay(Circle().strokeBorder(i < digits.count ? Ink.vermillion : Ink.faint, lineWidth: 1))
                        .frame(width: 13, height: 13)
                }
            }
            .modifier(Shake(amount: CGFloat(shake)))
            .animation(.default, value: shake)
            Text(error ?? " ").font(.label(11)).foregroundStyle(Ink.vermillion).frame(height: 14)
            Grid(horizontalSpacing: 26, verticalSpacing: 14) {
                ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9]], id: \.self) { row in
                    GridRow { ForEach(row, id: \.self) { n in key("\(n)") } }
                }
                GridRow {
                    Color.clear.frame(width: 68, height: 68)
                    key("0")
                    Button { if !digits.isEmpty { digits.removeLast() } } label: {
                        Image(systemName: "delete.left").font(.system(size: 20, weight: .light)).foregroundStyle(Ink.muted)
                            .frame(width: 68, height: 68)
                    }
                    .accessibilityLabel("Delete")
                }
            }
        }
        .onChange(of: error) { _, e in
            if e != nil { shake += 1; digits = "" }
        }
    }

    private func key(_ d: String) -> some View {
        Button {
            guard digits.count < 6 else { return }
            digits += d
            if digits.count == 6 {
                let pin = digits
                Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    done(pin)
                    digits = ""
                }
            }
        } label: {
            Text(d)
                .font(.serif(28, .light))
                .foregroundStyle(Ink.text)
                .frame(width: 68, height: 68)
                .overlay(Circle().strokeBorder(Ink.grid, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: digits)
    }
}

struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(amount * .pi * 4), y: 0))
    }
}
