import SwiftUI

struct LearningView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(
                "Learning",
                subtitle: "Langzeitdaten aus manuellem Nutzerfeedback. V1 sammelt Daten; automatisches Routing kommt später."
            )
            .padding(24)

            Divider()

            if store.learningRows.isEmpty {
                EmptyStateView(
                    systemImage: "chart.bar",
                    title: "Noch keine Feedbackdaten",
                    message: "Bewerte abgeschlossene Agent-Runs, damit Win-to-Race über Zeit reale Erfolgsdaten aufbauen kann."
                )
            } else {
                Table(store.learningRows) {
                    TableColumn("Agent") { row in
                        Label(row.agent.displayName, systemImage: row.agent.systemImage)
                    }
                    TableColumn("Runs") { row in
                        Text("\(row.total)")
                    }
                    TableColumn("Bestätigt") { row in
                        Text("\(row.confirmed)")
                    }
                    TableColumn("Nacharbeit") { row in
                        Text("\(row.needsWork)")
                    }
                    TableColumn("Untauglich") { row in
                        Text("\(row.unusable)")
                    }
                    TableColumn("Erfolgsquote") { row in
                        Text(row.successRate, format: .percent.precision(.fractionLength(0)))
                    }
                }
            }
        }
    }
}
