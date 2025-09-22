import SwiftUI

struct ConversationView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack {
                // Blank screen for now - placeholder for conversation feature
                Text("Conversation Mode")
                    .font(.largeTitle)
                    .foregroundStyle(T.C.ink2)
                    .padding()
                
                Text("Coming Soon")
                    .font(.body)
                    .foregroundStyle(T.C.ink2)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(T.C.bg)
            .navigationTitle("Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(T.C.ink)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ConversationView()
}