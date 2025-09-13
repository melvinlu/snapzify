import SwiftUI
import UIKit

// MARK: - Feedback Response Model
struct FeedbackResponse {
    let chineseText: String
    let englishTranslation: String
    let feedback: String
    let pinyin: String?
    
    init(from rawResponse: String) {
        // Parse the response to extract Chinese, English, and feedback
        // Expected format: "Chinese: [text]\nEnglish: [text]\nFeedback: [text]"
        let lines = rawResponse.components(separatedBy: "\n")
        var chinese = ""
        var english = ""
        var feedback = ""
        var pinyin: String? = nil
        
        for line in lines {
            if line.starts(with: "Chinese:") || line.starts(with: "中文:") {
                chinese = line.replacingOccurrences(of: "Chinese:", with: "")
                    .replacingOccurrences(of: "中文:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if line.starts(with: "English:") || line.starts(with: "Translation:") {
                english = line.replacingOccurrences(of: "English:", with: "")
                    .replacingOccurrences(of: "Translation:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if line.starts(with: "Pinyin:") {
                pinyin = line.replacingOccurrences(of: "Pinyin:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if line.starts(with: "Feedback:") {
                feedback = lines.dropFirst(lines.firstIndex(of: line)!)
                    .joined(separator: "\n")
                    .replacingOccurrences(of: "Feedback:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                break
            }
        }
        
        // If parsing fails, use the entire response as feedback
        if chinese.isEmpty && english.isEmpty {
            self.chineseText = ""
            self.englishTranslation = ""
            self.feedback = rawResponse
            self.pinyin = nil
        } else {
            self.chineseText = chinese
            self.englishTranslation = english
            self.feedback = feedback.isEmpty ? rawResponse : feedback
            self.pinyin = pinyin
        }
    }
}

// MARK: - Tappable Chinese Feedback View
struct TappableChineseFeedbackView: View {
    let feedbackText: String
    
    private var parsedResponse: FeedbackResponse {
        FeedbackResponse(from: feedbackText)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Chinese text with tappable characters
            if !parsedResponse.chineseText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("You said:")
                        .font(.caption)
                        .foregroundStyle(T.C.ink2)
                    
                    TappableChineseTextView(text: parsedResponse.chineseText, fontSize: 18)
                    
                    // Pinyin if available
                    if let pinyin = parsedResponse.pinyin, !pinyin.isEmpty {
                        Text(pinyin)
                            .font(.caption)
                            .foregroundStyle(T.C.ink2)
                    }
                }
                .padding(.vertical, 4)
            }
            
            // English translation
            if !parsedResponse.englishTranslation.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Translation:")
                        .font(.caption)
                        .foregroundStyle(T.C.ink2)
                    
                    // Support markdown in translation
                    if let attributedString = try? AttributedString(markdown: parsedResponse.englishTranslation) {
                        Text(attributedString)
                            .font(.body)
                            .foregroundStyle(T.C.ink)
                    } else {
                        Text(parsedResponse.englishTranslation)
                            .font(.body)
                            .foregroundStyle(T.C.ink)
                    }
                }
            }
            
            // Feedback section
            if !parsedResponse.feedback.isEmpty && 
               parsedResponse.feedback != feedbackText { // Only show if we successfully parsed
                VStack(alignment: .leading, spacing: 4) {
                    Text("Feedback:")
                        .font(.caption)
                        .foregroundStyle(T.C.ink2)
                    
                    // Make feedback text tappable too if it contains Chinese
                    TappableChineseTextView(text: parsedResponse.feedback, fontSize: 18)
                }
            } else if parsedResponse.chineseText.isEmpty {
                // Show raw response if parsing failed
                Text(feedbackText)
                    .font(.body)
                    .foregroundStyle(T.C.ink)
            }
        }
    }
}

// MARK: - Tappable Chinese Text View
struct TappableChineseTextView: View {
    let text: String
    var fontSize: CGFloat = 18  // Default font size, can be customized
    
    @State private var showingPopup = false
    
    var body: some View {
        Button {
            showingPopup = true
        } label: {
            // Try to render with markdown support
            if let attributedString = try? AttributedString(markdown: text) {
                Text(attributedString)
                    .font(.system(size: fontSize))
                    .foregroundStyle(T.C.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(text)
                    .font(.system(size: fontSize))
                    .foregroundStyle(T.C.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showingPopup) {
            ZStack {
                // Semi-transparent background that blocks interaction
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showingPopup = false
                    }
                
                // Popup centered on screen
                StandaloneChinesePopup(
                    chineseText: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    isShowing: $showingPopup,
                    position: CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 3)
                )
                .transition(.opacity)
            }
            .presentationBackground(.clear)
            .transaction { transaction in
                transaction.disablesAnimations = true
            }
        }
    }
}


