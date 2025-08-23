import SwiftUI

struct SentenceRowView: View {
    @ObservedObject var vm: SentenceViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: T.S.xs) {
            mainContent
            
            if vm.isExpanded {
                expandedContent
            }
        }
        .padding(T.S.md)
        .card()
        .contentShape(Rectangle())
        .onTapGesture {
            vm.toggleExpanded()
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        HStack(alignment: .top) {
            Text(vm.sentence.text)
                .font(.system(size: 18))
                .foregroundStyle(T.C.ink)
                .lineLimit(vm.isExpanded ? nil : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Image(systemName: vm.isExpanded ? "chevron.up" : "chevron.down")
                .foregroundStyle(T.C.ink2)
                .font(.system(size: 12))
                .rotationEffect(.degrees(vm.isExpanded ? 180 : 0))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: vm.isExpanded)
        }
    }
    
    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: T.S.sm) {
            if !vm.sentence.pinyin.isEmpty {
                Text(vm.sentence.pinyin.joined(separator: " "))
                    .font(.system(size: 14))
                    .foregroundStyle(T.C.ink2)
            }
            
            if vm.isTranslating {
                HStack(spacing: T.S.xs) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: T.C.accent))
                        .scaleEffect(0.7)
                    
                    Text("Translating...")
                        .font(.caption)
                        .foregroundStyle(T.C.ink2)
                }
            } else if let english = vm.sentence.english {
                Text(english)
                    .font(.system(size: 16))
                    .foregroundStyle(T.C.ink2)
            }
            
            actionButtons
        }
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: T.S.sm) {
            if vm.sentence.english == nil {
                Button {
                    Task {
                        await vm.translateIfNeeded()
                    }
                } label: {
                    Label("Translate", systemImage: "globe")
                        .font(.caption)
                }
                .buttonStyle(ActionButtonStyle())
            }
            
            Button {
                vm.openInPleco()
            } label: {
                Label("Pleco", systemImage: "book")
                    .font(.caption)
            }
            .buttonStyle(ActionButtonStyle())
            
            if vm.isGeneratingAudio {
                HStack(spacing: 4) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: T.C.accent))
                        .scaleEffect(0.6)
                    
                    Text("Generating...")
                        .font(.caption)
                        .foregroundStyle(T.C.ink2)
                }
                .padding(.horizontal, 8)
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
                .buttonStyle(ActionButtonStyle(isActive: vm.isPlaying))
            }
            
            Button {
                vm.toggleSave()
            } label: {
                Image(systemName: vm.sentence.isSaved ? "pin.fill" : "pin")
                    .font(.caption)
            }
            .buttonStyle(ActionButtonStyle(isActive: vm.sentence.isSaved))
        }
    }
}

struct ActionButtonStyle: ButtonStyle {
    var isActive: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isActive ? T.C.accent : T.C.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? T.C.accent.opacity(0.15) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? T.C.accent.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
