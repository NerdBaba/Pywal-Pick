import SwiftUI

/// Parallelogram shape with configurable slant.
struct ParallelogramShape: Shape {
    let slant: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: slant, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - slant, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Wallhaven-style color filter bar with parallelogram swatches.
struct ColorFilterBar: View {
    @Binding var selectedGroup: ColorGroup?
    let colorCounts: [ColorGroup: Int]
    let totalCount: Int

    private let slant: CGFloat = 7
    private let swatchHeight: CGFloat = 28
    private let swatchMinWidth: CGFloat = 44

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: max(min(geometry.size.width * 0.008, 5), 2)) {
                    allButton(availableWidth: geometry.size.width)

                    ForEach(ColorGroup.displayOrder, id: \.self) { group in
                        colorSwatch(for: group, availableWidth: geometry.size.width)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
                .frame(minWidth: geometry.size.width, alignment: .trailing)
            }
        }
        .frame(height: swatchHeight + 8)
    }

    private func allButton(availableWidth: CGFloat) -> some View {
        let isSelected = selectedGroup == nil
        return Button {
            selectedGroup = nil
        } label: {
            ParallelogramShape(slant: slant)
                .fill(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.9)) : AnyShapeStyle(Color.secondary.opacity(0.18)))
                .overlay(
                    ParallelogramShape(slant: slant)
                        .stroke(
                            isSelected ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.08),
                            lineWidth: isSelected ? UIStyle.hairline * 1.5 : UIStyle.hairline
                        )
                )
                .overlay(
                    Text("\(totalCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? .white : .secondary)
                )
                .frame(
                    width: max(min(availableWidth * 0.07, swatchMinWidth + 14), 34),
                    height: swatchHeight
                )
                .shadow(color: isSelected ? Color.accentColor.opacity(0.25) : .clear, radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .help("Show all colors")
    }

    @ViewBuilder
    private func colorSwatch(for group: ColorGroup, availableWidth: CGFloat) -> some View {
        let count = colorCounts[group] ?? 0
        let isSelected = selectedGroup == group

        if count > 0 {
            let baseColor = Color(group.representativeColor)
            Button {
                selectedGroup = isSelected ? nil : group
            } label: {
                ParallelogramShape(slant: slant)
                    .fill(isSelected ? AnyShapeStyle(baseColor) : AnyShapeStyle(baseColor.opacity(0.4)))
                    .overlay(
                        ParallelogramShape(slant: slant)
                            .stroke(
                                isSelected ? Color.white.opacity(0.55) : Color.primary.opacity(0.06),
                                lineWidth: isSelected ? UIStyle.selectionLineWidth : UIStyle.hairline
                            )
                    )
                    .overlay(
                        Text("\(count)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(isSelected ? .white : .primary.opacity(0.75))
                    )
                    .frame(
                        width: max(
                            min(
                                availableWidth * 0.06,
                                max(swatchMinWidth, CGFloat(count.description.count * 8 + 22))
                            ),
                            30
                        ),
                        height: swatchHeight
                    )
                    .shadow(color: isSelected ? baseColor.opacity(0.35) : .clear, radius: 4, y: 1)
            }
            .buttonStyle(.plain)
            .help(group.rawValue.capitalized)
        }
    }
}
