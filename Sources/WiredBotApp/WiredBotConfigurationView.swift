import AppKit
import SwiftUI
import WiredBotCore

struct WiredBotConfigurationView: View {
    @EnvironmentObject private var model: WiredBotAppViewModel
    @State private var selectedPane: BotSettingsPane = .dashboard
    @State private var pendingPane: BotSettingsPane?
    @State private var showReloadConfirmation = false
    @State private var showSidebarDiscardConfirmation = false

    var body: some View {
        NavigationSplitView {
            List(BotSettingsPane.allCases, selection: sidebarSelection) { pane in
                Label(pane.title, systemImage: pane.symbolName)
                    .tag(pane)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } detail: {
            ScrollView {
                detailView
                    .frame(maxWidth: 880, alignment: .topLeading)
                    .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Wired Bot")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showReloadConfirmation = true
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")

                Button {
                    model.saveConfigFromUI()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Save configuration")
            }
        }
        .alert("Wired Bot", isPresented: $model.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage)
        }
        .alert("Reload Configuration", isPresented: $showReloadConfirmation) {
            Button("Reload", role: .destructive) {
                Task { await model.discardUnsavedChanges() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to reload the configuration? Unsaved changes will be lost.")
        }
        .alert("Unsaved Changes", isPresented: $showSidebarDiscardConfirmation) {
            Button("Save") {
                guard let pendingPane else { return }
                if model.saveForPendingAction() {
                    selectedPane = pendingPane
                    self.pendingPane = nil
                }
            }
            Button("Discard", role: .destructive) {
                guard let pendingPane else { return }
                Task {
                    await model.discardUnsavedChanges()
                    selectedPane = pendingPane
                    self.pendingPane = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingPane = nil
            }
        } message: {
            Text("You have unsaved changes. Unsaved changes will be lost.")
        }
        .onChange(of: model.config) { _ in
            model.updateUnsavedChanges()
        }
        .onChange(of: model.serverPassword) { _ in
            model.updateUnsavedChanges()
        }
        .background(WindowCloseGuard(model: model))
    }

    private var sidebarSelection: Binding<BotSettingsPane?> {
        Binding(
            get: { selectedPane },
            set: { newValue in
                guard let newValue, newValue != selectedPane else { return }
                if model.hasUnsavedChanges {
                    pendingPane = newValue
                    showSidebarDiscardConfirmation = true
                } else {
                    selectedPane = newValue
                }
            }
        )
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedPane {
        case .dashboard:
            DashboardPane()
        case .server:
            ServerPane()
        case .identity:
            IdentityPane()
        case .llm:
            LLMPane()
        case .behavior:
            BehaviorPane()
        case .triggers:
            TriggersPane()
        case .daemon:
            DaemonPane()
        case .logs:
            LogsPane()
        }
    }
}

private enum BotSettingsPane: String, CaseIterable, Identifiable {
    case dashboard
    case server
    case identity
    case llm
    case behavior
    case triggers
    case daemon
    case logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .server: return "Server"
        case .identity: return "Identity"
        case .llm: return "LLM"
        case .behavior: return "Behavior"
        case .triggers: return "Triggers"
        case .daemon: return "Daemon"
        case .logs: return "Logs"
        }
    }

    var symbolName: String {
        switch self {
        case .dashboard: return "rectangle.3.group.bubble"
        case .server: return "network"
        case .identity: return "person.text.rectangle"
        case .llm: return "brain.head.profile"
        case .behavior: return "switch.2"
        case .triggers: return "bolt.badge.clock"
        case .daemon: return "gearshape.2"
        case .logs: return "doc.text"
        }
    }
}

private struct DashboardPane: View {
    @EnvironmentObject private var model: WiredBotAppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Header(title: "Wired Bot", subtitle: model.statusMessage)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                StatusCard(title: "Bot status", value: model.installState.title, symbolName: model.menuBarSymbolName, color: model.installState.color)
                StatusCard(title: "LLM model", value: model.modelTitle, symbolName: "brain.head.profile", color: .purple)
                StatusCard(title: "Provider", value: "\(model.providerTitle) · \(model.providerStatus.title)", symbolName: "network", color: model.providerStatus.color)
                StatusCard(title: "Config", value: model.configURL.path, symbolName: "doc.badge.gearshape", color: .blue)
            }

            SettingsSection("Execution") {
                HStack(spacing: 10) {
                    Button(model.installState == .running ? "Stop" : "Start") {
                        Task {
                            if model.installState == .running {
                                await model.stopBotFromUI()
                            } else {
                                await model.startBot()
                            }
                        }
                    }
                    .keyboardShortcut(.defaultAction)

                    Button("Restart") {
                        Task { await model.restartBot() }
                    }
                    .disabled(model.installState != .running)

                    Button("Install") {
                        Task { await model.installBot() }
                    }
                    .disabled(model.installState != .uninstalled || model.isBusy)

                    Button("Uninstall") {
                        Task { await model.uninstallBot() }
                    }
                    .disabled(model.installState == .running || model.installState == .uninstalled || model.isBusy)

                    Spacer()

                    Button {
                        model.revealRuntimeFolder()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Show runtime folder")
                }

                Toggle("Start with launchd at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.toggleLaunchAtLogin($0) }
                ))
            }
        }
    }
}

private struct ServerPane: View {
    @EnvironmentObject private var model: WiredBotAppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Header(title: "Server", subtitle: "Connection details for the Wired server.")
            SettingsSection("Connection") {
                TextField("Wired URL", text: $model.config.server.url)
                    .textFieldStyle(.roundedBorder)
                Toggle("Store server password in Keychain", isOn: $model.config.server.useKeychainPassword)
                SecureField("Server password", text: $model.serverPassword)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!model.config.server.useKeychainPassword)
                ArrayField(title: "Chat room IDs", values: $model.config.server.channels)
                NumericField("Reconnect delay", value: $model.config.server.reconnectDelay, suffix: "seconds")
                IntField("Max reconnect attempts", value: $model.config.server.maxReconnectAttempts, suffix: "0 = unlimited")
            }
        }
    }
}

private struct IdentityPane: View {
    @EnvironmentObject private var model: WiredBotAppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Header(title: "Identity", subtitle: "How the bot appears on the Wired server.")
            SettingsSection("Profile") {
                HStack(alignment: .center, spacing: 14) {
                    IdentityIconPreview(image: model.identityIconImage)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Button {
                                model.chooseIdentityIcon()
                            } label: {
                                Label("Choose Icon", systemImage: "photo")
                            }

                            Button(role: .destructive) {
                                model.clearIdentityIcon()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .disabled(model.config.identity.icon == nil)
                            .help("Clear icon")
                        }

                        Text(model.config.identity.icon == nil ? "Default Wired icon" : "Custom icon embedded in the bot configuration")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                TextField("Nick", text: $model.config.identity.nick)
                    .textFieldStyle(.roundedBorder)
                TextField("Status", text: $model.config.identity.status)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: Binding(
                    get: { model.config.identity.identityPreamble ?? "" },
                    set: { model.config.identity.identityPreamble = $0.isEmpty ? nil : $0 }
                ))
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
                TokenHelp(tokens: ["{nick}", "{model}", "{provider}", "{status}", "{server}"])
            }
        }
    }
}

private struct IdentityIconPreview: View {
    let image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else {
                Image(systemName: "person.crop.square")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 82, height: 82)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2))
        )
    }
}

private struct LLMPane: View {
    @EnvironmentObject private var model: WiredBotAppViewModel
    private let providers = ["ollama", "openai", "anthropic"]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Header(title: "LLM", subtitle: "\(model.providerTitle) · \(model.providerStatus.title)")
            SettingsSection("Provider") {
                Picker("Provider", selection: $model.config.llm.provider) {
                    ForEach(providers, id: \.self) { Text($0.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)

                TextField("Endpoint", text: $model.config.llm.endpoint)
                    .textFieldStyle(.roundedBorder)
                TextField("Model", text: $model.config.llm.model)
                    .textFieldStyle(.roundedBorder)
                SecureField("API key", text: Binding(
                    get: { model.config.llm.apiKey ?? "" },
                    set: { model.config.llm.apiKey = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Check Provider") {
                        Task { await model.checkProvider() }
                    }
                    Label(model.providerStatus.title, systemImage: model.providerStatus.isAvailable ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(model.providerStatus.color)
                }
            }

            SettingsSection("Generation") {
                NumericField("Temperature", value: $model.config.llm.temperature, suffix: "0.0 - 1.0")
                IntField("Max tokens", value: $model.config.llm.maxTokens)
                IntField("Context messages", value: $model.config.llm.contextMessages)
                NumericField("Timeout", value: $model.config.llm.timeoutSeconds, suffix: "seconds")
                NumericField("Context max age", value: $model.config.llm.contextMaxAgeSeconds, suffix: "seconds, 0 = no expiry")
                Toggle("Summarize old context", isOn: $model.config.llm.enableSummarization)
            }

            SettingsSection("System prompt") {
                TextEditor(text: $model.config.llm.systemPrompt)
                    .font(.body)
                    .frame(minHeight: 160)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
            }
        }
    }
}

private struct BehaviorPane: View {
    @EnvironmentObject private var model: WiredBotAppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Header(title: "Behavior", subtitle: "Rules that decide when the bot speaks.")
            SettingsSection("Replies") {
                Toggle("Respond to mentions", isOn: $model.config.behavior.respondToMentions)
                Toggle("Respond to all public messages", isOn: $model.config.behavior.respondToAll)
                Toggle("Respond to private messages", isOn: $model.config.behavior.respondToPrivateMessages)
                Toggle("Continue active conversations", isOn: $model.config.behavior.respondToConversation)
                Toggle("Respond after bot posts", isOn: $model.config.behavior.respondAfterBotPost)
                Toggle("Reply in the user's language", isOn: $model.config.behavior.respondInUserLanguage)
                Toggle("Ignore own messages", isOn: $model.config.behavior.ignoreOwnMessages)
            }

            SettingsSection("Messages") {
                Toggle("Greet on join", isOn: $model.config.behavior.greetOnJoin)
                TextField("Greeting", text: $model.config.behavior.greetMessage)
                    .textFieldStyle(.roundedBorder)
                TokenHelp(tokens: ["{nick}", "{chatID}"])
                Toggle("Farewell on leave", isOn: $model.config.behavior.farewellOnLeave)
                TextField("Farewell", text: $model.config.behavior.farewellMessage)
                    .textFieldStyle(.roundedBorder)
                TokenHelp(tokens: ["{nick}", "{chatID}"])
                Toggle("Announce file uploads", isOn: $model.config.behavior.announceFileUploads)
                TextField("File upload message", text: $model.config.behavior.announceFileMessage)
                    .textFieldStyle(.roundedBorder)
                TokenHelp(tokens: ["{nick}", "{filename}", "{path}"])
            }

            SettingsSection("Limits and filters") {
                NumericField("Rate limit", value: $model.config.behavior.rateLimitSeconds, suffix: "seconds")
                IntField("Max response length", value: $model.config.behavior.maxResponseLength)
                NumericField("Thread timeout", value: $model.config.behavior.threadTimeoutSeconds, suffix: "seconds")
                StringArrayField(title: "Mention keywords", values: $model.config.behavior.mentionKeywords)
                StringArrayField(title: "Ignored nicks", values: $model.config.behavior.ignoredNicks)
            }

            SettingsSection("Spontaneous replies") {
                Toggle("Allow spontaneous interjections", isOn: $model.config.behavior.spontaneousReply)
                IntField("Check interval", value: $model.config.behavior.spontaneousCheckInterval, suffix: "messages")
                NumericField("Cooldown", value: $model.config.behavior.spontaneousCooldownSeconds, suffix: "seconds")
            }
        }
    }
}

private struct TriggersPane: View {
    @EnvironmentObject private var model: WiredBotAppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Header(title: "Triggers", subtitle: "\(model.config.triggers.count) configured trigger(s).")

            HStack {
                Button {
                    model.config.triggers.append(TriggerConfig(name: "new-trigger", pattern: "^!command"))
                } label: {
                    Label("Add", systemImage: "plus")
                }
                Spacer()
            }

            ForEach(model.config.triggers.indices, id: \.self) { index in
                TriggerEditor(trigger: $model.config.triggers[index]) {
                    model.config.triggers.remove(at: index)
                }
            }
        }
    }
}

private struct TriggerEditor: View {
    @Binding var trigger: TriggerConfig
    let delete: () -> Void

    var body: some View {
        SettingsSection(trigger.name.isEmpty ? "Trigger" : trigger.name) {
            HStack {
                TextField("Name", text: $trigger.name)
                    .textFieldStyle(.roundedBorder)
                Button(role: .destructive, action: delete) {
                    Image(systemName: "trash")
                }
                .help("Delete trigger")
            }
            TextField("Pattern", text: $trigger.pattern)
                .textFieldStyle(.roundedBorder)
            TriggerEventTypesPicker(values: $trigger.eventTypes)
            Toggle("Use LLM", isOn: $trigger.useLLM)
            Toggle("Case sensitive", isOn: $trigger.caseSensitive)
            NumericField("Cooldown", value: $trigger.cooldownSeconds, suffix: "seconds")
            TextField("Static response", text: Binding(
                get: { trigger.response ?? "" },
                set: { trigger.response = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
            TokenHelp(tokens: responseTokens)
            TextField("LLM prompt prefix", text: Binding(
                get: { trigger.llmPromptPrefix ?? "" },
                set: { trigger.llmPromptPrefix = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
            TokenHelp(tokens: responseTokens)
        }
    }

    private var responseTokens: [String] {
        let eventTypes = Set(trigger.eventTypes)
        if eventTypes.contains("thread_added") || eventTypes.contains("thread_changed") {
            return ["{nick}", "{subject}", "{board}", "{text}"]
        }
        return ["{nick}", "{input}", "{chatID}"]
    }
}

private struct TokenHelp: View {
    let tokens: [String]

    var body: some View {
        if !tokens.isEmpty {
            Text("Available tokens: \(tokens.joined(separator: ", "))")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

private struct TriggerEventTypesPicker: View {
    @Binding var values: [String]

    private let options: [TriggerEventTypeOption] = [
        .init(id: "chat", title: "Chat messages", detail: "Public chat messages"),
        .init(id: "private", title: "Private messages", detail: "Direct messages to the bot"),
        .init(id: "thread_added", title: "Board threads", detail: "New board thread"),
        .init(id: "thread_changed", title: "Board replies", detail: "New reply on a board thread"),
        .init(id: "all", title: "All trigger events", detail: "Match any supported trigger event")
    ]

    var body: some View {
        FieldRow("Event types") {
            VStack(alignment: .leading, spacing: 6) {
                Menu {
                    ForEach(options) { option in
                        Button {
                            toggle(option.id)
                        } label: {
                            if values.contains(option.id) {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }

                    if hasUnknownValues {
                        Divider()
                        ForEach(unknownValues, id: \.self) { value in
                            Button {
                                toggle(value)
                            } label: {
                                Label(value, systemImage: "questionmark.circle")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(summary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .menuStyle(.button)

                if !values.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(values, id: \.self) { value in
                            Text(title(for: value))
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.secondary.opacity(0.12)))
                        }
                    }
                }
            }
        }
    }

    private var summary: String {
        if values.isEmpty {
            return "No event selected"
        }
        return values.map(title(for:)).joined(separator: ", ")
    }

    private var knownIDs: Set<String> {
        Set(options.map(\.id))
    }

    private var unknownValues: [String] {
        values.filter { !knownIDs.contains($0) }
    }

    private var hasUnknownValues: Bool {
        !unknownValues.isEmpty
    }

    private func title(for value: String) -> String {
        options.first(where: { $0.id == value })?.title ?? value
    }

    private func toggle(_ id: String) {
        if id == "all" {
            values = values.contains("all") ? [] : ["all"]
            return
        }

        if values.contains(id) {
            values.removeAll { $0 == id }
        } else {
            values.removeAll { $0 == "all" }
            values.append(id)
        }

        if values.isEmpty {
            values = ["chat"]
        }
    }
}

private struct TriggerEventTypeOption: Identifiable {
    let id: String
    let title: String
    let detail: String
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: spacing) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DaemonPane: View {
    @EnvironmentObject private var model: WiredBotAppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Header(title: "Daemon", subtitle: "macOS launchd runtime.")
            SettingsSection("LaunchAgent") {
                PathRow(title: "Runtime", value: model.applicationSupportURL.path)
                PathRow(title: "Binary", value: model.binaryURL.path)
                PathRow(title: "LaunchAgent", value: model.launchAgentPlistURL.path)
                PathRow(title: "Config", value: model.configURL.path)
                HStack {
                    Button("Show Runtime Folder") { model.revealRuntimeFolder() }
                    Button("Open Config JSON") { model.openConfigFile() }
                }
            }

            SettingsSection("Bot daemon fields") {
                Toggle("Foreground", isOn: $model.config.daemon.foreground)
                    .disabled(true)
                PathField(title: "PID file", path: $model.config.daemon.pidFile) {}
                PathField(title: "Log file", path: Binding(
                    get: { model.config.daemon.logFile ?? "" },
                    set: { model.config.daemon.logFile = $0.isEmpty ? nil : $0 }
                )) {}
                Picker("Log level", selection: $model.config.daemon.logLevel) {
                    ForEach(["VERBOSE", "DEBUG", "INFO", "WARNING", "ERROR"], id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

private struct LogsPane: View {
    @EnvironmentObject private var model: WiredBotAppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Header(title: "Logs", subtitle: model.stderrURL.path)
            TextEditor(text: .constant(model.logsText.isEmpty ? "No logs yet." : model.logsText))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 520)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
        }
    }
}

private struct Header: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.largeTitle.weight(.semibold))
            if !subtitle.isEmpty {
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        } label: {
            Text(title)
                .font(.headline)
        }
    }
}

private enum FormLayout {
    static let labelWidth: CGFloat = 160
    static let controlSpacing: CGFloat = 12
    static let numberFieldWidth: CGFloat = 120
}

private struct FieldRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: FormLayout.controlSpacing) {
            Text(title)
                .frame(width: FormLayout.labelWidth, alignment: .trailing)
                .foregroundStyle(.primary)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct StatusCard: View {
    let title: String
    let value: String
    let symbolName: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: symbolName)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(value)
                .font(.headline)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.18)))
    }
}

private struct NumericField: View {
    let title: String
    @Binding var value: Double
    let suffix: String

    init(_ title: String, value: Binding<Double>, suffix: String = "") {
        self.title = title
        self._value = value
        self.suffix = suffix
    }

    var body: some View {
        FieldRow(title) {
            HStack {
                TextField(title, value: $value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: FormLayout.numberFieldWidth)
                if !suffix.isEmpty {
                    Text(suffix)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct IntField: View {
    let title: String
    @Binding var value: Int
    let suffix: String

    init(_ title: String, value: Binding<Int>, suffix: String = "") {
        self.title = title
        self._value = value
        self.suffix = suffix
    }

    var body: some View {
        FieldRow(title) {
            HStack {
                TextField(title, value: $value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: FormLayout.numberFieldWidth)
                if !suffix.isEmpty {
                    Text(suffix)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ArrayField: View {
    let title: String
    @Binding var values: [UInt32]

    var body: some View {
        FieldRow(title) {
            TextField(title, text: Binding(
                get: { values.map(String.init).joined(separator: ", ") },
                set: { text in
                    values = text
                        .split(separator: ",")
                        .compactMap { UInt32($0.trimmingCharacters(in: .whitespaces)) }
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct StringArrayField: View {
    let title: String
    @Binding var values: [String]

    var body: some View {
        FieldRow(title) {
            TextField(title, text: Binding(
                get: { values.joined(separator: ", ") },
                set: { text in
                    values = text
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct PathField: View {
    let title: String
    @Binding var path: String
    let choose: () -> Void

    var body: some View {
        FieldRow(title) {
            HStack {
                TextField(title, text: $path)
                    .textFieldStyle(.roundedBorder)
                if !path.isEmpty {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Reveal")
                }
                Button {
                    choose()
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("Choose")
            }
        }
    }
}

private struct PathRow: View {
    let title: String
    let value: String

    var body: some View {
        FieldRow(title) {
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}
