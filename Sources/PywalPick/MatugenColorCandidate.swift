import Foundation

/// A safe color that can be assigned to one pywal role.
public struct MatugenColorCandidate: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let hex: String
    public let family: String
    public let tone: Double?
    public let contrast: Double
    public let chroma: Double
    public let nearExtreme: Bool
}

/// The complete set of Matugen-derived choices for one generated theme.
public struct MatugenThemeCandidateSet: Equatable, Sendable {
    let mode: MatugenMode
    let schemeType: MatugenSchemeType
    let background: ThemeColor
    let foreground: ThemeColor
    let choices: [String: [MatugenColorCandidate]]
    let cursorChoices: [MatugenColorCandidate]
    let localColors: [String: String]
    let localCursor: String

    func accepts(_ hex: String, for slot: String) -> Bool {
        choices[slot]?.contains(where: { $0.hex == hex }) == true
    }

    func acceptsCursor(_ hex: String) -> Bool {
        cursorChoices.contains(where: { $0.hex == hex })
    }

    /// Keeps only candidate-backed choices and drops avoidable duplicate
    /// assignments from a remote ranking response. The local palette remains
    /// in place for any rejected slot.
    func acceptedPreferences(_ preferred: [String: String]) -> [String: String] {
        var accepted: [String: String] = [:]
        var used = Set<String>()

        for slot in choices.keys.sorted() {
            guard let value = preferred[slot],
                  let options = choices[slot],
                  options.contains(where: { $0.hex == value })
            else { continue }

            if used.contains(value), options.contains(where: { $0.hex != value && !used.contains($0.hex) }) {
                continue
            }
            accepted[slot] = value
            used.insert(value)
        }

        if let cursor = preferred["cursor"], acceptsCursor(cursor) {
            accepted["cursor"] = cursor
        }
        return accepted
    }
}

enum MatugenColorCandidateBuilder {
    private struct SlotDefinition {
        let slot: String
        let family: String
        let targetTone: Double
        let semanticName: String?
    }

    static func build(
        document: MatugenPaletteDocument,
        mode: MatugenMode,
        schemeType: MatugenSchemeType
    ) throws -> MatugenThemeCandidateSet {
        let background = try ThemeColor(hex: MatugenThemeConverter.color(
            named: "surface",
            from: document.semanticColors,
            mode: mode
        ))
        let foreground = try ThemeColor(hex: MatugenThemeConverter.color(
            named: "on_surface",
            from: document.semanticColors,
            mode: mode
        ))
        let dark = mode == .dark
        let normalTone = dark ? 70.0 : 40.0
        let brightTone = dark ? 80.0 : 30.0
        let allNeutral = schemeType == .schemeMonochrome || schemeType == .schemeNeutral
        let families: [String: String] = allNeutral
            ? ["error": "neutral", "tertiary": "neutral", "secondary": "neutral", "primary": "neutral"]
            : ["error": "error", "tertiary": "tertiary", "secondary": "secondary", "primary": "primary"]

        let definitions: [SlotDefinition] = [
            SlotDefinition(slot: "color1", family: "error", targetTone: normalTone, semanticName: allNeutral ? nil : "error"),
            SlotDefinition(slot: "color2", family: "tertiary", targetTone: normalTone, semanticName: allNeutral ? nil : "tertiary"),
            SlotDefinition(slot: "color3", family: "secondary", targetTone: normalTone, semanticName: allNeutral ? nil : "secondary"),
            SlotDefinition(slot: "color4", family: "primary", targetTone: normalTone, semanticName: allNeutral ? nil : "primary"),
            SlotDefinition(slot: "color5", family: "secondary", targetTone: brightTone, semanticName: nil),
            SlotDefinition(slot: "color6", family: "tertiary", targetTone: brightTone, semanticName: nil),
            SlotDefinition(slot: "color9", family: "error", targetTone: brightTone, semanticName: nil),
            SlotDefinition(slot: "color10", family: "tertiary", targetTone: brightTone, semanticName: nil),
            SlotDefinition(slot: "color11", family: "secondary", targetTone: brightTone, semanticName: nil),
            SlotDefinition(slot: "color12", family: "primary", targetTone: brightTone, semanticName: nil),
            SlotDefinition(slot: "color13", family: "secondary", targetTone: brightTone, semanticName: nil),
            SlotDefinition(slot: "color14", family: "tertiary", targetTone: brightTone, semanticName: nil),
        ]

        var choices: [String: [MatugenColorCandidate]] = [:]
        for definition in definitions {
            choices[definition.slot] = try candidates(
                family: families[definition.family] ?? definition.family,
                semanticName: definition.semanticName,
                targetTone: definition.targetTone,
                background: background,
                mode: mode,
                document: document,
                minimumContrast: 4.5
            )
        }

        let color8 = try candidates(
            family: "neutral",
            semanticName: "on_surface_variant",
            targetTone: brightTone,
            background: background,
            mode: mode,
            document: document,
            minimumContrast: 4.5
        )
        choices["color8"] = color8

        var localColors: [String: String] = [
            "color0": background.hex,
            "color7": foreground.hex,
            "color15": foreground.hex,
            "color8": chooseBest(color8, targetTone: brightTone, used: [])?.hex ?? foreground.hex,
        ]
        var used = Set(localColors.values)
        for definition in definitions {
            guard let options = choices[definition.slot],
                  let selected = chooseBest(options, targetTone: definition.targetTone, used: used)
            else {
                throw MatugenToneSelectionError.noReadableTone(
                    family: definition.family,
                    minimumContrast: 4.5
                )
            }
            localColors[definition.slot] = selected.hex
            used.insert(selected.hex)
        }

        let cursorChoices = try candidates(
            family: families["primary"] ?? "primary",
            semanticName: "primary",
            targetTone: normalTone,
            background: background,
            mode: mode,
            document: document,
            minimumContrast: 3
        )
        guard let localCursor = chooseBest(cursorChoices, targetTone: normalTone, used: [])?.hex else {
            throw MatugenToneSelectionError.noReadableTone(family: "primary", minimumContrast: 3)
        }

        return MatugenThemeCandidateSet(
            mode: mode,
            schemeType: schemeType,
            background: background,
            foreground: foreground,
            choices: choices,
            cursorChoices: cursorChoices,
            localColors: localColors,
            localCursor: localCursor
        )
    }

    private static func candidates(
        family: String,
        semanticName: String?,
        targetTone: Double,
        background: ThemeColor,
        mode: MatugenMode,
        document: MatugenPaletteDocument,
        minimumContrast: Double
    ) throws -> [MatugenColorCandidate] {
        var values: [MatugenColorCandidate] = []
        if let semanticName,
           document.semanticColors[semanticName] != nil {
            let value = try MatugenThemeConverter.color(
                named: semanticName,
                from: document.semanticColors,
                mode: mode
            )
            if let candidate = makeCandidate(
                id: "semantic-\(semanticName)",
                hex: value,
                family: family,
                tone: nil,
                background: background,
                minimumContrast: minimumContrast
            ) {
                values.append(candidate)
            }
        }

        guard let palette = document.tonalPalettes[family] else {
            throw MatugenThemeError.missingColor("palettes.\(family)")
        }
        for (tone, value) in palette {
            guard let toneValue = Double(tone),
                  let candidate = makeCandidate(
                      id: "\(family)-\(tone)",
                      hex: value,
                      family: family,
                      tone: toneValue,
                      background: background,
                      minimumContrast: minimumContrast
                  )
            else { continue }
            values.append(candidate)
        }

        var deduplicated: [String: MatugenColorCandidate] = [:]
        for candidate in values {
            if let existing = deduplicated[candidate.hex],
               existing.nearExtreme && !candidate.nearExtreme {
                deduplicated[candidate.hex] = candidate
            } else {
                deduplicated[candidate.hex] = candidate
            }
        }
        let sorted = deduplicated.values.sorted { left, right in
            let leftDistance = abs((left.tone ?? targetTone) - targetTone)
            let rightDistance = abs((right.tone ?? targetTone) - targetTone)
            if leftDistance != rightDistance { return leftDistance < rightDistance }
            if left.nearExtreme != right.nearExtreme { return !left.nearExtreme }
            if left.contrast != right.contrast { return left.contrast < right.contrast }
            return left.id < right.id
        }
        // Keep extreme black/white candidates available only when the palette
        // offers no safer readable alternative. This protects both the local
        // selector and an optional remote ranker from choosing a technically
        // contrasting but visually harsh ANSI color.
        let safe = sorted.filter { !$0.nearExtreme }
        return safe.isEmpty ? sorted : safe
    }

    private static func makeCandidate(
        id: String,
        hex: String,
        family: String,
        tone: Double?,
        background: ThemeColor,
        minimumContrast: Double
    ) -> MatugenColorCandidate? {
        guard let parsed = try? ThemeColor(hex: hex) else { return nil }
        let contrast = parsed.contrastRatio(to: background)
        guard contrast >= minimumContrast else { return nil }
        return MatugenColorCandidate(
            id: id,
            hex: parsed.hex,
            family: family,
            tone: tone,
            contrast: contrast,
            chroma: parsed.chroma,
            nearExtreme: parsed.isNearExtreme
        )
    }

    private static func chooseBest(
        _ candidates: [MatugenColorCandidate],
        targetTone: Double,
        used: Set<String>
    ) -> MatugenColorCandidate? {
        candidates.min { left, right in
            let leftScore = score(left, targetTone: targetTone, used: used)
            let rightScore = score(right, targetTone: targetTone, used: used)
            if leftScore != rightScore { return leftScore < rightScore }
            return left.id < right.id
        }
    }

    private static func score(
        _ candidate: MatugenColorCandidate,
        targetTone: Double,
        used: Set<String>
    ) -> Double {
        let toneDistance = abs((candidate.tone ?? targetTone) - targetTone)
        let highContrastPenalty = max(0, candidate.contrast - 12) * 1.5
        let extremePenalty = candidate.nearExtreme ? 100.0 : 0
        let duplicatePenalty = used.contains(candidate.hex) ? 8.0 : 0
        return toneDistance + highContrastPenalty + extremePenalty + duplicatePenalty
    }
}
