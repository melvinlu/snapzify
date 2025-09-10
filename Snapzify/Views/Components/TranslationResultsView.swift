import SwiftUI

struct TranslationResultsView: View {
    let result: TranslationResult
    let onSelect: (ChineseTranslation) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: T.S.lg) {
            // Header
            VStack(alignment: .leading, spacing: T.S.xs) {
                Text("Translations for:")
                    .font(.caption)
                    .foregroundStyle(T.C.ink2)
                
                Text(result.query)
                    .font(.headline)
                    .foregroundStyle(T.C.ink)
            }
            .padding(.horizontal)
            
            Divider()
                .background(T.C.divider)
            
            // Translation options
            ScrollView {
                VStack(spacing: T.S.md) {
                    ForEach(Array(result.translations.enumerated()), id: \.element) { index, translation in
                        TranslationCard(
                            translation: translation,
                            rank: index + 1,
                            onSelect: { onSelect(translation) }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }
}

struct TranslationCard: View {
    let translation: ChineseTranslation
    let rank: Int
    let onSelect: () -> Void
    
    @State private var isPressed = false
    
    private var formalityColor: Color {
        switch translation.formality {
        case "formal":
            return T.C.accentAlt
        case "informal":
            return T.C.accent
        default:
            return T.C.ink2
        }
    }
    
    private var formalityIcon: String {
        switch translation.formality {
        case "formal":
            return "tie"
        case "informal":
            return "face.smiling"
        default:
            return "circle"
        }
    }
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: T.S.sm) {
                // Header with rank and formality
                HStack {
                    // Rank badge
                    Text("#\(rank)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(T.C.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(rank == 1 ? T.C.accent : T.C.cardElevated)
                        )
                    
                    Spacer()
                    
                    // Formality indicator
                    HStack(spacing: 4) {
                        Image(systemName: formalityIcon)
                            .font(.caption)
                        Text(translation.formality.capitalized)
                            .font(.caption)
                    }
                    .foregroundStyle(formalityColor)
                }
                
                // Main Chinese text with pinyin
                VStack(alignment: .leading, spacing: 4) {
                    Text(translation.chinese)
                        .font(.title2.weight(.medium))
                        .foregroundStyle(T.C.ink)
                    
                    Text(translation.pinyin)
                        .font(.subheadline)
                        .foregroundStyle(T.C.ink2)
                }
                
                // Context badge
                HStack {
                    Label(translation.context, systemImage: "tag.fill")
                        .font(.caption)
                        .foregroundStyle(T.C.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(T.C.cardElevated)
                        )
                }
                
                // Usage example
                VStack(alignment: .leading, spacing: 4) {
                    Text("Example:")
                        .font(.caption2)
                        .foregroundStyle(T.C.ink2)
                    
                    Text(translation.usage)
                        .font(.footnote)
                        .foregroundStyle(T.C.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
                
                // Tap to use indicator
                HStack {
                    Spacer()
                    Text("Tap to use this translation")
                        .font(.caption2)
                        .foregroundStyle(T.C.accent)
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.caption)
                        .foregroundStyle(T.C.accent)
                }
                .padding(.top, 4)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(T.C.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isPressed ? T.C.accent : T.C.divider, lineWidth: isPressed ? 2 : 1)
                    )
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity) { isPressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = isPressing
            }
        } perform: {
            // Long press action if needed
        }
    }
}

// MARK: - Loading View
struct TranslationLoadingView: View {
    @State private var animationAmount = 0.0
    
    var body: some View {
        VStack(spacing: T.S.lg) {
            HStack(spacing: T.S.sm) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(T.C.accent)
                        .frame(width: 12, height: 12)
                        .scaleEffect(animationAmount)
                        .opacity(2 - animationAmount)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2),
                            value: animationAmount
                        )
                }
            }
            
            Text("Translating...")
                .font(.headline)
                .foregroundStyle(T.C.ink2)
        }
        .onAppear {
            animationAmount = 2
        }
    }
}

// MARK: - Error View
struct TranslationErrorView: View {
    let message: String
    let onRetry: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: T.S.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(T.C.danger)
            
            Text("Translation Error")
                .font(.headline)
                .foregroundStyle(T.C.ink)
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(T.C.ink2)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            HStack(spacing: T.S.md) {
                Button("Dismiss") {
                    onDismiss()
                }
                .buttonStyle(SecondaryButtonStyle())
                
                Button("Retry") {
                    onRetry()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding()
    }
}

// MARK: - Not Configured View
struct TranslationNotConfiguredView: View {
    var body: some View {
        VStack(spacing: T.S.lg) {
            Image(systemName: "key.horizontal")
                .font(.largeTitle)
                .foregroundStyle(T.C.accent)
            
            Text("OpenAI API Key Required")
                .font(.headline)
                .foregroundStyle(T.C.ink)
            
            Text("Please configure your OpenAI API key in Settings to use Reverse Snapzify.")
                .font(.subheadline)
                .foregroundStyle(T.C.ink2)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Open Settings") {
                // Open settings
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding()
    }
}