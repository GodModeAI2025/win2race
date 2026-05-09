import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 0) {
            taskList
                .frame(width: 300)
                .background(.bar)

            Divider()

            if let task = store.selectedTask {
                TaskDetailView(task: task)
            } else {
                EmptyStateView(
                    systemImage: "rectangle.3.group",
                    title: "Keine Runs",
                    message: "Starte eine Aufgabe im Simple Mode oder importiere Markdown-Aufgaben im Advanced Mode."
                )
            }
        }
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Aufgaben", subtitle: "\(store.tasks.count) gespeichert")
                .padding(.horizontal, 14)
                .padding(.top, 16)

            List(selection: $store.selectedTaskID) {
                ForEach(store.tasks) { task in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                            .lineLimit(1)
                        Text(task.repository)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 4)
                    .tag(task.id)
                }
            }
            .listStyle(.sidebar)
        }
    }
}

private struct TaskDetailView: View {
    @EnvironmentObject private var store: AppStore
    let task: W2RTask

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(20)

            Divider()

            if store.selectedRuns.isEmpty {
                EmptyStateView(
                    systemImage: "terminal",
                    title: "Runs werden vorbereitet",
                    message: "Sobald die Agenten gestartet sind, erscheinen Logs und Status hier."
                )
            } else {
                VStack(spacing: 0) {
                    runTabs
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    Divider()
                    AgentRunDetailView()
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.title2.weight(.semibold))
                    Text(task.repository)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(task.status.rawValue)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Text(task.description)
                .foregroundStyle(.primary)
                .lineLimit(3)

            if !task.constraints.isEmpty {
                Text(task.constraints.map { "• \($0)" }.joined(separator: "  "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var runTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.selectedRuns) { run in
                    Button {
                        store.selectedRunID = run.id
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: run.agent.systemImage)
                            Text(run.agent.displayName)
                            StatusPill(status: run.status)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(store.selectedRun?.id == run.id ? Color.accentColor.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
