import SwiftUI
import UniformTypeIdentifiers

public struct SettingsView: View {
    @ObservedObject public var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false
    @State private var activePicker: PickerType = .folder
    @State private var selectedTab = "paths"

    // Deferred path editing: local copies that only apply when user taps Apply
    @State private var pendingWallpaperPath = ""
    @State private var pendingDummyFile = ""
    @State private var pendingWalBinary = ""
    @State private var pendingCustomScript = ""
    @State private var pathStatus: PathStatus?

    // CLI state
    @State private var cliInstalled = false
    @State private var cliInstallPath = ""
    @State private var cliInstallMessage: String?

    private enum PickerType {
        case folder, dummyFile, walBinary, script
    }

    private struct PathStatus: Equatable {
        let message: String
        let isError: Bool
    }

    public init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.title)
                    .fontWeight(.bold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // Tab picker
            Picker("Settings", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.id) { tab in
                    Label(tab.title, systemImage: tab.icon).tag(tab.id)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            // Tab content
            TabView(selection: $selectedTab) {
                pathsTab
                    .tag("paths")
                appearanceTab
                    .tag("appearance")
                integrationsTab
                    .tag("integrations")
                cliTab
                    .tag("cli")
            }
            .tabViewStyle(.automatic)
            .padding(.horizontal, 20)
        }
        .padding()
        .frame(minWidth: 620, minHeight: 480)
        .onAppear {
            loadPendingPaths()
            cliInstallPath = defaultCLIPath
            checkCLIInstallation()
        }
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: filePickerTypes(for: activePicker),
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let selectedURL = urls.first {
                    applyPickedPathToPending(selectedURL.path, for: activePicker)
                }
            case .failure(let error):
                print("Failed to select file: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Tabs

    private var pathsTab: some View {
        ScrollView {
            VStack(spacing: 24) {
                pathSection(
                    title: "Wallpaper Folder",
                    icon: "folder.fill",
                    path: $pendingWallpaperPath,
                    pickerType: .folder,
                    allowedTypes: [.folder],
                    apply: applyWallpaperPath
                )

                pathSection(
                    title: "Dummy File",
                    icon: "doc.fill",
                    path: $pendingDummyFile,
                    pickerType: .dummyFile,
                    allowedTypes: [.image, .jpeg, .png],
                    apply: applyDummyFile
                )

                pathSection(
                    title: "Wal Binary",
                    icon: "terminal.fill",
                    path: $pendingWalBinary,
                    pickerType: .walBinary,
                    allowedTypes: [.unixExecutable, .application],
                    apply: applyWalBinary
                )
            }
            .padding(.vertical, 8)
        }
    }

    private var appearanceTab: some View {
        ScrollView {
            VStack(spacing: 24) {
                Group {
                    Text("Default Sorting")
                        .font(.headline)

                    HStack(spacing: 16) {
                        Picker("Sort by", selection: $settingsManager.config.defaultSortOption) {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)

                        Button(action: {
                            settingsManager.config.defaultSortOrder.toggle()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: settingsManager.config.defaultSortOrder ? "arrow.up" : "arrow.down")
                                Text(settingsManager.config.defaultSortOrder ? "A-Z" : "Z-A")
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Divider()

                Group {
                    Text("Grid Layout")
                        .font(.headline)

                    HStack {
                        Text("Columns:")
                        Stepper(value: $settingsManager.config.gridColumns, in: 2...8) {
                            Text("\(settingsManager.config.gridColumns)")
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }

                Divider()

                Group {
                    Text("View Mode")
                        .font(.headline)

                    Picker("Default view", selection: $settingsManager.config.viewMode) {
                        ForEach(ViewMode.allCases) { mode in
                            Label(mode.rawValue.capitalized, systemImage: mode.icon).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var integrationsTab: some View {
        ScrollView {
            VStack(spacing: 24) {
                Group {
                    Text("Wal Backend")
                        .font(.headline)

                    Picker("Color extraction backend:", selection: $settingsManager.config.selectedBackend) {
                        ForEach(WalBackend.allCases) { backend in
                            Text(backend.displayName).tag(backend)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Determines how wal extracts colors from wallpapers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                Group {
                    Text("Browser Integration")
                        .font(.headline)

                    Toggle("Run pywalfox update after wal", isOn: $settingsManager.config.runPywalfox)
                    Text("Updates Firefox theme colors automatically")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                pathSection(
                    title: "Custom Script",
                    icon: "script",
                    path: $pendingCustomScript,
                    pickerType: .script,
                    allowedTypes: [.shellScript, .unixExecutable],
                    apply: applyCustomScript
                )
            }
            .padding(.vertical, 8)
        }
    }

    private var cliTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "terminal")
                        .font(.title2)
                    Text("wallpick CLI Tool")
                        .font(.headline)
                }

                Text("Install the command-line tool to control wallpapers from your terminal.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack {
                    Text("Install path:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Install path", text: $cliInstallPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                HStack(spacing: 12) {
                    Button(action: installCLI) {
                        Label(cliInstalled ? "Reinstall" : "Install", systemImage: cliInstalled ? "checkmark.circle.fill" : "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(cliInstalled ? .green : .blue)
                    .disabled(cliInstallPath.isEmpty)

                    Button(action: uninstallCLI) {
                        Label("Uninstall", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(!cliInstalled)

                    if let message = cliInstallMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(message.hasPrefix("Error") ? .red : .green)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Usage")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("wallpick random          - Set a random wallpaper")
                        .font(.system(.caption, design: .monospaced))
                    Text("wallpick fzf               - Pick wallpaper interactively via fzf")
                        .font(.system(.caption, design: .monospaced))
                    Text("wallpick set <path>        - Set wallpaper by path")
                        .font(.system(.caption, design: .monospaced))
                    Text("wallpick update            - Re-run wal on current wallpaper")
                        .font(.system(.caption, design: .monospaced))
                    Text("wallpick list [query]      - List wallpapers")
                        .font(.system(.caption, design: .monospaced))
                    Text("wallpick current           - Show current wallpaper")
                        .font(.system(.caption, design: .monospaced))
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Path Section Component

    private func pathSection(
        title: String,
        icon: String,
        path: Binding<String>,
        pickerType: PickerType,
        allowedTypes: [UTType],
        apply: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.headline)
            }

            HStack(spacing: 8) {
                TextField("Path", text: path)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                Button("Browse") {
                    activePicker = pickerType
                    showPicker = true
                    // Update pending path after picker returns
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        pendingWallpaperPath = pendingWallpaperPath
                    }
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Button("Apply") {
                    apply()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                if let status = pathStatus {
                    Text(status.message)
                        .font(.caption)
                        .foregroundColor(status.isError ? .red : .green)
                }
            }
        }
    }

    // MARK: - Helpers

    private func loadPendingPaths() {
        pendingWallpaperPath = settingsManager.config.wallpaperFolderPath
        pendingDummyFile = settingsManager.config.dummyWallpaperFile
        pendingWalBinary = settingsManager.config.walBinaryPath
        pendingCustomScript = settingsManager.config.customScriptPath
    }

    private func applyPickedPathToPending(_ path: String, for type: PickerType) {
        switch type {
        case .folder:
            pendingWallpaperPath = path
        case .dummyFile:
            pendingDummyFile = path
        case .walBinary:
            pendingWalBinary = path
        case .script:
            pendingCustomScript = path
        }
    }

    private func filePickerTypes(for type: PickerType) -> [UTType] {
        switch type {
        case .folder:
            return [.folder]
        case .dummyFile:
            return [.image, .jpeg, .png, .gif, .tiff, .webP]
        case .walBinary:
            return [.unixExecutable, .application]
        case .script:
            return [.shellScript, .unixExecutable]
        }
    }

    private func applyWallpaperPath() {
        guard !pendingWallpaperPath.isEmpty else {
            pathStatus = PathStatus(message: "Path cannot be empty", isError: true)
            return
        }
        if !FileManager.default.fileExists(atPath: pendingWallpaperPath) {
            pathStatus = PathStatus(message: "Path does not exist", isError: true)
            return
        }
        settingsManager.updateWallpaperFolderPath(pendingWallpaperPath)
        pathStatus = PathStatus(message: "Applied wallpapers will reload", isError: false)
    }

    private func applyDummyFile() {
        guard !pendingDummyFile.isEmpty else {
            pathStatus = PathStatus(message: "Path cannot be empty", isError: true)
            return
        }
        settingsManager.updateDummyWallpaperFile(pendingDummyFile)
        pathStatus = PathStatus(message: "Applied", isError: false)
    }

    private func applyWalBinary() {
        guard !pendingWalBinary.isEmpty else {
            pathStatus = PathStatus(message: "Path cannot be empty", isError: true)
            return
        }
        if !FileManager.default.fileExists(atPath: pendingWalBinary) {
            pathStatus = PathStatus(message: "Binary not found at this path", isError: true)
            return
        }
        settingsManager.updateWalBinaryPath(pendingWalBinary)
        pathStatus = PathStatus(message: "Applied", isError: false)
    }

    private func applyCustomScript() {
        settingsManager.config.customScriptPath = pendingCustomScript
        pathStatus = PathStatus(message: "Applied", isError: false)
    }

    // MARK: - CLI Installation

    private var defaultCLIPath: String {
        NSHomeDirectory() + "/.local/bin/wallpick"
    }

    private func checkCLIInstallation() {
        let installPath = cliInstallPath.isEmpty ? defaultCLIPath : cliInstallPath
        cliInstalled = FileManager.default.fileExists(atPath: installPath)
    }

    private func installCLI() {
        let installPath = cliInstallPath.isEmpty ? defaultCLIPath : cliInstallPath
        cliInstallMessage = nil

        let bundlePath = Bundle.main.bundlePath + "/Contents/MacOS/wallpick"
        let fm = FileManager.default

        guard fm.fileExists(atPath: bundlePath) else {
            cliInstallMessage = "Error: wallpick binary not found in app bundle. Build the app first."
            return
        }

        let targetDir = (installPath as NSString).deletingLastPathComponent
        do {
            try fm.createDirectory(atPath: targetDir, withIntermediateDirectories: true)
        } catch {
            cliInstallMessage = "Error creating directory: \(error.localizedDescription)"
            return
        }

        if fm.fileExists(atPath: installPath) {
            try? fm.removeItem(atPath: installPath)
        }

        do {
            try fm.copyItem(atPath: bundlePath, toPath: installPath)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installPath)
            cliInstallMessage = "Installed to \(installPath)"
            cliInstalled = true
        } catch {
            cliInstallMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func uninstallCLI() {
        let installPath = cliInstallPath.isEmpty ? defaultCLIPath : cliInstallPath
        cliInstallMessage = nil

        do {
            try FileManager.default.removeItem(atPath: installPath)
            cliInstallMessage = "Uninstalled from \(installPath)"
            cliInstalled = false
        } catch {
            cliInstallMessage = "Error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Tab Definition

extension SettingsView {
    private enum Tab: String, CaseIterable, Identifiable {
        case paths
        case appearance
        case integrations
        case cli

        var id: String { rawValue }
        var title: String {
            switch self {
            case .paths: return "Paths"
            case .appearance: return "Appearance"
            case .integrations: return "Integrations"
            case .cli: return "CLI"
            }
        }
        var icon: String {
            switch self {
            case .paths: return "folder.badge.gearshape"
            case .appearance: return "paintpalette"
            case .integrations: return "link"
            case .cli: return "terminal"
            }
        }
    }
}
