import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            detail
                .safeAreaInset(edge: .bottom) {
                    StatusBar(message: store.statusMessage)
                }
        }
        .frame(minWidth: 1180, minHeight: 720)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.refreshSetupState()
                } label: {
                    Label("Aktualisieren", systemImage: "arrow.clockwise")
                }
                .help("CLI-Setup, API-Key-Status, ENV-Dateien und Diagnostics erneut laden")

                Button {
                    store.selectedSection = .simple
                } label: {
                    Label("Neue Aufgabe", systemImage: "plus")
                }
                .help("Neue Aufgabe erstellen")
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch store.selectedSection {
        case .dashboard:
            DashboardView()
        case .simple:
            SimpleTaskView()
        case .advanced:
            AdvancedModeView()
        case .setup:
            SetupView()
        case .learning:
            LearningView()
        case .diagnostics:
            DiagnosticsView()
        }
    }
}

private struct StatusBar: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(message)
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
    }
}
