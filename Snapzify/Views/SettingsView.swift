import SwiftUI

struct SettingsView: View {
    @StateObject var vm: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            RootBackground {
                ScrollView {
                    VStack(spacing: T.S.lg) {
                        aboutSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(T.C.ink)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    
    
    @ViewBuilder
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: T.S.sm) {
            Text("About")
                .font(.headline)
                .foregroundStyle(T.C.ink)
            
            VStack(spacing: T.S.sm) {
                HStack {
                    Label("Snapzify v1.0", systemImage: "camera.viewfinder")
                        .foregroundStyle(T.C.ink)
                    
                    Spacer()
                }
                
                Divider()
                    .background(T.C.divider.opacity(0.6))
                
                Button {
                    if let url = URL(string: "mailto:snapzify.feedback@gmail.com?subject=Snapzify%20Feedback") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Label("Send Feedback", systemImage: "envelope")
                            .foregroundStyle(T.C.ink)
                        
                        Spacer()
                        
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(T.C.ink2)
                            .font(.caption)
                    }
                }
            }
        }
        .padding()
        .card()
    }
}

struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(T.C.card)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(T.C.outline, lineWidth: 1)
            )
            .foregroundStyle(T.C.ink)
    }
}
