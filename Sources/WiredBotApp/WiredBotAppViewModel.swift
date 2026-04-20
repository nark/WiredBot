import AppKit
import Darwin
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WiredBotCore

enum BotInstallState: String {
    case uninstalled
    case installed
    case running
    case stopped

    var title: String {
        switch self {
        case .uninstalled: return "Uninstalled"
        case .installed: return "Installed"
        case .running: return "Running"
        case .stopped: return "Stopped"
        }
    }

    var color: Color {
        switch self {
        case .running: return .green
        case .installed: return .blue
        case .stopped: return .orange
        case .uninstalled: return .secondary
        }
    }
}

enum ProviderStatus: Equatable {
    case unknown
    case checking
    case available(String)
    case unavailable(String)

    var title: String {
        switch self {
        case .unknown: return "Unknown"
        case .checking: return "Checking..."
        case .available(let detail): return detail
        case .unavailable(let detail): return detail
        }
    }

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var color: Color {
        switch self {
        case .available: return .green
        case .checking: return .blue
        case .unavailable: return .red
        case .unknown: return .secondary
        }
    }
}

@MainActor
final class WiredBotAppViewModel: ObservableObject {
    @Published var config = BotConfig()
    @Published var installState: BotInstallState = .uninstalled
    @Published var providerStatus: ProviderStatus = .unknown
    @Published var serverPassword = ""
    @Published var isBusy = false
    @Published var statusMessage = ""
    @Published var logsText = ""
    @Published var showError = false
    @Published var errorMessage = ""
    @Published private(set) var hasUnsavedChanges = false

    @AppStorage("wiredbot.launchAtLogin") var launchAtLogin = true

    private let fileManager = FileManager.default
    private let launchAgentLabel = "fr.read-write.wiredbot"
    private var pollTimer: Timer?
    private var savedConfig = BotConfig()
    private var savedServerPassword = ""

    var applicationSupportURL: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WiredBot", isDirectory: true)
    }

    var binURL: URL { applicationSupportURL.appendingPathComponent("bin", isDirectory: true) }
    var etcURL: URL { applicationSupportURL.appendingPathComponent("etc", isDirectory: true) }
    var logURL: URL { applicationSupportURL.appendingPathComponent("Logs", isDirectory: true) }
    var binaryURL: URL { binURL.appendingPathComponent("wiredbot") }
    var configURL: URL { etcURL.appendingPathComponent("wiredbot.json") }
    var bundledSpecURL: URL { applicationSupportURL.appendingPathComponent("wired.xml") }
    var stdoutURL: URL { logURL.appendingPathComponent("wiredbot.out.log") }
    var stderrURL: URL { logURL.appendingPathComponent("wiredbot.err.log") }

    var launchAgentPlistURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(launchAgentLabel).plist")
    }

    var launchctlDomain: String { "gui/\(getuid())" }
    var launchctlService: String { "\(launchctlDomain)/\(launchAgentLabel)" }

    var menuBarSymbolName: String {
        switch installState {
        case .running: return "bolt.circle.fill"
        case .installed, .stopped: return "bolt.circle"
        case .uninstalled: return "bolt.slash.circle"
        }
    }

    var launchdPID: Int32? {
        let result = runProcess("/bin/launchctl", ["print", launchctlService])
        guard result.status == 0 else { return nil }

        for line in result.output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("pid =") {
                let value = trimmed.replacingOccurrences(of: "pid =", with: "")
                    .trimmingCharacters(in: .whitespaces)
                return Int32(value)
            }
        }

        return nil
    }

    var isLaunchAgentLoaded: Bool {
        runProcess("/bin/launchctl", ["print", launchctlService]).status == 0
    }

    var isInstalled: Bool {
        fileManager.isExecutableFile(atPath: binaryURL.path)
            && fileManager.fileExists(atPath: configURL.path)
            && fileManager.fileExists(atPath: launchAgentPlistURL.path)
    }

    var providerTitle: String {
        config.llm.provider.capitalized
    }

    var serverKeychainService: String {
        ServerPasswordKeychain.service(for: config.server)
    }

    var serverKeychainAccount: String {
        ServerPasswordKeychain.account(for: config.server)
    }

    var modelTitle: String {
        config.llm.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "-" : config.llm.model
    }

    var identityIconImage: NSImage? {
        guard
            let icon = config.identity.icon,
            let data = Data(base64Encoded: icon)
        else {
            return nil
        }

        return NSImage(data: data)
    }

    func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshState()
                self?.refreshLogs()
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func refreshAll() async {
        loadConfig()
        await refreshState()
        refreshLogs()
        await checkProvider()
    }

    func refreshState() async {
        if !isInstalled {
            installState = .uninstalled
        } else if launchdPID != nil {
            installState = .running
        } else if isLaunchAgentLoaded {
            installState = .installed
        } else {
            installState = .stopped
        }
    }

    func installBot() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            try bootstrapRuntime()
            try installBinary()
            try installSpecIfNeeded()
            if !fileManager.fileExists(atPath: configURL.path) {
                config.daemon.foreground = true
                config.daemon.pidFile = applicationSupportURL.appendingPathComponent("wiredbot.pid").path
                config.daemon.logFile = stdoutURL.path
                try saveConfig()
            }
            try writeLaunchAgentPlist()
            if launchAtLogin {
                try bootstrapLaunchAgent()
            }
            statusMessage = "Wired Bot installed"
            await refreshState()
        } catch {
            publish(error)
        }
    }

    func uninstallBot() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            try? stopBot()
            if fileManager.fileExists(atPath: launchAgentPlistURL.path) {
                try fileManager.removeItem(at: launchAgentPlistURL)
            }
            if fileManager.fileExists(atPath: applicationSupportURL.path) {
                try fileManager.removeItem(at: applicationSupportURL)
            }
            config = BotConfig()
            statusMessage = "Wired Bot uninstalled"
            await refreshState()
        } catch {
            publish(error)
        }
    }

    func startBot() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            if !isInstalled {
                try bootstrapRuntime()
                try installBinary()
                try installSpecIfNeeded()
                try saveConfig()
                try writeLaunchAgentPlist()
            } else {
                try saveConfig()
                try writeLaunchAgentPlist()
            }
            try bootstrapLaunchAgent()
            statusMessage = "Wired Bot started"
            await refreshState()
        } catch {
            publish(error)
        }
    }

    func stopBot() throws {
        _ = runProcess("/bin/launchctl", ["bootout", launchctlService])
        _ = runProcess("/bin/launchctl", ["bootout", launchctlDomain, launchAgentPlistURL.path])
        statusMessage = "Wired Bot stopped"
    }

    func stopBotFromUI() async {
        do {
            try stopBot()
            await refreshState()
        } catch {
            publish(error)
        }
    }

    func restartBot() async {
        try? stopBot()
        try? await Task.sleep(nanoseconds: 500_000_000)
        await startBot()
    }

    func toggleLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = enabled
        guard isInstalled else { return }

        do {
            if enabled {
                try writeLaunchAgentPlist()
                try bootstrapLaunchAgent()
            } else if installState != .running {
                _ = runProcess("/bin/launchctl", ["bootout", launchctlService])
            }
        } catch {
            publish(error)
        }
    }

    func loadConfig() {
        guard fileManager.fileExists(atPath: configURL.path) else {
            config = BotConfig()
            configureRuntimeDefaults()
            rememberSavedConfiguration()
            return
        }

        do {
            config = try ConfigLoader.load(from: configURL.path)
            configureRuntimeDefaults()
            loadServerPassword()
            rememberSavedConfiguration()
        } catch {
            publish(error)
        }
    }

    func saveConfigFromUI() {
        do {
            try saveConfig()
            try writeLaunchAgentPlist()
            rememberSavedConfiguration()
            reloadRunningBotIfNeeded()
        } catch {
            publish(error)
        }
    }

    func updateUnsavedChanges() {
        hasUnsavedChanges = config != savedConfig || serverPassword != savedServerPassword
    }

    @discardableResult
    func saveForPendingAction() -> Bool {
        do {
            try saveConfig()
            try writeLaunchAgentPlist()
            rememberSavedConfiguration()
            reloadRunningBotIfNeeded()
            return true
        } catch {
            publish(error)
            return false
        }
    }

    func discardUnsavedChanges() async {
        loadConfig()
        await refreshState()
        refreshLogs()
        await checkProvider()
        statusMessage = "Unsaved changes discarded"
    }

    func confirmDiscardUnsavedChanges(message: String) -> Bool {
        guard hasUnsavedChanges else { return true }

        let alert = NSAlert()
        alert.messageText = "Unsaved Changes"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return saveForPendingAction()
        case .alertSecondButtonReturn:
            loadConfig()
            return true
        default:
            return false
        }
    }

    func chooseSpecPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK {
            config.server.specPath = panel.url?.path
            saveConfigFromUI()
        }
    }

    func chooseIdentityIcon() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .gif, .bmp, .heic, .image]
        panel.prompt = "Choose"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try normalizedPNGData(from: url)
            config.identity.icon = data.base64EncodedString()
            saveConfigFromUI()
        } catch {
            publish(error)
        }
    }

    func clearIdentityIcon() {
        config.identity.icon = nil
        saveConfigFromUI()
    }

    func revealRuntimeFolder() {
        NSWorkspace.shared.open(applicationSupportURL)
    }

    func openConfigFile() {
        NSWorkspace.shared.open(configURL)
    }

    func refreshLogs() {
        let paths = [stderrURL.path, stdoutURL.path, config.daemon.logFile ?? ""].filter { !$0.isEmpty }
        var collected: [String] = []
        for path in paths where fileManager.fileExists(atPath: path) {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let text = String(data: Data(data.suffix(30_000)), encoding: .utf8),
               !text.isEmpty {
                collected.append("== \(path) ==\n\(text)")
            }
        }
        logsText = collected.joined(separator: "\n\n")
    }

    func checkProvider() async {
        providerStatus = .checking
        let llm = config.llm

        do {
            switch llm.provider.lowercased() {
            case "ollama":
                try await checkOllama(llm)
            case "openai":
                try await checkOpenAICompatible(llm)
            case "anthropic":
                providerStatus = llm.apiKey?.isEmpty == false
                    ? .available("API key configured")
                    : .unavailable("Missing API key")
            default:
                providerStatus = .unavailable("Unsupported provider")
            }
        } catch {
            providerStatus = .unavailable(error.localizedDescription)
        }
    }

    private func checkOllama(_ llm: LLMConfig) async throws {
        let base = llm.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/api/tags") else {
            providerStatus = .unavailable("Invalid endpoint")
            return
        }

        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 5))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            providerStatus = .unavailable("Ollama did not answer")
            return
        }

        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let models = (json?["models"] as? [[String: Any]]) ?? []
        let names = models.compactMap { $0["name"] as? String }
        if names.contains(where: { $0 == llm.model || $0.hasPrefix("\(llm.model):") }) {
            providerStatus = .available("Connected, model found")
        } else {
            providerStatus = .available("Connected, model not listed")
        }
    }

    private func checkOpenAICompatible(_ llm: LLMConfig) async throws {
        let base = llm.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/v1/models") else {
            providerStatus = .unavailable("Invalid endpoint")
            return
        }

        var request = URLRequest(url: url, timeoutInterval: 5)
        if let key = llm.apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) {
            providerStatus = .available("Connected")
        } else {
            providerStatus = .unavailable("HTTP \(status)")
        }
    }

    private func bootstrapRuntime() throws {
        try fileManager.createDirectory(at: binURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: etcURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: logURL, withIntermediateDirectories: true)
    }

    private func normalizedPNGData(from url: URL) throws -> Data {
        guard let image = NSImage(contentsOf: url) else {
            throw WiredBotAppError.invalidImage
        }

        let targetSize = NSSize(width: 128, height: 128)
        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        resized.unlockFocus()

        guard
            let tiff = resized.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw WiredBotAppError.invalidImage
        }

        return png
    }

    private func installBinary() throws {
        guard let source = resolveSourceBinary() else {
            throw WiredBotAppError.missingBundledBinary
        }

        if fileManager.fileExists(atPath: binaryURL.path) {
            try fileManager.removeItem(at: binaryURL)
        }
        try fileManager.copyItem(at: source, to: binaryURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)
    }

    private func installSpecIfNeeded() throws {
        guard !fileManager.fileExists(atPath: bundledSpecURL.path) else { return }

        if let bundled = Bundle.main.url(forResource: "wired", withExtension: "xml") {
            try fileManager.copyItem(at: bundled, to: bundledSpecURL)
            return
        }

        let checkout = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/checkouts/WiredSwift/Sources/WiredSwift/Resources/wired.xml")
        if fileManager.fileExists(atPath: checkout.path) {
            try fileManager.copyItem(at: checkout, to: bundledSpecURL)
        }
    }

    private func resolveSourceBinary() -> URL? {
        let bundleCandidates = [
            Bundle.main.url(forResource: "wiredbot", withExtension: nil),
            Bundle.main.url(forResource: "WiredBot", withExtension: nil)
        ].compactMap { $0 }

        let devCandidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/release/WiredBot"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/debug/WiredBot")
        ]

        return (bundleCandidates + devCandidates).first {
            fileManager.isExecutableFile(atPath: $0.path)
        }
    }

    private func configureRuntimeDefaults() {
        config.daemon.foreground = true
        config.daemon.pidFile = applicationSupportURL.appendingPathComponent("wiredbot.pid").path
        if config.daemon.logFile == nil {
            config.daemon.logFile = stdoutURL.path
        }
        if config.server.specPath == nil, fileManager.fileExists(atPath: bundledSpecURL.path) {
            config.server.specPath = bundledSpecURL.path
        }
    }

    private func saveConfig() throws {
        try bootstrapRuntime()
        configureRuntimeDefaults()
        try persistServerPasswordIfNeeded()
        try ConfigLoader.save(config, to: configURL.path)
    }

    private func rememberSavedConfiguration() {
        savedConfig = config
        savedServerPassword = serverPassword
        hasUnsavedChanges = false
    }

    private func reloadRunningBotIfNeeded() {
        guard installState == .running || launchdPID != nil else {
            statusMessage = "Configuration saved"
            return
        }

        guard let pid = launchdPID else {
            statusMessage = "Configuration saved; reload will apply on next start"
            return
        }

        if kill(pid, SIGHUP) == 0 {
            statusMessage = "Configuration saved and bot reloaded"
        } else {
            statusMessage = "Configuration saved; reload signal failed"
        }
    }

    private func loadServerPassword() {
        if let password = URLComponents(string: config.server.url)?.password, !password.isEmpty {
            serverPassword = password
            return
        }

        guard config.server.useKeychainPassword else {
            serverPassword = ""
            return
        }

        do {
            serverPassword = try ServerPasswordKeychain.readPassword(
                service: serverKeychainService,
                account: serverKeychainAccount
            ) ?? ""
        } catch {
            publish(error)
        }
    }

    private func persistServerPasswordIfNeeded() throws {
        guard config.server.useKeychainPassword else { return }

        if !serverPassword.isEmpty {
            try ServerPasswordKeychain.savePassword(
                serverPassword,
                service: serverKeychainService,
                account: serverKeychainAccount
            )
        }
        config.server.url = ServerPasswordKeychain.sanitizedURL(config.server.url)
    }

    private func writeLaunchAgentPlist() throws {
        try bootstrapRuntime()

        let arguments = [
            binaryURL.path,
            "run",
            "--config", configURL.path,
            "--spec", config.server.specPath ?? bundledSpecURL.path,
            "--foreground"
        ]

        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": arguments,
            "WorkingDirectory": applicationSupportURL.path,
            "RunAtLoad": true,
            "KeepAlive": false,
            "StandardOutPath": stdoutURL.path,
            "StandardErrorPath": stderrURL.path
        ]

        let launchAgentsDirectory = launchAgentPlistURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)

        guard (plist as NSDictionary).write(to: launchAgentPlistURL, atomically: true) else {
            throw WiredBotAppError.launchAgentWriteFailed
        }
    }

    private func bootstrapLaunchAgent() throws {
        _ = runProcess("/bin/launchctl", ["bootout", launchctlService])
        _ = runProcess("/bin/launchctl", ["bootout", launchctlDomain, launchAgentPlistURL.path])

        let result = runProcess("/bin/launchctl", ["bootstrap", launchctlDomain, launchAgentPlistURL.path])
        if result.status != 0 {
            throw WiredBotAppError.launchctlFailed(result.errorOutput.isEmpty ? result.output : result.errorOutput)
        }
    }

    private func runProcess(_ launchPath: String, _ arguments: [String]) -> ProcessResult {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return ProcessResult(status: 1, output: "", errorOutput: error.localizedDescription)
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ProcessResult(status: task.terminationStatus, output: output, errorOutput: errorOutput)
    }

    private func publish(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
        statusMessage = error.localizedDescription
    }
}

private struct ProcessResult {
    let status: Int32
    let output: String
    let errorOutput: String
}

private enum WiredBotAppError: LocalizedError {
    case missingBundledBinary
    case invalidImage
    case launchAgentWriteFailed
    case launchctlFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingBundledBinary:
            return "Could not find the WiredBot command-line binary to install."
        case .invalidImage:
            return "Could not read this image."
        case .launchAgentWriteFailed:
            return "Could not write the LaunchAgent plist."
        case .launchctlFailed(let message):
            return "launchctl failed: \(message)"
        }
    }
}
