import SwiftUI

struct VersionHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    
    let releases: [ReleaseInfo] = [
        ReleaseInfo(
            version: "1.0",
            date: "August 2025",
            notes: [
                ""                
            ]
        )
    ]
    
    var body: some View {
        NavigationStack {
            RootBackground {
                ScrollView {
                    VStack(spacing: T.S.lg) {
                        ForEach(releases) { release in
                            releaseCard(release)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Version History")
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
    private func releaseCard(_ release: ReleaseInfo) -> some View {
        VStack(alignment: .leading, spacing: T.S.md) {
            // Version header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Version \(release.version)")
                        .font(.headline)
                        .foregroundStyle(T.C.ink)
                    
                    Text(release.date)
                        .font(.caption)
                        .foregroundStyle(T.C.ink2)
                }
                
                Spacer()
                
                if release == releases.first {
                    Text("Current")
                        .font(.caption)
                        .foregroundStyle(T.C.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(T.C.accent.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            
            Divider()
                .background(T.C.divider.opacity(0.6))
            
            // Release notes
            VStack(alignment: .leading, spacing: T.S.sm) {
                ForEach(release.notes, id: \.self) { note in
                    HStack(alignment: .top, spacing: T.S.sm) {
                        Text("•")
                            .foregroundStyle(T.C.ink2)
                        
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(T.C.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding()
        .card()
    }
}

struct ReleaseInfo: Identifiable, Equatable {
    let id = UUID()
    let version: String
    let date: String
    let notes: [String]
    
    static func == (lhs: ReleaseInfo, rhs: ReleaseInfo) -> Bool {
        lhs.version == rhs.version
    }
}
