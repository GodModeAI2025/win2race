import SwiftUI

struct SimpleTaskView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeader(
                    "Simple Mode",
                    subtitle: "Repository und Problem reichen aus. Win-to-Race wählt die verfügbaren Agenten automatisch."
                )

                VStack(alignment: .leading, spacing: 14) {
                    TextField("Git-Repository oder lokaler Pfad", text: $store.draft.repository)
                        .textFieldStyle(.roundedBorder)

                    TextField("Titel", text: $store.draft.title)
                        .textFieldStyle(.roundedBorder)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Problembeschreibung")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $store.draft.description)
                            .font(.body)
                            .frame(minHeight: 150)
                            .scrollContentBackground(.hidden)
                            .background(.quaternary.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Constraints")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $store.draft.constraints)
                            .font(.body)
                            .frame(minHeight: 90)
                            .scrollContentBackground(.hidden)
                            .background(.quaternary.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Beispiel-Repository")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("Optional: Repository mit Patterns, die W2R berücksichtigen soll", text: $store.draft.exampleRepository)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader("Automatische Agent-Auswahl")
                        ForEach(store.installations) { installation in
                            HStack(spacing: 10) {
                                Image(systemName: installation.agent.systemImage)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(installation.agent.displayName)
                                    Text(installation.notes)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(installation.readinessLabel)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(installation.isInstalled ? .green : .secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("Start")
                        Text("Jeder Agent erhält einen eigenen Branch, Workspace, Sandbox-Kontext und Log-Ordner.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            store.startSimpleTask()
                        } label: {
                            Label(store.startButtonTitle, systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!store.draft.isStartable || store.runnableInstallations.isEmpty)

                        Button {
                            store.selectedSection = .setup
                        } label: {
                            Label("Setup prüfen", systemImage: "gearshape")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(width: 260, alignment: .topLeading)
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
    }
}
