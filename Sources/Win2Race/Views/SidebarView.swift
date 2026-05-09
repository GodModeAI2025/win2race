import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Win-to-Race")
                    .font(.title3.weight(.semibold))
                Text("KI-Agenten lokal orchestriert")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, 10)

            ForEach(AppSection.allCases) { section in
                Button {
                    store.selectedSection = section
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.systemImage)
                            .frame(width: 18)
                        Text(section.title)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(store.selectedSection == section ? Color.accentColor.opacity(0.16) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 8)
            }

            Divider()
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 6) {
                Text("Agenten")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)

                ForEach(store.installations.prefix(6)) { installation in
                    HStack(spacing: 8) {
                        Image(systemName: installation.agent.systemImage)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(installation.agent.displayName)
                            .lineLimit(1)
                        Spacer()
                        Circle()
                            .fill(installation.isInstalled ? Color.green : Color.secondary.opacity(0.35))
                            .frame(width: 7, height: 7)
                    }
                    .font(.caption)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 3)
                }
            }

            Spacer()
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
    }
}
