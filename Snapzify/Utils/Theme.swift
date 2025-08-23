import SwiftUI

enum T {
    enum C {
        static let bg = Color(hex: 0x0B0F14)
        static let card = Color(hex: 0x121823)
        static let cardElevated = Color(hex: 0x171F2B)
        static let divider = Color(hex: 0x263041)
        static let brandStart = Color(hex: 0x6A8DFF)
        static let brandEnd = Color(hex: 0x4E5FEA)
        static let accent = Color(hex: 0x22D1B2)
        static let accentAlt = Color(hex: 0xB07CFF)
        static let ink = Color(hex: 0xE9EDF6)
        static let ink2 = Color(hex: 0xA8B0C0)
        static let warning = Color(hex: 0xF2B45A)
        static let danger = Color(hex: 0xFF6B6B)
        static let outline = Color.white.opacity(0.08)
    }
    
    enum S {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
    }
}

extension LinearGradient {
    static var appBg: LinearGradient {
        LinearGradient(
            colors: [T.C.brandStart, T.C.brandEnd, Color(hex: 0x2B3550)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static var cta: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0x69F0DE), T.C.accent],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

struct RootBackground<Content: View>: View {
    @ViewBuilder var content: Content
    
    var body: some View {
        ZStack {
            LinearGradient.appBg.ignoresSafeArea()
            content
        }
    }
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                T.C.card.overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.black.opacity(0.6), radius: 24, x: 0, y: 8)
    }
}

extension View {
    func card() -> some View {
        modifier(CardModifier())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.black.opacity(0.9))
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .background(LinearGradient.cta)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        Color.white.opacity(configuration.isPressed ? 0.2 : 0.1),
                        lineWidth: 1
                    )
            )
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .foregroundStyle(T.C.ink)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(T.C.card)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(T.C.outline, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}