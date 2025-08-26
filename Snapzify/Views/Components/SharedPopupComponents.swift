import SwiftUI

// MARK: - Shared Popup Button Style
struct PopupButtonStyle: ButtonStyle {
    var isActive: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isActive ? .white : T.C.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Constants.UI.smallCornerRadius)
                    .fill(isActive ? T.C.accent : T.C.ink.opacity(0.1))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

// MARK: - Sentence Popup (Shared between Document and Video)
struct SentencePopup: View {
    let sentence: Sentence
    @ObservedObject var vm: SentenceViewModel
    @Binding var isShowing: Bool
    let position: CGPoint
    @Binding var showingChatGPTInput: Bool
    @Binding var chatGPTContext: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: T.S.sm) {
            // Chinese text
            Text(sentence.text)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(T.C.ink)
            
            // Pinyin
            if !vm.sentence.pinyin.isEmpty {
                Text(vm.sentence.pinyin.joined(separator: " "))
                    .font(.system(size: 14))
                    .foregroundStyle(T.C.ink2)
            } else if !sentence.pinyin.isEmpty {
                Text(sentence.pinyin.joined(separator: " "))
                    .font(.system(size: 14))
                    .foregroundStyle(T.C.ink2)
            }
            
            // English translation or loading indicator
            if vm.isTranslating {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Translating...")
                        .font(.system(size: 16))
                        .foregroundStyle(T.C.ink2)
                }
            } else if let english = sentence.english, english != "Generating..." {
                Text(english)
                    .font(.system(size: 16))
                    .foregroundStyle(T.C.ink2)
            }
            
            // Action buttons
            PopupActionButtons(
                vm: vm,
                showingChatGPTInput: $showingChatGPTInput
            )
        }
        .padding(T.S.lg)
        .background(
            RoundedRectangle(cornerRadius: Constants.UI.cornerRadius)
                .fill(T.C.card)
                .shadow(color: .black.opacity(0.2), radius: Constants.UI.shadowRadius, x: 0, y: 10)
        )
        .frame(maxWidth: Constants.UI.popupMaxWidth)
    }
}

// MARK: - Popup Action Buttons
struct PopupActionButtons: View {
    @ObservedObject var vm: SentenceViewModel
    @Binding var showingChatGPTInput: Bool
    
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Pleco button
            Button {
                vm.openInPleco()
            } label: {
                Label("Pleco", systemImage: "book")
                    .font(.caption)
            }
            .buttonStyle(PopupButtonStyle())
            
            // Spacing after Pleco
            Spacer().frame(width: T.S.sm)
            
            // Audio button
            AudioButton(vm: vm)
            
            // Spacing after Audio
            Spacer().frame(width: T.S.sm)
            
            // ChatGPT button
            Button {
                showingChatGPTInput = true
            } label: {
                Label("ChatGPT", systemImage: "message.circle")
                    .font(.caption)
            }
            .buttonStyle(PopupButtonStyle())
            
            // Push remaining space
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Audio Button Component
struct AudioButton: View {
    @ObservedObject var vm: SentenceViewModel
    
    var body: some View {
        if vm.isGeneratingAudio || vm.isPreparingAudio {
            HStack(spacing: 4) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: T.C.accent))
                    .scaleEffect(0.6)
                Text("Load")
                    .font(.caption)
                    .foregroundStyle(T.C.ink2)
                    .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Constants.UI.smallCornerRadius)
                    .fill(T.C.ink.opacity(0.1))
            )
            .fixedSize()
        } else {
            Button {
                vm.playOrPauseAudio()
            } label: {
                Label(
                    vm.isPlaying ? "Pause" : "Play",
                    systemImage: vm.isPlaying ? "pause.fill" : "play.fill"
                )
                .font(.caption)
            }
            .buttonStyle(PopupButtonStyle(isActive: vm.isPlaying))
        }
    }
}

// MARK: - ChatGPT Input Popup (Shared)
struct ChatGPTContextInputPopup: View {
    let chineseText: String
    @Binding var context: String
    @Binding var isPresented: Bool
    @State private var streamedResponse = ""
    @State private var isStreaming = false
    @State private var userPrompt = ""
    @State private var streamTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool
    
    private let chatGPTService = ServiceContainer.shared.chatGPTService
    
    var body: some View {
        VStack(alignment: .leading, spacing: T.S.md) {
            // Header
            ChatGPTHeader(isPresented: $isPresented, streamTask: streamTask)
            
            // Response area
            ChatGPTResponseArea(
                streamedResponse: streamedResponse,
                isStreaming: isStreaming,
                chineseText: chineseText
            )
            
            // Input area
            ChatGPTInputArea(
                userPrompt: $userPrompt,
                isStreaming: isStreaming,
                isFocused: _isFocused,
                onSend: sendCustomPrompt,
                onStop: { streamTask?.cancel() }
            )
            
            // External ChatGPT button
            ExternalChatGPTButton(chineseText: chineseText, userPrompt: userPrompt)
        }
        .padding(T.S.lg)
        .background(
            RoundedRectangle(cornerRadius: Constants.UI.cornerRadius)
                .fill(T.C.card)
                .shadow(color: .black.opacity(0.2), radius: Constants.UI.shadowRadius, x: 0, y: 10)
        )
        .frame(maxWidth: Constants.UI.chatGPTPopupMaxWidth, maxHeight: Constants.UI.popupMaxHeight)
        .onAppear {
            startInitialBreakdown()
        }
        .onDisappear {
            streamTask?.cancel()
        }
    }
    
    private func startInitialBreakdown() {
        guard chatGPTService.isConfigured() else {
            streamedResponse = Constants.ErrorMessage.apiKeyMissing
            return
        }
        
        isStreaming = true
        streamedResponse = ""
        
        streamTask = Task {
            do {
                for try await chunk in chatGPTService.streamBreakdown(chineseText: chineseText) {
                    if !Task.isCancelled {
                        await MainActor.run {
                            streamedResponse += chunk
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    streamedResponse = "Error: \(error.localizedDescription)"
                }
            }
            
            await MainActor.run {
                isStreaming = false
            }
        }
    }
    
    private func sendCustomPrompt() {
        guard !userPrompt.isEmpty, chatGPTService.isConfigured() else { return }
        
        let prompt = userPrompt
        userPrompt = ""
        
        isStreaming = true
        streamedResponse += "\n\n**You:** \(prompt)\n\n**ChatGPT:** "
        
        streamTask?.cancel()
        streamTask = Task {
            do {
                for try await chunk in chatGPTService.streamCustomPrompt(chineseText: chineseText, userPrompt: prompt) {
                    if !Task.isCancelled {
                        await MainActor.run {
                            streamedResponse += chunk
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    streamedResponse += "\n\nError: \(error.localizedDescription)"
                }
            }
            
            await MainActor.run {
                isStreaming = false
            }
        }
    }
}

// MARK: - ChatGPT Sub-Components
private struct ChatGPTHeader: View {
    @Binding var isPresented: Bool
    let streamTask: Task<Void, Never>?
    
    var body: some View {
        HStack {
            Text("ChatGPT")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(T.C.ink)
            
            Spacer()
            
            Button {
                streamTask?.cancel()
                isPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(T.C.ink2)
                    .font(.title2)
            }
        }
    }
}

private struct ChatGPTResponseArea: View {
    let streamedResponse: String
    let isStreaming: Bool
    let chineseText: String
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: T.S.sm) {
                    if streamedResponse.isEmpty && isStreaming {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Prompting...")
                                .font(.system(size: 14))
                                .foregroundStyle(T.C.ink2)
                        }
                    } else if !streamedResponse.isEmpty {
                        Text(streamedResponse)
                            .font(.system(size: 14))
                            .foregroundStyle(T.C.ink)
                            .textSelection(.enabled)
                            .id("response")
                    } else {
                        Text("Ask me anything about: \"\(String(chineseText.prefix(50)))\(chineseText.count > 50 ? "..." : "")\"")
                            .font(.system(size: 14))
                            .foregroundStyle(T.C.ink2)
                            .italic()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: streamedResponse) { newValue in
                // Auto-scroll for follow-up questions only
                if newValue.contains("\n\n**You:**") {
                    let components = newValue.components(separatedBy: "\n\n**You:**")
                    if components.count > 1 {
                        withAnimation {
                            proxy.scrollTo("response", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(minHeight: 200, maxHeight: 400)
        .padding(T.S.sm)
        .background(
            RoundedRectangle(cornerRadius: Constants.UI.smallCornerRadius)
                .fill(T.C.ink.opacity(0.05))
        )
    }
}

private struct ChatGPTInputArea: View {
    @Binding var userPrompt: String
    let isStreaming: Bool
    @FocusState var isFocused: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    
    var body: some View {
        HStack(spacing: T.S.sm) {
            TextField("Ask a follow-up question...", text: $userPrompt, axis: .vertical)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .lineLimit(1...3)
                .focused($isFocused)
                .disabled(isStreaming)
                .onSubmit {
                    onSend()
                }
            
            Button {
                if isStreaming {
                    onStop()
                } else if !userPrompt.isEmpty {
                    onSend()
                }
            } label: {
                if isStreaming {
                    Image(systemName: "stop.circle.fill")
                        .foregroundStyle(.red)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(userPrompt.isEmpty ? T.C.ink2 : T.C.accent)
                }
            }
            .font(.title2)
            .disabled(!isStreaming && userPrompt.isEmpty)
        }
    }
}

private struct ExternalChatGPTButton: View {
    let chineseText: String
    let userPrompt: String
    
    var body: some View {
        Button {
            openInChatGPTApp()
        } label: {
            Label("Open in ChatGPT", systemImage: "arrow.up.forward.app")
                .font(.system(size: 14, weight: .medium))
        }
        .buttonStyle(PopupButtonStyle())
    }
    
    private func openInChatGPTApp() {
        let prompt = chineseText + (userPrompt.isEmpty ? "" : " " + userPrompt)
        let encodedPrompt = prompt.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        // Try ChatGPT app first
        if let url = URL(string: "chatgpt://message?prompt=\(encodedPrompt)"),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } 
        // Fall back to web version
        else if let url = URL(string: "https://chat.openai.com/?q=\(encodedPrompt)") {
            UIApplication.shared.open(url)
        }
    }
}