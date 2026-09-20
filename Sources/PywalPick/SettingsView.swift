import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct SettingsView: View {
    @ObservedObject public var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var showPicker = false
    @State private var activePicker: PickerType = .folder
    @State private var selectedTab: Tab = .paths

    // Deferred path editing: local copies that only apply when user taps Apply
    @State private var pendingWallpaperPath = ""
    @State private var pendingDummyFile = ""
    @State private var pendingWalBinary = ""
    @State private var pendingMatugenBinary = ""
    @State private var pendingCustomScript = ""
    @State private var typeSafeAPIKey = ""
    @State private var typeSafeKeyStatus: PathStatus?
    @State private var typeSafeLastStatus: TypeSafePreferenceStatus?
    @State private var pathStatuses: [PickerType: PathStatus] = [:]

    // CLI state
    @State private var cliInstalled = false
    @State private var cliInstallPath = ""
    @State private var cliInstallMessage: String?

    // Cache maintenance
    @State private var isRebuildingCache = false
    @State private var cacheRebuildMessage: String?

    private enum PickerType: Hashable {
        case folder, dummyFile, walBinary, matugenBinary, script
    }

    private struct PathStatus: Equatable {
        let message: String
        let isError: Bool
    }

    public init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section("Library") {
                    ForEach(Tab.libraryTabs) { tab in
                        sidebarRow(for: tab)
                    }
                }

                Section("System") {
                    ForEach(Tab.systemTabs) { tab in
                        sidebarRow(for: tab)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(.background)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 720, minHeight: 520)
        .onAppear {
            loadPendingPaths()
            loadTypeSafeStatus()
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

    @ViewBuilder
    private func sidebarRow(for tab: Tab) -> some View {
        Label(tab.title, systemImage: tab.icon)
            .symbolRenderingMode(.hierarchical)
            .tag(tab)
    }

    @ViewBuilder
    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: UIStyle.spaceSM) {
                Image(systemName: selectedTab.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .frame(width: 34, height: 34)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: UIStyle.radiusSM, style: .continuous))

                VStack(alignment: .leading, spacing: UIStyle.spaceXS) {
                    Text(selectedTab.title)
                        .font(.title2.weight(.bold))

                    Text(selectedTab.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, UIStyle.spaceXL)
            .padding(.vertical, UIStyle.spaceXL)

            Divider().opacity(0.45)

            Group {
                switch selectedTab {
                case .paths: pathsTab
                case .appearance: appearanceTab
                case .integrations: integrationsTab
                case .cli: cliTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, UIStyle.spaceXL)
            .padding(.bottom, UIStyle.spaceMD)
        }
    }

    @ViewBuilder
    private func settingsPage<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UIStyle.spaceXXL) {
                content()
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.vertical, UIStyle.spaceXL)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func settingsGroup<Content: View>(
        title: String,
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: UIStyle.spaceMD) {
            HStack(alignment: .top, spacing: UIStyle.spaceSM) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(.tint.opacity(0.75))
                    .frame(width: 3, height: 30)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: UIStyle.spaceXS) {
                    Text(title)
                        .font(.headline.weight(.semibold))

                    if let description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .background(
                .regularMaterial.opacity(0.34),
                in: RoundedRectangle(cornerRadius: UIStyle.radiusMD, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: UIStyle.radiusMD, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: UIStyle.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: UIStyle.radiusMD, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Tabs

    private var pathsTab: some View {
        settingsPage {
            settingsGroup(
                title: "Wallpaper setup",
                description: "Choose the folder to browse and the image file wal uses during color extraction."
            ) {
                pathSection(
                    title: "Wallpaper folder",
                    icon: "folder.fill",
                    path: $pendingWallpaperPath,
                    pickerType: .folder,
                    apply: applyWallpaperPath
                )

                pathSection(
                    title: "Dummy file",
                    icon: "doc.fill",
                    path: $pendingDummyFile,
                    pickerType: .dummyFile,
                    apply: applyDummyFile
                )
            }

            settingsGroup(
                title: "Color pipeline",
                description: "Point Pywal Pick at the wal executable used to generate colors."
            ) {
                pathSection(
                    title: "Wal binary",
                    icon: "terminal.fill",
                    path: $pendingWalBinary,
                    pickerType: .walBinary,
                    apply: applyWalBinary,
                    showsFindWal: true
                )
            }
        }
    }

    private var appearanceTab: some View {
        settingsPage {
            settingsGroup(
                title: "Display",
                description: "Set the browser layout and choose how much information appears on each wallpaper."
            ) {
                VStack(alignment: .leading, spacing: UIStyle.spaceMD) {
                    Label("Grid layout", systemImage: "square.grid.3x3")
                        .font(UIStyle.sectionTitle)

                    LabeledContent("Columns") {
                        Stepper(value: $settingsManager.config.gridColumns, in: 2...8) {
                            Text("\(settingsManager.config.gridColumns)")
                                .font(UIStyle.mono)
                                .frame(minWidth: 24, alignment: .trailing)
                        }
                    }

                    Toggle("Show wallpaper names", isOn: $settingsManager.config.showWallpaperNames)
                        .toggleStyle(.switch)
                }
                .uiSettingsSection()

                VStack(alignment: .leading, spacing: UIStyle.spaceMD) {
                    Label("View mode", systemImage: "rectangle.split.3x1")
                        .font(UIStyle.sectionTitle)

                    Picker("Default view", selection: $settingsManager.config.viewMode) {
                        ForEach(ViewMode.allCases) { mode in
                            Label(mode.rawValue.capitalized, systemImage: mode.icon).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .uiSettingsSection()
            }

            settingsGroup(
                title: "Sorting",
                description: "Choose the order used when the wallpaper browser opens."
            ) {
                VStack(alignment: .leading, spacing: UIStyle.spaceMD) {
                    Label("Default sorting", systemImage: "arrow.up.arrow.down")
                        .font(UIStyle.sectionTitle)

                    HStack(spacing: UIStyle.spaceMD) {
                        Picker("Sort by", selection: $settingsManager.config.defaultSortOption) {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Button {
                            settingsManager.config.defaultSortOrder.toggle()
                        } label: {
                            Label(
                                settingsManager.config.defaultSortOrder ? "A–Z" : "Z–A",
                                systemImage: settingsManager.config.defaultSortOrder ? "arrow.up" : "arrow.down"
                            )
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                }
                .uiSettingsSection()
            }

            settingsGroup(
                title: "Transitions",
                description: "Control the animation played above the desktop when a wallpaper is applied."
            ) {
                VStack(alignment: .leading, spacing: UIStyle.spaceMD) {
                    Label("Wallpaper transition", systemImage: "rectangle.on.rectangle.angled")
                        .font(UIStyle.sectionTitle)

                    Picker("Transition", selection: $settingsManager.config.transitionType) {
                        ForEach(TransitionType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    LabeledContent("Duration") {
                        Stepper(
                            value: $settingsManager.config.transitionDuration,
                            in: 0.2...3.0,
                            step: 0.1
                        ) {
                            Text(String(format: "%.1f s", settingsManager.config.transitionDuration))
                                .font(UIStyle.mono)
                                .frame(minWidth: 48, alignment: .trailing)
                        }
                    }

                    LabeledContent("Frame rate") {
                        Stepper(
                            value: $settingsManager.config.transitionFPS,
                            in: 10...120,
                            step: 5
                        ) {
                            Text("\(settingsManager.config.transitionFPS) fps")
                                .font(UIStyle.mono)
                                .frame(minWidth: 64, alignment: .trailing)
                        }
                    }

                    Text("Plays a brief animation above the desktop when a wallpaper is applied.")
                        .font(UIStyle.caption)
                        .foregroundStyle(.secondary)
                }
                .uiSettingsSection()
            }

            settingsGroup(
                title: "Maintenance",
                description: "Refresh generated wallpaper data when previews or color filters need to be rebuilt."
            ) {
                VStack(alignment: .leading, spacing: UIStyle.spaceMD) {
                    Label("Cache", systemImage: "internaldrive")
                        .font(UIStyle.sectionTitle)

                    Text("Clears thumbnail, preview, and color-filter caches, then regenerates them from your wallpaper folder.")
                        .font(UIStyle.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: UIStyle.spaceMD) {
                        Button {
                            rebuildWallpaperCache()
                        } label: {
                            if isRebuildingCache {
                                Label("Rebuilding…", systemImage: "arrow.triangle.2.circlepath")
                            } else {
                                Label("Rebuild wallpaper cache", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRebuildingCache || settingsManager.config.wallpaperFolderPath.isEmpty)
                        .help(
                            settingsManager.config.wallpaperFolderPath.isEmpty
                                ? "Set a wallpaper folder first"
                                : "Clear and regenerate wallpaper caches"
                        )

                        if isRebuildingCache {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if let cacheRebuildMessage {
                        Label(
                            cacheRebuildMessage,
                            systemImage: cacheRebuildMessage.hasPrefix("Failed")
                                ? "exclamationmark.triangle.fill"
                                : "checkmark.circle.fill"
                        )
                        .font(UIStyle.caption)
                        .foregroundStyle(
                            cacheRebuildMessage.hasPrefix("Failed") ? .red : .green
                        )
                    }
                }
                .uiSettingsSection()
            }
        }
    }

    private var integrationsTab: some View {
        settingsPage {
            settingsGroup(
                title: "Color engine",
                description: "Choose how wallpaper colors are extracted and prepared for the rest of the app."
            ) {
                VStack(alignment: .leading, spacing: UIStyle.spaceMD) {
                    Label("Color backend", systemImage: "paintbrush.pointed")
                        .font(UIStyle.sectionTitle)

                    Picker("Color extraction backend", selection: $settingsManager.config.selectedBackend) {
                        ForEach(WalBackend.allCases) { backend in
                            Text(backend.displayName).tag(backend)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text("Determines how wal extracts colors from wallpapers")
                        .font(UIStyle.caption)
                        .foregroundStyle(.secondary)

                    if settingsManager.config.selectedBackend == .matugen {
                        Text("Matugen generates a Material You palette, then Pywal Pick renders it through pywal so existing themes and integrations stay compatible.")
                            .font(UIStyle.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .uiSettingsSection()
            }

            settingsGroup(
                title: "Matugen palette",
                description: "Configure the optional Material You pipeline and its preference service."
            ) {
                pathSection(
                    title: "Matugen binary",
                    icon: "paintpalette",
                    path: $pendingMatugenBinary,
                    pickerType: .matugenBinary,
                    apply: applyMatugenBinary,
                    showsFindMatugen: true
                )

                VStack(alignment: .leading, spacing: UIStyle.spaceMD) {
                    Label("Matugen palette", systemImage: "wand.and.stars")
                        .font(UIStyle.sectionTitle)

                    Picker("Mode", selection: $settingsManager.config.matugenMode) {
                        ForEach(MatugenMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Scheme", selection: $settingsManager.config.matugenSchemeType) {
                        ForEach(MatugenSchemeType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)

                    LabeledContent("Contrast") {
                        Slider(value: $settingsManager.config.matugenContrast, in: -1...1, step: 0.05)
                        Text(String(format: "%+.2f", settingsManager.config.matugenContrast))
                            .font(UIStyle.mono)
                            .frame(width: 42, alignment: .trailing)
                    }

                    Text("Matugen is available as a backend in the main picker and backend cycle. These options apply the next time it is selected.")
                        .font(UIStyle.caption)
                        .foregroundStyle(.secondary)
                }
                .uiSettingsSection()

                VStack(alignment: .leading, spacing: UIStyle.spaceMD) {
                    Label("TypeSafe preference", systemImage: "checkmark.seal")
                        .font(UIStyle.sectionTitle)

                    Toggle("Use TypeSafe color preference", isOn: $settingsManager.config.matugenTypeSafeEnabled)
                        .toggleStyle(.switch)

                    HStack {
                        SecureField("TypeSafe API key", text: $typeSafeAPIKey)
                            .textFieldStyle(.roundedBorder)

                        Button("Save Key") {
                            saveTypeSafeAPIKey()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Clear") {
                            clearTypeSafeAPIKey()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if let typeSafeKeyStatus {
                        Label(
                            typeSafeKeyStatus.message,
                            systemImage: typeSafeKeyStatus.isError ? "exclamationmark.circle" : "checkmark.circle"
                        )
                        .font(UIStyle.caption)
                        .foregroundStyle(typeSafeKeyStatus.isError ? .red : .secondary)
                    }

                    Text("Optional. TypeSafe ranks only Matugen-derived color candidates; the local selector remains the fallback. Only palette metadata is sent.")
                        .font(UIStyle.caption)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .firstTextBaseline) {
                        Label("Last TypeSafe run", systemImage: "clock.arrow.circlepath")
                            .font(UIStyle.caption.weight(.semibold))
                        Spacer()
                        Button("Refresh") {
                            loadTypeSafeStatus()
                        }
                        .buttonStyle(.borderless)
                        .font(UIStyle.caption)
                    }

                    if let typeSafeLastStatus {
                        VStack(alignment: .leading, spacing: UIStyle.spaceXS) {
                            Text(typeSafeLastStatus.summary)
                                .font(UIStyle.caption)
                            Text(typeSafeLastStatus.timestamp.formatted(
                                date: .abbreviated,
                                time: .shortened
                            ))
                            .font(UIStyle.caption)
                            .foregroundStyle(.secondary)

                            if !typeSafeLastStatus.selectedColors.isEmpty {
                                Text(typeSafeLastStatus.selectedColors
                                    .sorted { $0.key < $1.key }
                                    .map { "\($0.key): \($0.value)" }
                                    .joined(separator: " · "))
                                    .font(UIStyle.mono)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                            }
                        }
                        .padding(.vertical, UIStyle.spaceXS)
                    } else {
                        Text("No Matugen run has recorded a TypeSafe result yet. Cache hits do not make another API request.")
                            .font(UIStyle.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .uiSettingsSection()

                HStack {
                    Label("Palette explorer", systemImage: "square.grid.3x3.fill")
                        .font(UIStyle.sectionTitle)

                    Spacer()

                    Button {
                        openWindow(id: "matugen-colors")
                    } label: {
                        Label("Explore all colors", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Inspect every generated Material, Base16, and tonal palette color")
                }
                .uiSettingsSection()
            }

            settingsGroup(
                title: "Browser & scripts",
                description: "Keep browser themes and optional post-processing scripts in sync with wallpaper changes."
            ) {
                VStack(alignment: .leading, spacing: UIStyle.spaceMD) {
                    Label("Browser integration", systemImage: "safari")
                        .font(UIStyle.sectionTitle)

                    Toggle("Run pywalfox update after wal", isOn: $settingsManager.config.runPywalfox)
                        .toggleStyle(.switch)

                    Text("Updates Firefox theme colors automatically")
                        .font(UIStyle.caption)
                        .foregroundStyle(.secondary)
                }
                .uiSettingsSection()

                pathSection(
                    title: "Custom script",
                    icon: "applescript",
                    path: $pendingCustomScript,
                    pickerType: .script,
                    apply: applyCustomScript
                )
            }

            settingsGroup(
                title: "Wallhaven",
                description: "Set the optional API connection and the defaults used by the Wallhaven browser."
            ) {
                VStack(alignment: .leading, spacing: UIStyle.spaceMD) {
                    Label("API key", systemImage: "key")
                        .font(UIStyle.sectionTitle)

                    HStack {
                        SecureField("Enter your Wallhaven API key", text: $settingsManager.config.wallhavenAPIKey)
                            .textFieldStyle(.roundedBorder)

                        Button("Get Key") {
                            NSWorkspace.shared.open(URL(string: "https://wallhaven.cc/settings/account")!)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Text("Optional. Required for NSFW content and access to your collections.")
                        .font(UIStyle.caption)
                        .foregroundStyle(.secondary)
                }
                .uiSettingsSection()

                VStack(alignment: .leading, spacing: UIStyle.spaceMD) {
                    Label("Default filters", systemImage: "line.3.horizontal.decrease.circle")
                        .font(UIStyle.sectionTitle)

                    Text("Applied every time you open the Wallhaven browser.")
                        .font(UIStyle.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: UIStyle.spaceSM) {
                        ForEach(WallhavenCategory.allCases) { category in
                            Toggle(isOn: Binding(
                                get: { settingsManager.config.wallhavenDefaultCategories.contains(category.rawValue) },
                                set: { enabled in
                                    var set = Set(settingsManager.config.wallhavenDefaultCategories)
                                    if enabled { set.insert(category.rawValue) } else { set.remove(category.rawValue) }
                                    settingsManager.config.wallhavenDefaultCategories = Array(set)
                                }
                            )) {
                                Text(category.displayName)
                            }
                            .toggleStyle(.button)
                            .controlSize(.small)
                        }
                    }

                    HStack(spacing: UIStyle.spaceSM) {
                        ForEach(WallhavenPurity.allCases) { purity in
                            Toggle(isOn: Binding(
                                get: { settingsManager.config.wallhavenDefaultPurity.contains(purity.rawValue) },
                                set: { enabled in
                                    var set = Set(settingsManager.config.wallhavenDefaultPurity)
                                    if enabled { set.insert(purity.rawValue) } else { set.remove(purity.rawValue) }
                                    settingsManager.config.wallhavenDefaultPurity = Array(set)
                                }
                            )) {
                                Text(purity.displayName)
                            }
                            .toggleStyle(.button)
                            .controlSize(.small)
                        }
                    }

                    HStack(spacing: UIStyle.spaceMD) {
                        Picker("Sort", selection: $settingsManager.config.wallhavenDefaultSorting) {
                            ForEach(WallhavenSorting.allCases) { sorting in
                                Text(sorting.displayName).tag(sorting.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()

                        Picker("Order", selection: $settingsManager.config.wallhavenDefaultOrder) {
                            Text("Descending").tag("desc")
                            Text("Ascending").tag("asc")
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()

                        Picker("Toplist", selection: $settingsManager.config.wallhavenDefaultTopRange) {
                            ForEach(WallhavenToplistRange.allCases) { range in
                                Text(range.displayName).tag(range.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    HStack(spacing: UIStyle.spaceMD) {
                        Picker("Min resolution", selection: $settingsManager.config.wallhavenDefaultAtLeast) {
                            Text("Any").tag("")
                            Text("1920x1080").tag("1920x1080")
                            Text("2560x1440").tag("2560x1440")
                            Text("3840x2160").tag("3840x2160")
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()

                        Picker("Color", selection: $settingsManager.config.wallhavenDefaultColor) {
                            Text("Any").tag("")
                            ForEach(WallhavenColor.allCases) { color in
                                Text(color.displayName).tag(color.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    HStack(spacing: UIStyle.spaceSM) {
                        ForEach(WallhavenRatio.allCases) { ratio in
                            Toggle(isOn: Binding(
                                get: { settingsManager.config.wallhavenDefaultRatios.contains(ratio.rawValue) },
                                set: { enabled in
                                    var list = settingsManager.config.wallhavenDefaultRatios
                                    if enabled {
                                        if !list.contains(ratio.rawValue) { list.append(ratio.rawValue) }
                                    } else {
                                        list.removeAll { $0 == ratio.rawValue }
                                    }
                                    settingsManager.config.wallhavenDefaultRatios = list
                                }
                            )) {
                                Text(ratio.displayName)
                                    .font(.caption.monospaced())
                            }
                            .toggleStyle(.button)
                            .controlSize(.small)
                        }
                    }
                }
                .uiSettingsSection()
            }
        }
    }

    private var cliTab: some View {
        settingsPage {
            settingsGroup(
                title: "Installation",
                description: "Install wallpick once, then control wallpapers from any terminal session."
            ) {
                VStack(alignment: .leading, spacing: UIStyle.spaceMD) {
                    Label("wallpick CLI tool", systemImage: "terminal")
                        .font(UIStyle.sectionTitle)

                    Text("Install the command-line tool to control wallpapers from your terminal.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    LabeledContent("Install path") {
                        TextField("Install path", text: $cliInstallPath)
                            .textFieldStyle(.roundedBorder)
                            .font(UIStyle.mono)
                            .frame(maxWidth: 360)
                    }

                    HStack(spacing: UIStyle.spaceMD) {
                        Button(action: installCLI) {
                            Label(
                                cliInstalled ? "Reinstall" : "Install",
                                systemImage: cliInstalled ? "checkmark.circle.fill" : "square.and.arrow.down"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(cliInstalled ? .green : .accentColor)
                        .disabled(cliInstallPath.isEmpty)

                        Button(action: uninstallCLI) {
                            Label("Uninstall", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(!cliInstalled)
                    }

                    if let message = cliInstallMessage {
                        Text(message)
                            .font(UIStyle.caption)
                            .foregroundStyle(message.hasPrefix("Error") ? .red : .green)
                    }
                }
                .uiSettingsSection()
            }

            settingsGroup(
                title: "Command reference",
                description: "Common commands for choosing, listing, and refreshing wallpapers."
            ) {
                VStack(alignment: .leading, spacing: UIStyle.spaceSM) {
                    Text("Usage")
                        .font(UIStyle.sectionTitle)

                    Group {
                        Text("wallpick random          - Set a random wallpaper")
                        Text("wallpick set <path>      - Set wallpaper by path")
                        Text("wallpick update          - Re-run wal on current wallpaper")
                        Text("wallpick list [query]    - List wallpapers")
                        Text("wallpick current         - Show current wallpaper")
                    }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                }
                .uiSettingsSection()
            }
        }
    }

    // MARK: - Path Section Component

    private func pathSection(
        title: String,
        icon: String,
        path: Binding<String>,
        pickerType: PickerType,
        apply: @escaping () -> Void,
        showsFindWal: Bool = false,
        showsFindMatugen: Bool = false
    ) -> some View {
        let live = liveValidation(for: path.wrappedValue, type: pickerType)
        let applyStatus = pathStatuses[pickerType]

        return VStack(alignment: .leading, spacing: UIStyle.spaceMD) {
            Label(title, systemImage: icon)
                .font(UIStyle.sectionTitle)

            HStack(spacing: UIStyle.spaceSM) {
                TextField("Path", text: path)
                    .textFieldStyle(.roundedBorder)
                    .font(UIStyle.mono)
                    .onChange(of: path.wrappedValue) { _, _ in
                        // Clear sticky apply message once the user edits again.
                        pathStatuses[pickerType] = nil
                    }

                Button {
                    activePicker = pickerType
                    showPicker = true
                } label: {
                    Label("Browse", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Button {
                    revealInFinder(path.wrappedValue)
                } label: {
                    Label("Reveal", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!canReveal(path.wrappedValue))
                .help("Reveal in Finder")
            }

            HStack(spacing: UIStyle.spaceSM) {
                Button("Apply", action: apply)
                    .buttonStyle(.borderedProminent)
                    .disabled(live?.isError == true)

                if showsFindWal {
                    Button {
                        findWalBinary()
                    } label: {
                        Label("Find wal", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .help("Search common install locations for wal")
                }

                if showsFindMatugen {
                    Button {
                        findMatugenBinary()
                    } label: {
                        Label("Find Matugen", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .help("Search common install locations for matugen")
                }

                if let applyStatus {
                    Label(
                        applyStatus.message,
                        systemImage: applyStatus.isError
                            ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                    )
                    .font(UIStyle.caption)
                    .foregroundStyle(applyStatus.isError ? .red : .green)
                    .labelStyle(.titleAndIcon)
                } else if let live {
                    Label(live.message, systemImage: live.symbol)
                        .font(UIStyle.caption)
                        .foregroundStyle(live.isError ? .orange : .secondary)
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        .uiSettingsSection()
    }

    // MARK: - Helpers

    private func rebuildWallpaperCache() {
        guard !settingsManager.config.wallpaperFolderPath.isEmpty else {
            cacheRebuildMessage = "Failed: set a wallpaper folder first"
            return
        }

        isRebuildingCache = true
        cacheRebuildMessage = nil

        Task.detached(priority: .userInitiated) {
            CacheMaintenance.rebuildAndReload()
            await MainActor.run {
                isRebuildingCache = false
                cacheRebuildMessage = "Cache cleared — regenerating thumbnails and colors"
            }
        }
    }

    private func loadPendingPaths() {
        pendingWallpaperPath = settingsManager.config.wallpaperFolderPath
        pendingDummyFile = settingsManager.config.dummyWallpaperFile
        pendingWalBinary = settingsManager.config.walBinaryPath
        pendingMatugenBinary = settingsManager.config.matugenBinaryPath
        pendingCustomScript = settingsManager.config.customScriptPath
        typeSafeAPIKey = (try? TypeSafeAPIKeyStore.shared.load()) ?? ""
    }

    private func loadTypeSafeStatus() {
        typeSafeLastStatus = TypeSafePreferenceStatusStore.shared.load()
    }

    private func applyPickedPathToPending(_ path: String, for type: PickerType) {
        switch type {
        case .folder:
            pendingWallpaperPath = path
        case .dummyFile:
            pendingDummyFile = path
        case .walBinary:
            pendingWalBinary = path
        case .matugenBinary:
            pendingMatugenBinary = path
        case .script:
            pendingCustomScript = path
        }
        pathStatuses[type] = nil
    }

    private func filePickerTypes(for type: PickerType) -> [UTType] {
        switch type {
        case .folder:
            return [.folder]
        case .dummyFile:
            var types: [UTType] = [.image, .jpeg, .png, .gif, .tiff, .webP]
            if let avif = UTType(filenameExtension: "avif") {
                types.append(avif)
            }
            return types
        case .walBinary:
            return [.unixExecutable, .application]
        case .matugenBinary:
            return [.unixExecutable, .application]
        case .script:
            return [.shellScript, .unixExecutable]
        }
    }

    private func setStatus(_ type: PickerType, message: String, isError: Bool) {
        pathStatuses[type] = PathStatus(message: message, isError: isError)
    }

    private func applyWallpaperPath() {
        let path = pendingWallpaperPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            setStatus(.folder, message: "Path cannot be empty", isError: true)
            return
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            setStatus(.folder, message: "Folder not found", isError: true)
            return
        }
        pendingWallpaperPath = path
        settingsManager.updateWallpaperFolderPath(path)
        setStatus(.folder, message: "Applied — wallpapers will reload", isError: false)
    }

    private func applyDummyFile() {
        let path = pendingDummyFile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            setStatus(.dummyFile, message: "Path cannot be empty", isError: true)
            return
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
            setStatus(.dummyFile, message: "Image file not found", isError: true)
            return
        }
        pendingDummyFile = path
        settingsManager.updateDummyWallpaperFile(path)
        setStatus(.dummyFile, message: "Applied", isError: false)
    }

    private func applyWalBinary() {
        let path = pendingWalBinary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            setStatus(.walBinary, message: "Path cannot be empty", isError: true)
            return
        }
        guard FileManager.default.isExecutableFile(atPath: path) else {
            setStatus(.walBinary, message: "Executable not found at this path", isError: true)
            return
        }
        pendingWalBinary = path
        settingsManager.updateWalBinaryPath(path)
        setStatus(.walBinary, message: "Applied", isError: false)
    }

    private func applyMatugenBinary() {
        let path = pendingMatugenBinary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            setStatus(.matugenBinary, message: "Path cannot be empty", isError: true)
            return
        }
        guard FileManager.default.isExecutableFile(atPath: path) else {
            setStatus(.matugenBinary, message: "Executable not found at this path", isError: true)
            return
        }
        pendingMatugenBinary = path
        settingsManager.config.matugenBinaryPath = path
        setStatus(.matugenBinary, message: "Applied", isError: false)
    }

    private func applyCustomScript() {
        let path = pendingCustomScript.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty {
            settingsManager.config.customScriptPath = ""
            setStatus(.script, message: "Cleared", isError: false)
            return
        }
        guard FileManager.default.fileExists(atPath: path) else {
            setStatus(.script, message: "Script not found", isError: true)
            return
        }
        pendingCustomScript = path
        settingsManager.config.customScriptPath = path
        setStatus(.script, message: "Applied", isError: false)
    }

    private func saveTypeSafeAPIKey() {
        do {
            try TypeSafeAPIKeyStore.shared.save(typeSafeAPIKey)
            typeSafeKeyStatus = PathStatus(message: "Saved securely in Keychain", isError: false)
        } catch {
            typeSafeKeyStatus = PathStatus(message: error.localizedDescription, isError: true)
        }
    }

    private func clearTypeSafeAPIKey() {
        do {
            try TypeSafeAPIKeyStore.shared.remove()
            typeSafeAPIKey = ""
            typeSafeKeyStatus = PathStatus(message: "Cleared", isError: false)
        } catch {
            typeSafeKeyStatus = PathStatus(message: error.localizedDescription, isError: true)
        }
    }

    // MARK: - Path validation / Finder / wal detect

    private struct LiveValidation: Equatable {
        let message: String
        let isError: Bool
        let symbol: String
    }

    private func liveValidation(for path: String, type: PickerType) -> LiveValidation? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if type == .script {
                return LiveValidation(message: "Optional", isError: false, symbol: "info.circle")
            }
            return LiveValidation(message: "Enter a path", isError: true, symbol: "exclamationmark.circle")
        }

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDir)

        switch type {
        case .folder:
            if exists && isDir.boolValue {
                return LiveValidation(message: "Valid folder", isError: false, symbol: "checkmark.circle")
            }
            return LiveValidation(message: "Not a folder", isError: true, symbol: "exclamationmark.triangle")
        case .dummyFile:
            if exists && !isDir.boolValue {
                return LiveValidation(message: "File found", isError: false, symbol: "checkmark.circle")
            }
            return LiveValidation(message: "File not found", isError: true, symbol: "exclamationmark.triangle")
        case .walBinary:
            if FileManager.default.isExecutableFile(atPath: trimmed) {
                return LiveValidation(message: "Executable found", isError: false, symbol: "checkmark.circle")
            }
            if exists {
                return LiveValidation(message: "Not executable", isError: true, symbol: "exclamationmark.triangle")
            }
            return LiveValidation(message: "Binary not found", isError: true, symbol: "exclamationmark.triangle")
        case .matugenBinary:
            if FileManager.default.isExecutableFile(atPath: trimmed) {
                return LiveValidation(message: "Executable found", isError: false, symbol: "checkmark.circle")
            }
            if exists {
                return LiveValidation(message: "Not executable", isError: true, symbol: "exclamationmark.triangle")
            }
            return LiveValidation(message: "Binary not found", isError: true, symbol: "exclamationmark.triangle")
        case .script:
            if exists {
                return LiveValidation(message: "Script found", isError: false, symbol: "checkmark.circle")
            }
            return LiveValidation(message: "Path not found", isError: true, symbol: "exclamationmark.triangle")
        }
    }

    private func canReveal(_ path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && FileManager.default.fileExists(atPath: trimmed)
    }

    private func revealInFinder(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let url = URL(fileURLWithPath: trimmed)
        if FileManager.default.fileExists(atPath: trimmed) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
        }
    }

    private func findWalBinary() {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.local/bin/wal",
            "/opt/homebrew/bin/wal",
            "/usr/local/bin/wal",
            "/usr/bin/wal",
        ]

        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            pendingWalBinary = found
            pathStatuses[.walBinary] = nil
            setStatus(.walBinary, message: "Found at \(found)", isError: false)
            return
        }

        // Fall back to `which wal` using a login-like PATH.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-lc", "which wal"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if task.terminationStatus == 0,
                !output.isEmpty,
                FileManager.default.isExecutableFile(atPath: output)
            {
                pendingWalBinary = output
                pathStatuses[.walBinary] = nil
                setStatus(.walBinary, message: "Found at \(output)", isError: false)
                return
            }
        } catch {
            // fall through
        }

        setStatus(.walBinary, message: "Could not find wal — install pywal or set path manually", isError: true)
    }

    private func findMatugenBinary() {
        let candidates = [
            NSHomeDirectory() + "/.cargo/bin/matugen",
            "/opt/homebrew/bin/matugen",
            "/usr/local/bin/matugen",
            "/usr/bin/matugen",
        ]

        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            pendingMatugenBinary = found
            pathStatuses[.matugenBinary] = nil
            settingsManager.config.matugenBinaryPath = found
            setStatus(.matugenBinary, message: "Found at \(found)", isError: false)
        } else {
            setStatus(.matugenBinary, message: "Could not find matugen — install it or set path manually", isError: true)
        }
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
    private enum Tab: String, CaseIterable, Hashable, Identifiable {
        case paths
        case appearance
        case integrations
        case cli

        var id: String { rawValue }

        static let libraryTabs: [Tab] = [.paths, .appearance]
        static let systemTabs: [Tab] = [.integrations, .cli]

        var title: String {
            switch self {
            case .paths: return "Paths"
            case .appearance: return "Appearance"
            case .integrations: return "Integrations"
            case .cli: return "CLI"
            }
        }

        var subtitle: String {
            switch self {
            case .paths: return "Choose where Pywal Pick finds wallpapers and supporting tools."
            case .appearance: return "Tune the browser layout, sorting, and wallpaper transitions."
            case .integrations: return "Connect color engines, browsers, scripts, and Wallhaven."
            case .cli: return "Install and use wallpick from Terminal."
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
