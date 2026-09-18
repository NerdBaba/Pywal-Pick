import SwiftUI

enum WallhavenDownloadIndicatorModel {
    static func normalizedProgress(_ progress: Double) -> Double {
        min(max(progress, 0), 1)
    }

    static func percentage(for progress: Double) -> Int {
        Int(normalizedProgress(progress) * 100)
    }
}

struct WallhavenDownloadIndicator: View {
    let progress: Double
    let size: CGFloat
    let lineWidth: CGFloat
    let tint: Color

    @State private var isSpinning = false

    init(
        progress: Double,
        size: CGFloat,
        lineWidth: CGFloat = 3,
        tint: Color = .accentColor
    ) {
        self.progress = progress
        self.size = size
        self.lineWidth = lineWidth
        self.tint = tint
    }

    private var normalizedProgress: Double {
        WallhavenDownloadIndicatorModel.normalizedProgress(progress)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.22), lineWidth: lineWidth)

            if normalizedProgress == 0 {
                Circle()
                    .trim(from: 0.08, to: 0.72)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(isSpinning ? 360 : 0))
                    .animation(
                        .linear(duration: 0.9).repeatForever(autoreverses: false),
                        value: isSpinning
                    )
            } else {
                Circle()
                    .trim(from: 0, to: normalizedProgress)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.18), value: normalizedProgress)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Downloading")
        .accessibilityValue("\(WallhavenDownloadIndicatorModel.percentage(for: progress)) percent")
        .onAppear {
            isSpinning = true
        }
    }
}
