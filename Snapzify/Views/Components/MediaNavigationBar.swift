import SwiftUI

// MARK: - Media Navigation Bar
/// Shared navigation bar for media document views
struct MediaNavigationBar: View {
    @ObservedObject var vm: DocumentViewModel
    @Binding var showingRenameAlert: Bool
    @Binding var newDocumentName: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        HStack {
            // Back button
            NavigationButton(
                systemName: "chevron.left",
                action: { dismiss() }
            )
            
            Spacer()
            
            // Rename button
            NavigationButton(
                systemName: "pencil",
                action: {
                    newDocumentName = vm.document.customName ?? ""
                    showingRenameAlert = true
                }
            )
            
            // Pin/Save button
            NavigationButton(
                systemName: vm.document.isSaved ? "pin.fill" : "pin",
                foregroundColor: vm.document.isSaved ? T.C.accent : .white,
                action: { vm.toggleImageSave() }
            )
            
            // Delete button (if from photos)
            if vm.document.assetIdentifier != nil {
                NavigationButton(
                    systemName: "trash",
                    foregroundColor: .red,
                    action: { vm.showDeleteImageAlert = true }
                )
            }
        }
        .padding()
    }
}

// MARK: - Navigation Button Component
private struct NavigationButton: View {
    let systemName: String
    var foregroundColor: Color = .white
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .foregroundColor(foregroundColor)
                .font(.title2)
                .frame(width: Constants.UI.navigationButtonSize, 
                       height: Constants.UI.navigationButtonSize)
                .background(Circle().fill(Color.black.opacity(0.5)))
        }
    }
}

// MARK: - Media Document Alerts
struct MediaDocumentAlerts: ViewModifier {
    @ObservedObject var vm: DocumentViewModel
    @Binding var showingRenameAlert: Bool
    @Binding var newDocumentName: String
    
    func body(content: Content) -> some View {
        content
            .alert("Delete Document", isPresented: $vm.showDeleteImageAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    vm.deleteImage()
                }
            } message: {
                Text(deleteMessage)
            }
            .alert("Rename Document", isPresented: $showingRenameAlert) {
                TextField("Enter name", text: $newDocumentName)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    vm.renameDocument(newDocumentName)
                }
            } message: {
                Text("Give this document a custom name")
            }
    }
    
    private var deleteMessage: String {
        if vm.document.isVideo {
            return "This will delete the document from Snapzify AND permanently delete the original video from your device's photo library. This action cannot be undone."
        } else {
            return "This will delete the document from Snapzify AND permanently delete the original photo from your device's photo library. This action cannot be undone."
        }
    }
}

// MARK: - View Extension
extension View {
    func mediaDocumentAlerts(vm: DocumentViewModel, showingRenameAlert: Binding<Bool>, newDocumentName: Binding<String>) -> some View {
        self.modifier(MediaDocumentAlerts(
            vm: vm,
            showingRenameAlert: showingRenameAlert,
            newDocumentName: newDocumentName
        ))
    }
}