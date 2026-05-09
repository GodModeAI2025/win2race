import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedDiagnosticID: UUID?

    private var selectedDiagnostic: DiagnosticRecord? {
        guard let selectedDiagnosticID else {
            return store.diagnostics.first
        }
        return store.diagnostics.first(where: { $0.id == selectedDiagnosticID }) ?? store.diagnostics.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(
                    "Diagnostics",
                    subtitle: "Persistente, kopierbare Fehler- und Warnmeldungen aus Setup, Import, Storage und Orchestrator."
                )

                Spacer()

                Button {
                    store.copyAllDiagnostics()
                } label: {
                    Label("Alle kopieren", systemImage: "doc.on.doc")
                }
                .disabled(store.diagnostics.isEmpty)

                Button {
                    store.revealDiagnosticsFile()
                } label: {
                    Label("Datei", systemImage: "folder")
                }
            }
            .padding(24)

            Divider()

            if store.diagnostics.isEmpty {
                EmptyStateView(
                    systemImage: "checkmark.seal",
                    title: "Keine Diagnostics",
                    message: "Fehler und Warnungen werden hier als kopierbare Einträge gesammelt."
                )
            } else {
                HSplitView {
                    diagnosticList
                        .frame(minWidth: 320, idealWidth: 380)

                    Divider()

                    diagnosticDetail
                        .frame(minWidth: 520)
                }
            }
        }
    }

    private var diagnosticList: some View {
        List(selection: $selectedDiagnosticID) {
            ForEach(store.diagnostics) { diagnostic in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: icon(for: diagnostic.severity))
                            .foregroundStyle(color(for: diagnostic.severity))
                            .frame(width: 16)
                        Text(diagnostic.title)
                            .font(.headline)
                            .lineLimit(1)
                    }

                    Text(diagnostic.context)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(W2RDateFormatter.displayDateTime.string(from: diagnostic.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 5)
                .tag(diagnostic.id)
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var diagnosticDetail: some View {
        if let diagnostic = selectedDiagnostic {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(diagnostic.severity.label, systemImage: icon(for: diagnostic.severity))
                            .foregroundStyle(color(for: diagnostic.severity))
                            .font(.caption.weight(.semibold))

                        Text(diagnostic.title)
                            .font(.title3.weight(.semibold))

                        Text(diagnostic.message)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Spacer()

                    Button {
                        store.copyDiagnostic(diagnostic)
                    } label: {
                        Label("Kopieren", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Zeit").foregroundStyle(.secondary)
                        Text(W2RDateFormatter.displayDateTime.string(from: diagnostic.createdAt)).textSelection(.enabled)
                    }
                    GridRow {
                        Text("Kontext").foregroundStyle(.secondary)
                        Text(diagnostic.context).textSelection(.enabled)
                    }
                    GridRow {
                        Text("Datei").foregroundStyle(.secondary)
                        Text(diagnostic.filePath ?? "n/a")
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                    GridRow {
                        Text("Task").foregroundStyle(.secondary)
                        Text(diagnostic.taskID?.uuidString ?? "n/a").textSelection(.enabled)
                    }
                    GridRow {
                        Text("Run").foregroundStyle(.secondary)
                        Text(diagnostic.runID?.uuidString ?? "n/a").textSelection(.enabled)
                    }
                }
                .font(.callout)

                Text("Kopierbare Meldung")
                    .font(.headline)

                ScrollView {
                    Text(diagnostic.copyText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(20)
        } else {
            EmptyStateView(
                systemImage: "exclamationmark.bubble",
                title: "Keine Diagnose ausgewählt",
                message: "Wähle links einen Eintrag aus."
            )
        }
    }

    private func icon(for severity: DiagnosticSeverity) -> String {
        switch severity {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        }
    }

    private func color(for severity: DiagnosticSeverity) -> Color {
        switch severity {
        case .info: .blue
        case .warning: .orange
        case .error: .red
        }
    }
}
