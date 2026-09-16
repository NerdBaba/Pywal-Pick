import AppKit
import SwiftUI

enum MatugenPaletteExplorer {
    static func filteredSemanticColors(
        in document: MatugenPaletteDocument,
        query: String
    ) -> [MatugenPaletteColor] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return document.semanticColors.values
            .filter { normalizedQuery.isEmpty || $0.id.lowercased().contains(normalizedQuery) }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    static func filteredBase16Colors(
        in document: MatugenPaletteDocument,
        query: String
    ) -> [MatugenPaletteColor] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return document.base16Colors.values
            .filter { normalizedQuery.isEmpty || $0.id.lowercased().contains(normalizedQuery) }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    static func filteredTonalPalettes(
        in document: MatugenPaletteDocument,
        query: String
    ) -> [String: [String: String]] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return document.tonalPalettes.filter { normalizedQuery.isEmpty || $0.key.lowercased().contains(normalizedQuery) }
    }
}

@MainActor
final class MatugenPaletteExplorerModel: ObservableObject {
    @Published private(set) var snapshot: MatugenPaletteSnapshot?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published var searchText = ""
    @Published var selectedMode: MatugenMode = .dark

    private let directory: URL?

    init(directory: URL = MatugenPaletteCache.defaultDirectory) {
        self.directory = directory
    }

    init(document: MatugenPaletteDocument) {
        self.directory = nil
        self.snapshot = MatugenPaletteSnapshot(document: document, generationInfo: nil)
        self.selectedMode = document.mode ?? .dark
    }

    var sectionCount: Int { 3 }

    var additionalVariants: [String] {
        guard let document = snapshot?.document else { return [] }
        return document.availableVariants.filter { $0 != "dark" && $0 != "light" }
    }

    var filteredSemanticColors: [MatugenPaletteColor] {
        guard let document = snapshot?.document else { return [] }
        return MatugenPaletteExplorer.filteredSemanticColors(in: document, query: searchText)
    }

    var filteredBase16Colors: [MatugenPaletteColor] {
        guard let document = snapshot?.document else { return [] }
        return MatugenPaletteExplorer.filteredBase16Colors(in: document, query: searchText)
    }

    var filteredTonalPalettes: [String: [String: String]] {
        guard let document = snapshot?.document else { return [:] }
        return MatugenPaletteExplorer.filteredTonalPalettes(in: document, query: searchText)
    }

    func reload() {
        guard let directory else { return }
        isLoading = true
        errorMessage = nil

        do {
            let loadedSnapshot = try MatugenPaletteCache.load(from: directory)
            snapshot = loadedSnapshot
            selectedMode = loadedSnapshot.document.mode
                ?? loadedSnapshot.generationInfo?.mode
                ?? .dark
        } catch {
            snapshot = nil
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

@MainActor
public struct MatugenPaletteExplorerView: View {
    @StateObject private var model: MatugenPaletteExplorerModel

    public init() {
        _model = StateObject(wrappedValue: MatugenPaletteExplorerModel())
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.45)

            if model.isLoading {
                ProgressView("Loading Matugen colors…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = model.errorMessage {
                stateView(
                    title: "Couldn’t load Matugen colors",
                    message: errorMessage,
                    buttonTitle: "Retry"
                ) {
                    model.reload()
                }
            } else if model.snapshot == nil {
                stateView(
                    title: "No Matugen palette yet",
                    message: "Generate a Matugen theme first, then return here to explore every generated color.",
                    buttonTitle: "Refresh"
                ) {
                    model.reload()
                }
            } else {
                paletteContent
            }
        }
        .frame(minWidth: 980, minHeight: 700)
        .task {
            model.reload()
        }
    }

    private var toolbar: some View {
        HStack(spacing: UIStyle.spaceMD) {
            Label("Matugen Colors", systemImage: "paintpalette.fill")
                .font(.title2.weight(.semibold))

            Spacer()

            HStack(spacing: UIStyle.spaceSM) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search roles and palettes", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 220)
            }
            .padding(.horizontal, UIStyle.spaceMD)
            .padding(.vertical, UIStyle.spaceSM)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: UIStyle.radiusSM))

            Picker("Mode", selection: $model.selectedMode) {
                ForEach(MatugenMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)

            Button {
                model.reload()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .help("Reload the last generated Matugen palette")
        }
        .padding(.horizontal, UIStyle.spaceXL)
        .padding(.vertical, UIStyle.spaceLG)
    }

    private var paletteContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UIStyle.spaceLG) {
                metadataCard
                semanticSection
                base16Section
                tonalSection
            }
            .padding(UIStyle.spaceXL)
        }
    }

    private var metadataCard: some View {
        HStack(spacing: UIStyle.spaceLG) {
            Label("Last generated palette", systemImage: "clock.arrow.circlepath")
                .font(.headline)

            if let info = model.snapshot?.generationInfo {
                Text(info.mode.displayName)
                Text(info.schemeType.displayName)
                Text(String(format: "Contrast %+.2f", info.contrast))
                Text(URL(fileURLWithPath: info.sourcePath).lastPathComponent)
                    .foregroundStyle(.secondary)
            } else {
                Text("Generation metadata unavailable")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .padding(UIStyle.spaceLG)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial.opacity(0.45), in: RoundedRectangle(cornerRadius: UIStyle.radiusMD))
    }

    private var semanticSection: some View {
        paletteSection(title: "Material roles", count: model.filteredSemanticColors.count) {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: UIStyle.spaceSM) {
                    ForEach(model.filteredSemanticColors) { color in
                        colorRow(color)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var base16Section: some View {
        paletteSection(title: "Base16 / pywal", count: model.filteredBase16Colors.count) {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: UIStyle.spaceSM) {
                    ForEach(model.filteredBase16Colors) { color in
                        colorRow(color)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var tonalSection: some View {
        paletteSection(title: "Tonal palettes", count: model.filteredTonalPalettes.count) {
            ForEach(model.filteredTonalPalettes.keys.sorted(), id: \.self) { family in
                let tones = model.filteredTonalPalettes[family] ?? [:]
                VStack(alignment: .leading, spacing: UIStyle.spaceSM) {
                    Text(family.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.headline)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 130), spacing: UIStyle.spaceSM)],
                        alignment: .leading,
                        spacing: UIStyle.spaceSM
                    ) {
                        ForEach(tones.keys.sorted(by: toneSort), id: \.self) { tone in
                            valueCell(label: tone, value: tones[tone])
                        }
                    }
                }
                .padding(.vertical, UIStyle.spaceSM)
            }
        }
    }

    private func paletteSection<Content: View>(
        title: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: UIStyle.spaceMD) {
            HStack {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.bottom, UIStyle.spaceXS)
            content()
        }
        .padding(UIStyle.spaceLG)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial.opacity(0.35), in: RoundedRectangle(cornerRadius: UIStyle.radiusMD))
    }

    private func colorRow(_ color: MatugenPaletteColor) -> some View {
        HStack(spacing: UIStyle.spaceMD) {
            Text(color.id)
                .font(UIStyle.mono)
                .frame(width: 250, alignment: .leading)

            valueCell(label: "Dark", value: color.dark)
            valueCell(label: "Light", value: color.light)
            valueCell(label: "Selected", value: color.value(for: model.selectedMode))
            ForEach(model.additionalVariants, id: \.self) { variant in
                valueCell(
                    label: variant.replacingOccurrences(of: "_", with: " ").capitalized,
                    value: color.variants[variant]
                )
            }
        }
    }

    private func valueCell(label: String, value: String?) -> some View {
        HStack(spacing: UIStyle.spaceSM) {
            RoundedRectangle(cornerRadius: UIStyle.radiusXS, style: .continuous)
                .fill(swatchColor(for: value))
                .frame(width: 24, height: 24)
                .overlay {
                    RoundedRectangle(cornerRadius: UIStyle.radiusXS, style: .continuous)
                        .strokeBorder(.primary.opacity(0.12), lineWidth: UIStyle.hairline)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value ?? "—")
                    .font(.caption.monospaced())
                    .lineLimit(1)
            }

            if let value {
                Button {
                    copy(value)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy \(value)")
            }
        }
        .frame(minWidth: 165, alignment: .leading)
    }

    private func stateView(
        title: String,
        message: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: UIStyle.spaceMD) {
            Image(systemName: "paintpalette")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)
            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(UIStyle.spaceXL)
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func swatchColor(for value: String?) -> Color {
        guard let value else { return .secondary.opacity(0.18) }
        let digits = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard digits.count == 6, let number = UInt64(digits, radix: 16) else {
            return .secondary.opacity(0.18)
        }
        return Color(
            nsColor: NSColor(
                srgbRed: CGFloat((number >> 16) & 0xff) / 255,
                green: CGFloat((number >> 8) & 0xff) / 255,
                blue: CGFloat(number & 0xff) / 255,
                alpha: 1
            )
        )
    }

    private func toneSort(_ lhs: String, _ rhs: String) -> Bool {
        switch (Int(lhs), Int(rhs)) {
        case let (.some(left), .some(right)):
            return left < right
        default:
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }
}
