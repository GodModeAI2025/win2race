import AppKit
import SwiftUI

struct AdvancedModeView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    "Advanced Mode",
                    subtitle: "Markdown-Aufgaben aus einem Ordner importieren. Nach jeder Aufgabe bleibt der Nutzer bewusst im Loop."
                )

                HStack {
                    Button {
                        chooseFolder()
                    } label: {
                        Label("Ordner wählen", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)

                    Text(store.advancedFolderPath.isEmpty ? "Kein Ordner gewählt" : store.advancedFolderPath)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(24)

            Divider()

            if store.parsedAdvancedTasks.isEmpty {
                EmptyStateView(
                    systemImage: "tray",
                    title: "Keine Markdown-Aufgaben geladen",
                    message: "Wähle einen Ordner mit Dateien im dokumentierten `task.md`-Format."
                )
            } else {
                List {
                    ForEach(store.parsedAdvancedTasks, id: \.sourceURL) { parsed in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
                                .padding(.top, 3)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(parsed.draft.title)
                                    .font(.headline)
                                Text(parsed.draft.repository)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Text(parsed.draft.description)
                                    .lineLimit(2)
                            }

                            Spacer()

                            Button {
                                store.startAdvancedTask(parsed)
                            } label: {
                                Label("Starten", systemImage: "play.fill")
                            }
                            .disabled(store.runnableInstallations.isEmpty)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Auswählen"

        if panel.runModal() == .OK, let url = panel.url {
            store.importAdvancedFolder(url)
        }
    }
}
