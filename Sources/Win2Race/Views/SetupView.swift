import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedEnvAgent: AgentKind = .claude
    @State private var selectedProfileAgent: AgentKind = .claude
    @State private var focusedKey: String?

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
                workspaceSection
                runtimeSection
                cliSection
                keySection
                envSection
                profileSection
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
    }

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Arbeitsverzeichnis", subtitle: "Root fuer Tasks, Agent-Workspaces, Logs, ADRs, ENV und Diagnostics.")

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "externaldrive")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text(store.fileStore.rootURL.path)
                        .font(.callout)
                        .textSelection(.enabled)
                        .lineLimit(2)
                    Text("Cleanup entfernt nur regenerierbare Artefakte wie `node_modules`, `.next`, `.turbo`, `.build` und `DerivedData`; `.git`, Logs, ADRs und Resultate bleiben erhalten.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    store.reveal(path: store.fileStore.rootURL.path)
                } label: {
                    Label("Im Finder", systemImage: "folder")
                }

                Button {
                    store.cleanupWorkspaceArtifacts()
                } label: {
                    Label("Cleanup", systemImage: "trash")
                }
            }
        }
    }

    private var runtimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Runtimes", subtitle: "Erkannte lokale Agent-Runtimes mit Profil-Overrides und Capabilities.")

            ForEach(store.runtimeRecords) { runtime in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: runtime.agent.systemImage)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(runtime.agent.displayName)
                                .font(.headline)
                            Text(runtime.strategy.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(runtime.commandPath ?? runtime.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(runtime.capabilities.joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    ReadinessBadge(
                        isGreen: runtime.health == .ready,
                        greenText: "runtime grün",
                        actionText: runtime.health.label
                    )
                }
                .padding(.vertical, 6)
            }
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
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(setupActionItems) { item in
                        setupActionRow(item)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background((setupIsGreen ? Color.green : Color.orange).opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func setupActionRow(_ item: SetupActionItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.systemImage)
                .foregroundStyle(item.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.callout.weight(.semibold))
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    if let url = item.url {
                        Button {
                            store.openExternalURL(url, label: item.urlButtonTitle)
                        } label: {
                            Label(item.urlButtonTitle, systemImage: "safari")
                        }
                    }

                    if let command = item.command {
                        Button {
                            store.copyText(command, label: "Install-Befehl")
                        } label: {
                            Label("Befehl kopieren", systemImage: "doc.on.doc")
                        }
                    }

                    if let key = item.focusKey {
                        Button {
                            focusedKey = key
                        } label: {
                            Label("Key-Feld markieren", systemImage: "key")
                        }
                    }

                    if let agent = item.focusAgent {
                        Button {
                            selectedEnvAgent = agent
                            selectedProfileAgent = agent
                        } label: {
                            Label("Agent anzeigen", systemImage: "scope")
                        }
                    }
                }
                .font(.caption)
            }
        }
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
                .padding(.vertical, focusedKey == state.key ? 6 : 0)
                .padding(.horizontal, focusedKey == state.key ? 8 : 0)
                .background(focusedKey == state.key ? Color.orange.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))

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

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Agent-Profile", subtitle: "CLI-Pfad, Modell, Extra-Argumente, Timeout und Git-Identität pro Agent.")

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(AgentKind.allCases) { agent in
                        Button {
                            selectedProfileAgent = agent
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: agent.systemImage)
                                    .frame(width: 18)
                                Text(agent.displayName)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(selectedProfileAgent == agent ? Color.accentColor.opacity(0.14) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .frame(width: 210)

                VStack(alignment: .leading, spacing: 10) {
                    Text(selectedProfileAgent.displayName)
                        .font(.headline)

                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("CLI Override").foregroundStyle(.secondary)
                            TextField("Optionaler absoluter Pfad zur CLI", text: profileBinding(\.commandPathOverride))
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Modell").foregroundStyle(.secondary)
                            TextField("Optionales Modell-Override", text: profileBinding(\.modelOverride))
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Extra Args").foregroundStyle(.secondary)
                            TextField("--flag value --quoted \"two words\"", text: profileBinding(\.extraArguments))
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("SSH Key").foregroundStyle(.secondary)
                            TextField("Optional: ~/.ssh/agents/claude/id_ed25519", text: profileBinding(\.sshIdentityPath))
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Git Name").foregroundStyle(.secondary)
                            TextField("Optionaler Commit-Name", text: profileBinding(\.gitUserName))
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Git Email").foregroundStyle(.secondary)
                            TextField("Optionale Commit-Mail", text: profileBinding(\.gitUserEmail))
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Timeout").foregroundStyle(.secondary)
                            Stepper(
                                "\(store.profile(for: selectedProfileAgent).timeoutSeconds) Sekunden",
                                value: timeoutBinding,
                                in: 300...86_400,
                                step: 300
                            )
                        }
                    }
                    .font(.callout)

                    Text("Extra-Argumente werden shell-kompatibel geparst. Der SSH-Key setzt `GIT_SSH_COMMAND` beim Clone und danach `core.sshCommand` im Worktree.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button {
                            store.saveAgentProfiles()
                        } label: {
                            Label("Speichern", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            store.resetAgentProfile(for: selectedProfileAgent)
                        } label: {
                            Label("Zurücksetzen", systemImage: "arrow.counterclockwise")
                        }

                        Spacer()

                        Button {
                            store.revealAgentProfilesFile()
                        } label: {
                            Label("Datei", systemImage: "doc")
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
                    detail: "Installiere mindestens eine CLI. Empfehlung: Claude oder OpenAI Codex, danach Terminal neu öffnen und in W2R „Neu prüfen“ klicken.",
                    url: "https://help.openai.com/en/articles/11096431",
                    urlButtonTitle: "Codex laden",
                    command: "npm install -g @openai/codex"
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
                    detail: cliActionText(for: firstMissing),
                    url: cliInstallURL(for: firstMissing.agent),
                    urlButtonTitle: "Download öffnen",
                    command: cliInstallCommand(for: firstMissing.agent),
                    focusAgent: firstMissing.agent
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
                    detail: keyActionText(for: firstMissingKey),
                    url: providerKeyURL(for: firstMissingKey.key),
                    urlButtonTitle: "Key-Seite öffnen",
                    focusKey: firstMissingKey.key
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
                    detail: "\(firstMessage) Wähle unten im ENV-Editor \(firstBrokenEnv.displayName), korrigiere die Zeile und klicke „Speichern“.",
                    focusAgent: firstBrokenEnv
                )
            )
        }

        if missingInstallations.count > 1 || missingKeys.count > 1 || AgentKind.allCases.filter({ !envIsGreen($0) }).count > 1 {
            items.append(
                SetupActionItem(
                    systemImage: "list.bullet.clipboard",
                    color: .secondary,
                    title: "Weitere offene Punkte",
                    detail: "Die Übersicht zeigt immer den nächsten konkreten Schritt. Für weitere CLIs oder Keys: unten in Coding-CLIs und API Keys stehen dieselben Hinweise je Zeile."
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
            return "Lade Claude Code von Anthropic oder kopiere den Install-Befehl. Danach ein neues Terminal öffnen, prüfen dass \(commands) im PATH liegt, und „Neu prüfen“ klicken."
        case .gemini:
            return "Lade Gemini CLI von Google oder kopiere den npm/brew-Befehl. Danach ein neues Terminal öffnen, prüfen dass \(commands) im PATH liegt, und „Neu prüfen“ klicken."
        case .openAI:
            return "Lade OpenAI Codex CLI oder kopiere den npm-Befehl. Danach ein neues Terminal öffnen, prüfen dass \(commands) im PATH liegt, und „Neu prüfen“ klicken."
        case .deepSeek, .qwen, .kimi, .groq, .glm:
            return "Diese Provider laufen in W2R über `aider`: installiere aider, speichere den passenden Provider-Key und klicke „Neu prüfen“."
        case .aider:
            return "Installiere aider mit dem offiziellen Installer, sodass \(commands) im PATH liegt. Danach „Neu prüfen“ klicken."
        case .openCode:
            return "Installiere OpenCode mit dem offiziellen Installer, sodass \(commands) im PATH liegt. Danach „Neu prüfen“ klicken."
        }
    }

    private func keyActionText(for state: ProviderSecretState) -> String {
        if state.isPresent {
            return "Gespeichert: \(state.key) wird beim CLI-Start als ENV gesetzt."
        }
        return "\(state.key) auf der Provider-Key-Seite erzeugen, hier im Feld \(state.key) einfügen und „Speichern“ klicken. Danach wird dieser Eintrag grün."
    }

    private func cliInstallCommand(for agent: AgentKind) -> String? {
        switch agent {
        case .claude:
            return "curl -fsSL https://claude.ai/install.sh | bash"
        case .gemini:
            return "npm install -g @google/gemini-cli"
        case .openAI:
            return "npm install -g @openai/codex"
        case .deepSeek, .qwen, .kimi, .groq, .glm, .aider:
            return "curl -LsSf https://aider.chat/install.sh | sh"
        case .openCode:
            return "curl -fsSL https://opencode.ai/install | bash"
        }
    }

    private func cliInstallURL(for agent: AgentKind) -> String? {
        switch agent {
        case .claude:
            return "https://support.claude.com/en/articles/14552646-troubleshoot-claude-code-installation-and-authentication"
        case .gemini:
            return "https://github.com/google-gemini/gemini-cli"
        case .openAI:
            return "https://help.openai.com/en/articles/11096431"
        case .deepSeek, .qwen, .kimi, .groq, .glm, .aider:
            return "https://aider.chat/docs/install.html"
        case .openCode:
            return "https://opencode.ai/docs/"
        }
    }

    private func providerKeyURL(for key: String) -> String? {
        if key.contains("ANTHROPIC") { return "https://console.anthropic.com/settings/keys" }
        if key.contains("OPENAI") { return "https://platform.openai.com/api-keys" }
        if key.contains("GEMINI") || key.contains("GOOGLE") { return "https://aistudio.google.com/app/apikey" }
        if key.contains("GROQ") { return "https://console.groq.com/keys" }
        if key.contains("DEEPSEEK") { return "https://platform.deepseek.com/api_keys" }
        if key.contains("OPENROUTER") { return "https://openrouter.ai/settings/keys" }
        if key.contains("DASHSCOPE") { return "https://dashscope.console.aliyun.com/apiKey" }
        if key.contains("MOONSHOT") { return "https://platform.moonshot.ai/console/api-keys" }
        if key.contains("ZAI") { return "https://open.bigmodel.cn/usercenter/proj-mgmt/apikeys" }
        return nil
    }

    private func envIsGreen(_ agent: AgentKind) -> Bool {
        store.envValidationMessages[agent, default: []].isEmpty
    }

    private func profileBinding(_ keyPath: WritableKeyPath<AgentProfile, String>) -> Binding<String> {
        Binding(
            get: { store.profile(for: selectedProfileAgent)[keyPath: keyPath] },
            set: { value in
                store.updateAgentProfile(for: selectedProfileAgent) { profile in
                    profile[keyPath: keyPath] = value
                }
            }
        )
    }

    private var timeoutBinding: Binding<Int> {
        Binding(
            get: { store.profile(for: selectedProfileAgent).timeoutSeconds },
            set: { value in
                store.updateAgentProfile(for: selectedProfileAgent) { profile in
                    profile.timeoutSeconds = value
                }
            }
        )
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
    var url: String? = nil
    var urlButtonTitle: String = "Öffnen"
    var command: String? = nil
    var focusKey: String? = nil
    var focusAgent: AgentKind? = nil
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
