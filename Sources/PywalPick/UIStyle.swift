import SwiftUI

/// Shared visual tokens for a noticeable but structure-preserving macOS polish.
enum UIStyle {
    // MARK: - Radii

    static let radiusXS: CGFloat = 6
    static let radiusSM: CGFloat = 8
    static let radiusMD: CGFloat = 12
    static let radiusLG: CGFloat = 16
    static let radiusXL: CGFloat = 20

    // MARK: - Spacing

    static let spaceXS: CGFloat = 6
    static let spaceSM: CGFloat = 8
    static let spaceMD: CGFloat = 12
    static let spaceLG: CGFloat = 16
    static let spaceXL: CGFloat = 20
    static let spaceXXL: CGFloat = 24

    // MARK: - Strokes / selection

    static let selectionLineWidth: CGFloat = 2.5
    static let highlightLineWidth: CGFloat = 2
    static let hairline: CGFloat = 1

    // MARK: - Typography

    static let brandTitleSize: CGFloat = 26
    static let sectionTitle: Font = .headline
    static let controlLabel: Font = .subheadline.weight(.medium)
    static let caption: Font = .caption
    static let mono: Font = .system(.body, design: .monospaced)

    // MARK: - Shadows

    static let cardShadow = ShadowStyle(color: .black.opacity(0.12), radius: 6, y: 3)
    static let elevatedShadow = ShadowStyle(color: .black.opacity(0.22), radius: 18, y: 10)
    static let toastShadow = ShadowStyle(color: .black.opacity(0.18), radius: 10, y: 4)

    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let y: CGFloat
    }
}

// MARK: - View helpers

extension View {
    /// Soft glass panel used for content wells (grid/carousel container).
    func uiContentWell() -> some View {
        self
            .padding(UIStyle.spaceMD)
            .background(.regularMaterial.opacity(0.55), in: RoundedRectangle(cornerRadius: UIStyle.radiusMD, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: UIStyle.radiusMD, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: UIStyle.hairline)
            )
            .padding(UIStyle.spaceSM)
    }

    /// Search / chip chrome.
    func uiGlassChip(cornerRadius: CGFloat = UIStyle.radiusMD) -> some View {
        self
            .padding(.horizontal, UIStyle.spaceLG)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: UIStyle.hairline)
            )
    }

    /// Settings section card.
    func uiSettingsSection() -> some View {
        self
            .padding(UIStyle.spaceLG)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial.opacity(0.45), in: RoundedRectangle(cornerRadius: UIStyle.radiusMD, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: UIStyle.radiusMD, style: .continuous)
                    .strokeBorder(.primary.opacity(0.06), lineWidth: UIStyle.hairline)
            )
    }

    func uiElevatedShadow(_ style: UIStyle.ShadowStyle = UIStyle.elevatedShadow) -> some View {
        shadow(color: style.color, radius: style.radius, x: 0, y: style.y)
    }
}
