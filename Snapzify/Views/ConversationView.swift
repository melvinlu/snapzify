import SwiftUI
import AVFoundation

struct ConversationView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ConversationViewModel()
    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case scenario, userInput
    }
    
    @ViewBuilder
    private var setupView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: T.S.lg) {
                // Scenario field
                VStack(alignment: .leading, spacing: T.S.xs) {
                    Text("Scenario")
                        .font(.headline)
                        .foregroundStyle(T.C.ink)

                    TextField("e.g., Ordering boba", text: $viewModel.scenario)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .foregroundStyle(T.C.ink)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(T.C.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(T.C.divider, lineWidth: 1)
                        )
                        .focused($focusedField, equals: .scenario)
                        .onAppear {
                            // Auto-focus when view appears
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                focusedField = .scenario
                            }
                        }

                }
                        
                        // Start button
                        Button {
                            viewModel.startConversation()
                            focusedField = nil
                        } label: {
                            Text("Start")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    LinearGradient(
                                        colors: [T.C.brandStart, T.C.brandEnd],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(8)
                        }
                        .disabled(!viewModel.canStartConversation)

                        // Resume previous chat button (if available)
                        if viewModel.hasPreviousSession {
                            Button {
                                viewModel.resumePreviousSession()
                                focusedField = nil
                            } label: {
                                Text("Resume")
                                    .font(.headline)
                                    .foregroundStyle(T.C.ink)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
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
            .padding(20)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var conversationView: some View {
                // Active conversation screen
                VStack(spacing: 0) {
                    // Messages list
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: T.S.md) {
                                ForEach(viewModel.messages) { message in
                                    MessageBubble(message: message)
                                        .environmentObject(viewModel)
                                        .id(message.id)
                                        .environment(\.openURL, OpenURLAction { url in
                                            if url.scheme == "chinese" {
                                                // Show the entire message content when any Chinese text is tapped
                                                viewModel.selectChineseText(message.content)
                                                return .handled
                                            }
                                            return .systemAction
                                        })
                                }
                                
                                if viewModel.isProcessing || viewModel.isGeneratingAudio {
                                    HStack {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text(viewModel.isGeneratingAudio ? "Generating audio..." : "Snap is thinking...")
                                            .font(.caption)
                                            .foregroundStyle(T.C.ink2)
                                    }
                                    .padding(.horizontal)
                                }
                            }
                            .padding(.vertical)
                        }
                        .scrollIndicators(.hidden)
                        .onChange(of: viewModel.messages.count) { _ in
                            withAnimation {
                                proxy.scrollTo(viewModel.messages.last?.id, anchor: .bottom)
                            }
                        }
                    }
                    
                    // Input bar
                    HStack(spacing: T.S.sm) {
                        TextField("Your response...", text: $viewModel.userInput)
                            .textFieldStyle(.plain)
                            .font(.body)
                            .foregroundStyle(T.C.ink)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(T.C.card)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(T.C.divider, lineWidth: 1)
                            )
                            .focused($focusedField, equals: .userInput)
                            .onSubmit {
                                if !viewModel.userInput.isEmpty && !viewModel.isProcessing {
                                    viewModel.sendMessage()
                                }
                            }

                        // Mic button
                        Button {
                            viewModel.toggleRecording()
                        } label: {
                            if viewModel.isRecording {
                                Image(systemName: "stop.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(Color.red)
                            } else {
                                Image(systemName: "mic.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [T.C.brandStart, T.C.brandEnd],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            }
                        }
                        .disabled(viewModel.isProcessing)

                        Button {
                            if viewModel.isRecording {
                                viewModel.cancelRecording()
                            } else {
                                viewModel.sendMessage()
                            }
                        } label: {
                            if viewModel.isRecording {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(Color.red)
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [T.C.brandStart, T.C.brandEnd],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            }
                        }
                        .disabled(!viewModel.isRecording && (viewModel.userInput.isEmpty || viewModel.isProcessing))
                    }
                    .padding()
                    .background(T.C.bg)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !viewModel.isConversationActive {
                    setupView
                } else {
                    conversationView
                }
            }
            .navigationTitle(viewModel.isConversationActive ? viewModel.scenario : "Conversation Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        if viewModel.isConversationActive {
                            viewModel.saveCurrentSession()
                        }
                        dismiss()
                    }
                    .foregroundStyle(T.C.ink)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $viewModel.showInfo) {
            ConversationInfoSheet(
                scenario: viewModel.scenario,
                messageCount: viewModel.messages.count
            )
        }
        .overlay(alignment: .center) {
            if viewModel.showChinesePopup, let chineseText = viewModel.selectedChineseText {
                ZStack {
                    // Backdrop
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            viewModel.showChinesePopup = false
                        }

                    // Use the standalone popup from home page
                    StandaloneChinesePopup(
                        chineseText: chineseText,
                        isShowing: $viewModel.showChinesePopup,
                        position: CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2)
                    )
                }
                .zIndex(1000)
            }
        }
    }
}

struct MessageBubble: View {
    let message: ConversationMessage
    @EnvironmentObject var viewModel: ConversationViewModel

    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.isUser ? "You" : "Snap")
                    .font(.caption)
                    .foregroundStyle(T.C.ink2)

                // All messages with tappable Chinese segments
                InteractiveTextView(
                    content: message.content,
                    chineseSegments: message.chineseSegments,
                    isUser: message.isUser,
                    onChineseTap: { _ in
                        // This callback is not used since we handle taps via openURL
                    }
                )
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            message.isUser
                                ? LinearGradient(
                                    colors: [T.C.brandStart, T.C.brandEnd],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                : LinearGradient(
                                    colors: [T.C.card, T.C.card],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                        )
                )
            }

            if !message.isUser {
                Spacer()
            }
        }
        .padding(.horizontal)
    }
}

struct InteractiveTextView: View {
    let content: String
    let chineseSegments: [ChineseTextSegment]
    let isUser: Bool
    let onChineseTap: (String) -> Void

    var body: some View {
        let attributedString = buildAttributedString()

        Text(attributedString)
            .font(.body)
            .foregroundStyle(isUser ? .white : T.C.ink)
    }

    private func buildAttributedString() -> AttributedString {
        var attributedString = AttributedString(content)

        for segment in chineseSegments {
            if let range = attributedString.range(of: segment.text) {
                // Create a link attribute for tap handling (without underline)
                attributedString[range].link = URL(string: "chinese://\(segment.text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
            }
        }

        return attributedString
    }
}

struct ConversationInfoSheet: View {
    let scenario: String
    let messageCount: Int
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: T.S.lg) {
                VStack(alignment: .leading, spacing: T.S.xs) {
                    Text("Scenario")
                        .font(.headline)
                        .foregroundStyle(T.C.ink)
                    Text(scenario)
                        .font(.body)
                        .foregroundStyle(T.C.ink2)
                }
                
                VStack(alignment: .leading, spacing: T.S.xs) {
                    Text("Messages Exchanged")
                        .font(.headline)
                        .foregroundStyle(T.C.ink)
                    Text("\(messageCount) messages")
                        .font(.body)
                        .foregroundStyle(T.C.ink2)
                }
                
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(T.C.bg)
            .navigationTitle("Conversation Info")
            .navigationBarTitleDisplayMode(.inline)
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
}


#Preview {
    ConversationView()
}