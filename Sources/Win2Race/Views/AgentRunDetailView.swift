import SwiftUI

struct AgentRunDetailView: View {
    @EnvironmentObject private var store: AppStore
    @State private var answerText = ""

    var body: some View {
        if let run = store.selectedRun {
            HSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        runSummary(run)
                        if run.status == .waitingForUser {
                            questionBox(run)
                        }
                        feedbackBox(run)
                    }
                    .padding(18)
                    .frame(minWidth: 360, idealWidth: 430, maxWidth: 520, alignment: .topLeading)
                }

                logView(run)
                    .frame(minWidth: 520)
            }
        } else {
            EmptyStateView(
                systemImage: "terminal",
                title: "Kein Agent ausgewählt",
                message: "Wähle oben einen Agenten-Run aus."
            )
        }
    }

    private func runSummary(_ run: AgentRunRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(run.agent.displayName, subtitle: run.lastAction)
                Spacer()
                StatusPill(status: run.status)
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Branch").foregroundStyle(.secondary)
                    Text(run.branchName).textSelection(.enabled)
                }
                GridRow {
                    Text("Workspace").foregroundStyle(.secondary)
                    Text(run.workspacePath).lineLimit(2).textSelection(.enabled)
                }
                GridRow {
                    Text("Exit").foregroundStyle(.secondary)
                    Text(run.exitCode.map(String.init) ?? "n/a")
                }
                GridRow {
                    Text("Tokens").foregroundStyle(.secondary)
                    Text("\(run.estimatedTokens)")
                }
                GridRow {
                    Text("Commit").foregroundStyle(.secondary)
                    Text(run.commitHash ?? "n/a").textSelection(.enabled)
                }
            }
            .font(.callout)

            HStack {
                Button {
                    store.reveal(path: run.workspacePath)
                } label: {
                    Label("Workspace", systemImage: "folder")
                }

                Button {
                    store.reveal(path: run.adrPath)
                } label: {
                    Label("ADR", systemImage: "doc.text")
                }
                .disabled(run.status.isTerminal == false)

                if !run.status.isTerminal {
                    Button(role: .destructive) {
                        store.cancel(run: run)
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                }
            }
        }
    }

    private func questionBox(_ run: AgentRunRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Rückfrage", subtitle: run.pendingQuestion)

            TextField("Antwort an den Agenten", text: $answerText, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)

            Button {
                store.answerSelectedRun(answerText)
                answerText = ""
            } label: {
                Label("Antwort senden", systemImage: "arrow.up.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(answerText.trimmed.isEmpty)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func feedbackBox(_ run: AgentRunRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Feedback", subtitle: "Manuelle Bewertung für das Langzeitlernen")

            Picker(
                "Bewertung",
                selection: Binding(
                    get: { store.feedbackVerdicts[run.id] ?? .confirmed },
                    set: { store.feedbackVerdicts[run.id] = $0 }
                )
            ) {
                ForEach(FeedbackVerdict.allCases) { verdict in
                    Text(verdict.label).tag(verdict)
                }
            }
            .pickerStyle(.segmented)

            TextField(
                "Notizen",
                text: Binding(
                    get: { store.feedbackNotes[run.id, default: ""] },
                    set: { store.feedbackNotes[run.id] = $0 }
                ),
                axis: .vertical
            )
            .lineLimit(3...6)
            .textFieldStyle(.roundedBorder)

            Button {
                store.recordFeedback(run: run)
            } label: {
                Label("Feedback speichern", systemImage: "checkmark.circle")
            }
            .disabled(!run.status.isTerminal)
        }
    }

    private func logView(_ run: AgentRunRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionHeader("Session Log", subtitle: run.logPath)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                Text((store.logsByRunID[run.id] ?? []).joined())
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}
