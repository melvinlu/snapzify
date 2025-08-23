import SwiftUI

struct SettingsView: View {
    @StateObject var vm: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            RootBackground {
                ScrollView {
                    VStack(spacing: T.S.lg) {
                        scriptSection
                        apiKeySection
                        translationSection
                        audioSection
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
                    .foregroundStyle(T.C.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    @ViewBuilder
    private var scriptSection: some View {
        VStack(alignment: .leading, spacing: T.S.sm) {
            Text("Script")
                .font(.headline)
                .foregroundStyle(T.C.ink)
            
            Picker("Script", selection: $vm.currentScript) {
                Text("Simplified").tag(ChineseScript.simplified)
                Text("Traditional").tag(ChineseScript.traditional)
            }
            .pickerStyle(SegmentedPickerStyle())
            .background(T.C.card)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding()
        .card()
    }
    
    @ViewBuilder
    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: T.S.md) {
            HStack {
                Text("OpenAI API Key")
                    .font(.headline)
                    .foregroundStyle(T.C.ink)
                
                Spacer()
                
                if vm.isAPIKeyValid {
                    Label("Configured", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(T.C.accent)
                }
            }
            
            VStack(alignment: .leading, spacing: T.S.sm) {
                SecureField("sk-...", text: $vm.apiKey)
                    .textFieldStyle(CustomTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                
                HStack {
                    Button {
                        vm.saveAPIKey()
                    } label: {
                        if vm.isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                .scaleEffect(0.8)
                        } else {
                            Text("Save Key")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(vm.apiKey.isEmpty || vm.isSaving)
                    
                    if vm.isAPIKeyValid {
                        Button("Clear") {
                            vm.clearAPIKey()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    
                    Spacer()
                    
                    if vm.showAPIKeySaved {
                        Label("Saved", systemImage: "checkmark")
                            .font(.caption)
                            .foregroundStyle(T.C.accent)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            
            Text("Your API key is stored securely in the Keychain")
                .font(.caption)
                .foregroundStyle(T.C.ink2)
        }
        .padding()
        .card()
    }
    
    @ViewBuilder
    private var translationSection: some View {
        VStack(alignment: .leading, spacing: T.S.md) {
            HStack {
                Text("Translation")
                    .font(.headline)
                    .foregroundStyle(T.C.ink)
                
                Spacer()
                
                Text(vm.translationStatus)
                    .font(.caption)
                    .foregroundStyle(vm.translationService.isConfigured() ? T.C.accent : T.C.ink2)
            }
            
            Toggle(isOn: $vm.autoTranslate) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-translate on import")
                        .foregroundStyle(T.C.ink)
                    Text("Automatically translate sentences when processing screenshots")
                        .font(.caption)
                        .foregroundStyle(T.C.ink2)
                }
            }
            .tint(T.C.accent)
        }
        .padding()
        .card()
    }
    
    @ViewBuilder
    private var audioSection: some View {
        VStack(alignment: .leading, spacing: T.S.md) {
            HStack {
                Text("Audio")
                    .font(.headline)
                    .foregroundStyle(T.C.ink)
                
                Spacer()
                
                Text(vm.audioStatus)
                    .font(.caption)
                    .foregroundStyle(vm.ttsService.isConfigured() ? T.C.accent : T.C.ink2)
            }
            
            Toggle(isOn: $vm.autoGenerateAudio) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-generate audio on expand")
                        .foregroundStyle(T.C.ink)
                    Text("Create audio when sentences are expanded")
                        .font(.caption)
                        .foregroundStyle(T.C.ink2)
                }
            }
            .tint(T.C.accent)
            
            VStack(alignment: .leading, spacing: T.S.xs) {
                Text("Playback Speed")
                    .font(.subheadline)
                    .foregroundStyle(T.C.ink)
                
                HStack {
                    Text("0.5x")
                        .font(.caption)
                        .foregroundStyle(T.C.ink2)
                    
                    Slider(value: $vm.ttsSpeed, in: 0.5...2.0, step: 0.1)
                        .tint(T.C.accent)
                    
                    Text("2.0x")
                        .font(.caption)
                        .foregroundStyle(T.C.ink2)
                }
                
                Text("\(String(format: "%.1fx", vm.ttsSpeed))")
                    .font(.caption)
                    .foregroundStyle(T.C.ink2)
                    .frame(maxWidth: .infinity)
            }
            
            VStack(alignment: .leading, spacing: T.S.sm) {
                Text("Voice Selection")
                    .font(.subheadline)
                    .foregroundStyle(T.C.ink)
                
                VStack(spacing: T.S.xs) {
                    HStack {
                        Text("Simplified Chinese")
                            .font(.caption)
                            .foregroundStyle(T.C.ink2)
                        Spacer()
                    }
                    
                    Picker("Simplified Voice", selection: $vm.voiceSimplified) {
                        ForEach(Array(vm.availableVoices.keys.sorted()), id: \.self) { key in
                            Text(vm.availableVoices[key] ?? key).tag(key)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(T.C.card)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                VStack(spacing: T.S.xs) {
                    HStack {
                        Text("Traditional Chinese")
                            .font(.caption)
                            .foregroundStyle(T.C.ink2)
                        Spacer()
                    }
                    
                    Picker("Traditional Voice", selection: $vm.voiceTraditional) {
                        ForEach(Array(vm.availableVoices.keys.sorted()), id: \.self) { key in
                            Text(vm.availableVoices[key] ?? key).tag(key)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(T.C.card)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding()
        .card()
    }
    
    @ViewBuilder
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: T.S.sm) {
            Text("About")
                .font(.headline)
                .foregroundStyle(T.C.ink)
            
            VStack(alignment: .leading, spacing: T.S.xs) {
                Label("Snapzify v1.0", systemImage: "camera.viewfinder")
                    .foregroundStyle(T.C.ink)
                
                Text("Turn screenshots into readable, tappable Chinese sentences")
                    .font(.caption)
                    .foregroundStyle(T.C.ink2)
                
                Divider()
                    .background(T.C.divider)
                
                Text("Privacy")
                    .font(.subheadline)
                    .foregroundStyle(T.C.ink)
                    .padding(.top, T.S.xs)
                
                Text("• OCR, segmentation, and pinyin are processed on-device\n• Only text is sent to OpenAI for translation and audio\n• Images never leave your device")
                    .font(.caption)
                    .foregroundStyle(T.C.ink2)
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