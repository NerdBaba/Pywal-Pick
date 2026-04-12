import SwiftUI
import UniformTypeIdentifiers

public struct SettingsView: View {
    @ObservedObject public var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false
    @State private var activePicker: PickerType = .folder

    private enum PickerType {
        case folder, script
    }

    public init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }

    public var body: some View {
        VStack(spacing: 20) {
            Text("Settings")
                .font(.largeTitle)
                .fontWeight(.bold)

            Form {
                Section(header: Text("Wallpaper Folder")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current folder:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(settingsManager.config.wallpaperFolderPath.isEmpty ? "No folder selected" : settingsManager.config.wallpaperFolderPath)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.primary)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)

                        Button("Choose Wallpaper Folder") {
                            activePicker = .folder
                            showPicker = true
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Section(header: Text("Dummy File Path")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Selected wallpapers will be copied to:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(settingsManager.config.dummyWallpaperFile)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.primary)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                    }
                }

                Section(header: Text("Wal Binary Path")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Path to wal binary:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("Path to wal binary", text: $settingsManager.config.walBinaryPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                        Text("Command will be run as: [path] -i [dummy-file] -n --backend [selected]")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Wal Backend")) {
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

                Section(header: Text("Default Sorting")) {
                    Picker("Sort by", selection: $settingsManager.config.defaultSortOption) {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Ascending Order", isOn: $settingsManager.config.defaultSortOrder)
                }
                
                Section(header: Text("Grid Layout")) {
                    HStack {
                        Text("Columns:")
                        Stepper(value: $settingsManager.config.gridColumns, in: 2...8) {
                            Text("\(settingsManager.config.gridColumns)")
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
                
                Section(header: Text("Browser Integration")) {
                    Toggle("Run pywalfox update after wal", isOn: $settingsManager.config.runPywalfox)
                    Text("Updates Firefox theme colors automatically")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Custom Script")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Script to run after wallpaper selection:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            TextField("Path to shell script", text: $settingsManager.config.customScriptPath)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))

                            Button("Choose Script") {
                                activePicker = .script
                                showPicker = true
                            }
                            .buttonStyle(.bordered)
                        }

                        Text("Executed after wal and pywalfox, with no arguments")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 500)
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: activePicker == .folder ? [.folder] : [.shellScript, .unixExecutable],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let selectedURL = urls.first {
                    switch activePicker {
                    case .folder:
                        settingsManager.updateWallpaperFolderPath(selectedURL.path)
                    case .script:
                        settingsManager.config.customScriptPath = selectedURL.path
                    }
                }
            case .failure(let error):
                print("Failed to select file: \(error.localizedDescription)")
            }
        }
    }
}