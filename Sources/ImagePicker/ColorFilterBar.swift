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

    private let slant: CGFloat = 8
    private let swatchHeight: CGFloat = 32
    private let swatchMinWidth: CGFloat = 48

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: max(min(geometry.size.width * 0.008, 6), 2)) {
                    allButton(availableWidth: geometry.size.width)

                    ForEach(ColorGroup.displayOrder, id: \.self) { group in
                        colorSwatch(for: group, availableWidth: geometry.size.width)
                    }
                }
                .padding(.vertical, 4)
                .frame(minWidth: geometry.size.width, alignment: .trailing)
            }
        }
        .frame(height: swatchHeight + 8)
    }

    private func allButton(availableWidth: CGFloat) -> some View {
        let isSelected = selectedGroup == nil
        return ParallelogramShape(slant: slant)
            .fill(isSelected ? AnyShapeStyle(.blue.opacity(0.8)) : AnyShapeStyle(Color.secondary.opacity(0.2)))
            .overlay(
                Text("\(totalCount)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : .secondary)
            )
            .frame(width: max(min(availableWidth * 0.07, swatchMinWidth + 16), 36), height: swatchHeight)
            .onTapGesture { selectedGroup = nil }
    }

    @ViewBuilder
    private func colorSwatch(for group: ColorGroup, availableWidth: CGFloat) -> some View {
        let count = colorCounts[group] ?? 0
        let isSelected = selectedGroup == group

        if count > 0 {
            let baseColor = Color(group.representativeColor)
            ParallelogramShape(slant: slant)
                .fill(isSelected ? AnyShapeStyle(baseColor) : AnyShapeStyle(baseColor.opacity(0.35)))
                .overlay(
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? .white : .secondary.opacity(0.8))
                )
                .frame(
                    width: max(min(availableWidth * 0.06, max(swatchMinWidth, CGFloat(count.description.count * 8 + 24))), 32),
                    height: swatchHeight
                )
                .onTapGesture {
                    selectedGroup = isSelected ? nil : group
                }
        }
    }
}
