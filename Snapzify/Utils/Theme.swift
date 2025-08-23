import SwiftUI

enum T {
    enum C {
        static let bg = Color(hex: 0x000000)  // Pure black
        static let card = Color(hex: 0x0A0A0A)  // Very dark gray
        static let cardElevated = Color(hex: 0x141414)  // Slightly lighter dark gray
        static let divider = Color(hex: 0x1F1F1F)  // Dark divider
        static let brandStart = Color(hex: 0x3B82F6)  // Modern blue
        static let brandEnd = Color(hex: 0x8B5CF6)  // Modern purple
        static let accent = Color(hex: 0x10B981)  // Modern emerald
        static let accentAlt = Color(hex: 0xA855F7)  // Modern violet
        static let ink = Color(hex: 0xF5F5F5)  // Off-white
        static let ink2 = Color(hex: 0x9CA3AF)  // Muted gray
        static let warning = Color(hex: 0xF59E0B)  // Modern amber
        static let danger = Color(hex: 0xEF4444)  // Modern red
        static let outline = Color.white.opacity(0.05)  // Very subtle outline
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
            colors: [
                Color(hex: 0x8B5CF6),  // Light purple at top-left
                Color(hex: 0x6366F1),  // Purple-blue blend
                Color(hex: 0x3B82F6),  // Cyan-blue hint
                Color(hex: 0x312E81),  // Dark purple-blue
                Color(hex: 0x1E1B4B)   // Very dark purple at bottom-right
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static var cta: LinearGradient {
        LinearGradient(
            colors: [T.C.brandStart, T.C.brandEnd],  // Blue to purple gradient
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
            Color(hex: 0x1C1C1E).ignoresSafeArea()  // Dark modern steel gray
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
                            Color.white.opacity(0.02),  // Very subtle gradient
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)  // Slightly smaller radius
                    .stroke(Color.white.opacity(0.03), lineWidth: 0.5)  // More subtle border
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Color.black.opacity(0.8), radius: 16, x: 0, y: 4)  // Darker, tighter shadow
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
            .foregroundStyle(Color.white)  // White text on gradient
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .background(LinearGradient.cta)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        Color.white.opacity(configuration.isPressed ? 0.1 : 0.05),
                        lineWidth: 0.5
                    )
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
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
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(T.C.outline, lineWidth: 0.5)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}