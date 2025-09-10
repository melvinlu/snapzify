import SwiftUI

struct BreakdownView: View {
    @Binding var text: String
    @Binding var breakdownResult: String
    let isBreakingDown: Bool
    let onBreakdown: () -> Void
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: T.S.sm) {
            HStack(spacing: T.S.sm) {
                // Text field
                TextField("Breakdown Chinese text...", text: $text)
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
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        onBreakdown()
                        isTextFieldFocused = false
                    }
                
                // Breakdown button
                Button {
                    isTextFieldFocused = false
                    onBreakdown()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(colors: [T.C.brandStart, T.C.brandEnd], 
                                         startPoint: .leading, 
                                         endPoint: .trailing)
                        )
                }
                .disabled(text.isEmpty || isBreakingDown)
            }
            
            // Breakdown results
            if isBreakingDown || !breakdownResult.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    // Show the text being broken down as header
                    if let currentBreakdown = UserDefaults.standard.string(forKey: "currentBreakdownQuery"), !currentBreakdown.isEmpty {
                        Text(currentBreakdown)
                            .font(.headline)
                            .foregroundStyle(T.C.ink)
                    }
                    
                    if isBreakingDown && breakdownResult.isEmpty {
                        Text("Breaking down...")
                            .font(.body)
                            .foregroundStyle(T.C.ink2)
                    } else {
                        // Display breakdown results
                        let lines = breakdownResult.components(separatedBy: "\n")
                        ForEach(lines.indices, id: \.self) { index in
                            let line = lines[index]
                            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                            if !trimmedLine.isEmpty {
                                Text(line)
                                    .font(.body)
                                    .foregroundStyle(T.C.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(T.C.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(T.C.divider, lineWidth: 1)
                )
            }
        }
    }
}