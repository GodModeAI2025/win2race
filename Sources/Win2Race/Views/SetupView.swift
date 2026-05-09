import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedEnvAgent: AgentKind = .claude

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    SectionHeader("Setup", subtitle: "Win-to-Race fragt nur fehlende CLI- und Provider-Informationen ab.")
                    Spacer()
                    Button {
                        store.refreshSetupState()
                    } label: {
                        Label("Neu prüfen", systemImage: "arrow.clockwise")
                    }
                }

                readinessSection
                cliSection
                keySection
                envSection
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
    }

    private var readinessSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: setupIsGreen ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(setupIsGreen ? .green : .orange)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(setupIsGreen ? "Setup ist grün" : "Damit Setup grün wird")
                        .font(.headline)
                    Text(readinessSubtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if !setupIsGreen {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(setupActionItems) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.systemImage)
                                .foregroundStyle(item.color)
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.callout.weight(.semibold))
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background((setupIsGreen ? Color.green : Color.orange).opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var cliSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Coding-CLIs")

            ForEach(store.installations) { installation in
                HStack(spacing: 12) {
                    Image(systemName: installation.agent.systemImage)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(installation.agent.displayName)
                                .font(.headline)
                            Text(installation.strategy.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(installation.commandPath ?? installation.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(cliActionText(for: installation))
                            .font(.caption)
                            .foregroundStyle(installation.isInstalled ? .green : .orange)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    ReadinessBadge(
                        isGreen: installation.isInstalled,
                        greenText: "grün",
                        actionText: "Aktion"
                    )
                }
                .padding(.vertical, 7)
            }
        }
    }

    private var keySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("API Keys", subtitle: "Keys werden im macOS Keychain gespeichert und beim CLI-Start als ENV gesetzt.")

            ForEach(store.providerSecretStates) { state in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.key)
                            .font(.headline)
                        Text(state.provider)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 190, alignment: .leading)

                    SecureField(
                        state.isPresent ? "gespeichert" : "fehlt",
                        text: Binding(
                            get: { store.secretDrafts[state.key, default: ""] },
                            set: { store.secretDrafts[state.key] = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    Button {
                        store.saveSecret(key: state.key)
                    } label: {
                        Label("Speichern", systemImage: "key")
                    }
                    .disabled(store.secretDrafts[state.key, default: ""].trimmed.isEmpty)
                    .help(state.isPresent ? "Neuen Wert einfügen, um den gespeicherten Key zu ersetzen" : "Key einfügen, um diesen Eintrag grün zu machen")

                    ReadinessBadge(
                        isGreen: state.isPresent,
                        greenText: "grün",
                        actionText: "Key fehlt"
                    )
                }

                Text(keyActionText(for: state))
                    .font(.caption)
                    .foregroundStyle(state.isPresent ? .green : .orange)
                    .padding(.leading, 200)
                    .lineLimit(2)
            }
        }
    }

    private var envSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("ENV-Editor", subtitle: "Zusätzliche Shell-ENV pro CLI. Syntax: `export NAME=value` oder `NAME=value`.")

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(AgentKind.allCases) { agent in
                        Button {
                            selectedEnvAgent = agent
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: agent.systemImage)
                                    .frame(width: 18)
                                Text(agent.displayName)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: envIsGreen(agent) ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .foregroundStyle(envIsGreen(agent) ? .green : .orange)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(selectedEnvAgent == agent ? Color.accentColor.opacity(0.14) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .frame(width: 210)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(selectedEnvAgent.displayName).env")
                                .font(.headline)
                            Text(store.fileStore.envFileURL(for: selectedEnvAgent).path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }

                        Spacer()

                        ReadinessBadge(
                            isGreen: envIsGreen(selectedEnvAgent),
                            greenText: "grün",
                            actionText: "Syntax prüfen"
                        )
                    }

                    TextEditor(
                        text: Binding(
                            get: { store.envDrafts[selectedEnvAgent, default: store.fileStore.envTemplate(for: selectedEnvAgent)] },
                            set: { store.updateEnvironmentDraft(for: selectedEnvAgent, content: $0) }
                        )
                    )
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 190)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(envIsGreen(selectedEnvAgent) ? Color.green.opacity(0.45) : Color.orange.opacity(0.70), lineWidth: 1)
                    }

                    envValidationView(for: selectedEnvAgent)

                    HStack {
                        Button {
                            store.saveEnvironmentDraft(for: selectedEnvAgent)
                        } label: {
                            Label("Speichern", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!envIsGreen(selectedEnvAgent))

                        Button {
                            store.reloadEnvironmentDraft(for: selectedEnvAgent)
                        } label: {
                            Label("Neu laden", systemImage: "arrow.clockwise")
                        }

                        Button {
                            store.resetEnvironmentDraft(for: selectedEnvAgent)
                        } label: {
                            Label("Template", systemImage: "doc.badge.arrow.up")
                        }

                        Spacer()

                        Button {
                            store.reveal(path: store.fileStore.envFileURL(for: selectedEnvAgent).path)
                        } label: {
                            Label("Im Finder", systemImage: "folder")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func envValidationView(for agent: AgentKind) -> some View {
        let messages = store.envValidationMessages[agent, default: []]

        if messages.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("ENV ist grün: Syntax passt, Datei kann gespeichert und beim Agent-Start geladen werden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(messages, id: \.self) { message in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(.orange)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var setupIsGreen: Bool {
        store.installations.contains(where: \.isInstalled) &&
        store.providerSecretStates.allSatisfy(\.isPresent) &&
        AgentKind.allCases.allSatisfy { envIsGreen($0) }
    }

    private var readinessSubtitle: String {
        if setupIsGreen {
            return "Mindestens eine Coding-CLI ist verfügbar und alle bekannten Provider-Keys sind gespeichert."
        }

        let missingCLI = store.installations.filter { !$0.isInstalled }.count
        let missingKeys = store.providerSecretStates.filter { !$0.isPresent }.count
        let envIssues = AgentKind.allCases.filter { !envIsGreen($0) }.count
        var parts: [String] = []
        if store.installations.contains(where: \.isInstalled) == false {
            parts.append("mindestens eine Coding-CLI installieren")
        }
        if missingCLI > 0 {
            parts.append("\(missingCLI) optionale CLI-Einträge prüfen")
        }
        if missingKeys > 0 {
            parts.append("\(missingKeys) API-Key\(missingKeys == 1 ? "" : "s") speichern")
        }
        if envIssues > 0 {
            parts.append("\(envIssues) ENV-Datei\(envIssues == 1 ? "" : "en") korrigieren")
        }
        return parts.joined(separator: ", ") + "."
    }

    private var setupActionItems: [SetupActionItem] {
        var items: [SetupActionItem] = []

        if store.installations.contains(where: \.isInstalled) == false {
            items.append(
                SetupActionItem(
                    systemImage: "terminal",
                    color: .orange,
                    title: "Mindestens eine Coding-CLI installieren",
                    detail: "Installiere `claude`, `codex`, `gemini`, `opencode` oder `aider`, stelle sicher, dass der Befehl im PATH liegt, und klicke danach auf „Neu prüfen“."
                )
            )
        }

        let missingInstallations = store.installations.filter { !$0.isInstalled }
        if let firstMissing = missingInstallations.first {
            items.append(
                SetupActionItem(
                    systemImage: firstMissing.agent.systemImage,
                    color: .orange,
                    title: "\(firstMissing.agent.displayName) grün machen",
                    detail: cliActionText(for: firstMissing)
                )
            )
        }

        let missingKeys = store.providerSecretStates.filter { !$0.isPresent }
        if let firstMissingKey = missingKeys.first {
            items.append(
                SetupActionItem(
                    systemImage: "key",
                    color: .orange,
                    title: "\(firstMissingKey.key) speichern",
                    detail: keyActionText(for: firstMissingKey)
                )
            )
        }

        if let firstBrokenEnv = AgentKind.allCases.first(where: { !envIsGreen($0) }),
           let firstMessage = store.envValidationMessages[firstBrokenEnv]?.first {
            items.append(
                SetupActionItem(
                    systemImage: "slider.horizontal.3",
                    color: .orange,
                    title: "\(firstBrokenEnv.displayName)-ENV korrigieren",
                    detail: firstMessage
                )
            )
        }

        if missingInstallations.count > 1 || missingKeys.count > 1 || AgentKind.allCases.filter({ !envIsGreen($0) }).count > 1 {
            items.append(
                SetupActionItem(
                    systemImage: "list.bullet.clipboard",
                    color: .secondary,
                    title: "Weitere offene Punkte",
                    detail: "Alle grauen oder orangenen Zeilen darunter zeigen direkt unter dem Namen die konkrete Aktion, die den Eintrag grün macht."
                )
            )
        }

        return items
    }

    private func cliActionText(for installation: CLIInstallation) -> String {
        if installation.isInstalled {
            return "Bereit: W2R kann `\(installation.commandName)` starten."
        }

        let commands = installation.agent.preferredCommands.map { "`\($0)`" }.joined(separator: " oder ")
        switch installation.agent {
        case .claude:
            return "Claude Code installieren, sodass \(commands) im PATH liegt. Danach „Neu prüfen“ klicken."
        case .gemini:
            return "Gemini CLI installieren, sodass \(commands) im PATH liegt. Danach „Neu prüfen“ klicken."
        case .openAI:
            return "OpenAI/Codex CLI installieren, sodass \(commands) im PATH liegt. Danach „Neu prüfen“ klicken."
        case .deepSeek, .qwen, .kimi, .groq, .glm:
            return "Wrapper `aider` installieren und den passenden Provider-Key speichern. Danach „Neu prüfen“ klicken."
        case .aider:
            return "aider installieren, sodass \(commands) im PATH liegt. Danach „Neu prüfen“ klicken."
        case .openCode:
            return "OpenCode installieren, sodass \(commands) im PATH liegt. Danach „Neu prüfen“ klicken."
        }
    }

    private func keyActionText(for state: ProviderSecretState) -> String {
        if state.isPresent {
            return "Gespeichert: \(state.key) wird beim CLI-Start als ENV gesetzt."
        }
        return "\(state.key) oben einfügen und „Speichern“ klicken. Danach wird dieser Eintrag grün."
    }

    private func envIsGreen(_ agent: AgentKind) -> Bool {
        store.envValidationMessages[agent, default: []].isEmpty
    }
}

struct SettingsView: View {
    var body: some View {
        SetupView()
    }
}

private struct SetupActionItem: Identifiable {
    let id = UUID()
    let systemImage: String
    let color: Color
    let title: String
    let detail: String
}

private struct ReadinessBadge: View {
    let isGreen: Bool
    let greenText: String
    let actionText: String

    var body: some View {
        Label(isGreen ? greenText : actionText, systemImage: isGreen ? "checkmark.circle.fill" : "arrow.right.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(isGreen ? .green : .orange)
            .labelStyle(.titleAndIcon)
            .fixedSize()
    }
}
