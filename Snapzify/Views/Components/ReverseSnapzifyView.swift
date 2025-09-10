import SwiftUI

struct ReverseSnapzifyView: View {
    @Binding var text: String
    let isTranslating: Bool
    let canTranslate: Bool
    let onTranslate: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: T.S.sm) {
            Text("Reverse Snapzify")
                .font(.title3)
                .foregroundStyle(T.C.ink)
            
            HStack(spacing: T.S.sm) {
                // Text field
                TextField("To translate...", text: $text)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundStyle(T.C.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(T.C.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(T.C.divider, lineWidth: 1)
                    )
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.go)
                    .onSubmit {
                        onTranslate()
                    }
                
                // Translate button
                Button(action: onTranslate) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(colors: [T.C.brandStart, T.C.brandEnd], 
                                         startPoint: .leading, 
                                         endPoint: .trailing)
                        )
                }
                .disabled(!canTranslate || isTranslating)
            }
        }
    }
}