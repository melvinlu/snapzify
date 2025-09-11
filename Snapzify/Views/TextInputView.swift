import SwiftUI

struct TextInputView: View {
    @Binding var isPresented: Bool
    @StateObject private var viewModel: TextInputViewModel
    @FocusState private var isTextFieldFocused: Bool
    @EnvironmentObject var appState: AppState
    @State private var showTranslationPopup = false
    
    init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
        
        // Initialize view model with services
        let container = ServiceContainer.shared
        let translationService = container.resolve(EnglishToChineseTranslationService.self) as? EnglishToChineseTranslationServiceImpl
            ?? EnglishToChineseTranslationServiceImpl(configService: container.configService)
        
        self._viewModel = StateObject(wrappedValue: TextInputViewModel(
            translationService: translationService,
            documentService: container.documentService,
            appState: container.appState
        ))
    }
    
    var body: some View {
        NavigationView {
            RootBackground {
                if !viewModel.isServiceConfigured {
                    TranslationNotConfiguredView()
                } else {
                    inputView
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(T.C.ink)
                            .font(.system(size: 16, weight: .medium))
                    }
                }
                
            }
            .preferredColorScheme(.dark)
        }
    }
    
    @ViewBuilder
    private var inputView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Text editor for multi-line input
                ZStack(alignment: .topLeading) {
                    if viewModel.inputText.isEmpty {
                        Text("Type or paste English text here...")
                            .foregroundStyle(T.C.ink2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 12)
                    }
                    
                    TextEditor(text: $viewModel.inputText)
                        .focused($isTextFieldFocused)
                        .foregroundStyle(T.C.ink)
                        .font(.body)
                        .padding(8)
                        .scrollContentBackground(.hidden)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(T.C.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(T.C.divider, lineWidth: 1)
                        )
                }
                .frame(minHeight: 150, maxHeight: 250)
                .padding(.horizontal)
                .padding(.top, 20)
                
                // Translate button
                Button {
                    // Dismiss keyboard
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    
                    showTranslationPopup = true
                    Task {
                        await viewModel.streamTranslate()
                    }
                } label: {
                    HStack {
                        if viewModel.isStreaming {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Image(systemName: "translate")
                        }
                        Text(viewModel.isStreaming ? "Translating..." : "Reverse Snapzify!")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Group {
                            if viewModel.hasInput && !viewModel.isStreaming {
                                LinearGradient(
                                    colors: [T.C.brandStart, T.C.brandEnd],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            } else {
                                T.C.divider
                            }
                        }
                    )
                    .cornerRadius(12)
                }
                .disabled(!viewModel.hasInput || viewModel.isStreaming)
                .padding(.horizontal)
                
                // Error message
                if let error = viewModel.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(T.C.danger)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(T.C.danger)
                        Spacer()
                        Button("Dismiss") {
                            viewModel.dismissError()
                        }
                        .font(.caption)
                        .foregroundStyle(T.C.accent)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(T.C.danger.opacity(0.1))
                    )
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            // Auto-focus the text field when view appears
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay
                isTextFieldFocused = true
            }
        }
        .overlay(
            Group {
                if showTranslationPopup && (viewModel.isStreaming || !viewModel.streamingResult.isEmpty) {
                    StreamingTranslationPopup(
                        content: viewModel.streamingResult,
                        isStreaming: viewModel.isStreaming,
                        onDismiss: {
                            showTranslationPopup = false
                            viewModel.clear()
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .zIndex(999)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showTranslationPopup)
        )
    }
}

struct TextInputView_Previews: PreviewProvider {
    static var previews: some View {
        TextInputView(isPresented: .constant(true))
    }
}