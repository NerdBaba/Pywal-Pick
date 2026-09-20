import AppKit
import SwiftUI

/// Compact theme picker shown when the active wallpaper is selected again.
struct WallpaperThemeChoicePopover: View {
    let selectedChoice: WallpaperThemeChoice
    let onSelect: (WallpaperThemeChoice) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var focusedChoice: WallpaperThemeChoice?

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: UIStyle.spaceSM),
        count: 3
    )

    private var choices: [WallpaperThemeChoice] {
        WallpaperThemeChoice.all
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIStyle.spaceMD) {
            HStack(alignment: .firstTextBaseline, spacing: UIStyle.spaceSM) {
                Image(systemName: "paintpalette.fill")
                    .foregroundStyle(.tint)
                Text("Choose color theme")
                    .font(.headline.weight(.semibold))
                Spacer(minLength: 0)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close theme picker")
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: UIStyle.spaceLG) {
                    ForEach(WallpaperThemeChoice.Section.allCases) { section in
                        let sectionChoices = choices.filter { $0.section == section }

                        VStack(alignment: .leading, spacing: UIStyle.spaceSM) {
                            Text(section.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .tracking(0.6)

                            LazyVGrid(columns: columns, spacing: UIStyle.spaceSM) {
                                ForEach(sectionChoices) { choice in
                                    choiceButton(choice)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.visible)
        }
        .padding(UIStyle.spaceLG)
        .frame(width: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: UIStyle.radiusLG, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: UIStyle.radiusLG, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: UIStyle.hairline)
        )
        .uiElevatedShadow()
        .onAppear {
            focusedChoice = selectedChoice
        }
        .overlay(alignment: .topLeading) {
            // NSPopover does not reliably deliver SwiftUI focus events to a
            // focusable view. Keep a native first responder in its window so
            // arrow keys are captured even when SwiftUI focus is unavailable.
            WallpaperThemeChoiceKeyCapture { action in
                handleKeyAction(action)
            }
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func choiceButton(_ choice: WallpaperThemeChoice) -> some View {
        let isSelected = choice == selectedChoice
        let isFocused = choice == focusedChoice

        Button {
            focusedChoice = choice
            onSelect(choice)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: choice.iconName)
                        .font(.caption.weight(.bold))
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                    }
                }

                Text(choice.displayName)
                    .font(choice.labelFont)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(choice.gradient)
            .overlay(
                RoundedRectangle(cornerRadius: UIStyle.radiusSM, style: .continuous)
                    .strokeBorder(
                        isFocused || isSelected ? .white.opacity(0.9) : .white.opacity(0.18),
                        lineWidth: isFocused ? 2 : (isSelected ? 1.5 : 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: UIStyle.radiusSM, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: UIStyle.radiusSM, style: .continuous))
        .accessibilityLabel(choice.displayName)
        .accessibilityHint("Apply this color theme")
    }

    private func moveFocus(_ direction: NavigationDirection) {
        var navigator = WallpaperThemeChoiceNavigator(
            choices: choices,
            selectedChoice: focusedChoice ?? selectedChoice
        )
        focusedChoice = navigator.move(direction, columns: columns.count)
    }

    private func activateFocusedChoice() {
        guard let focusedChoice else { return }
        onSelect(focusedChoice)
    }

    private func handleKeyAction(_ action: WallpaperThemeChoiceKeyAction) {
        switch action {
        case .move(let direction):
            moveFocus(direction)
        case .activate:
            activateFocusedChoice()
        case .dismiss:
            dismiss()
        }
    }
}

/// Embeds an AppKit first responder in the SwiftUI popover.
///
/// A SwiftUI `.onKeyPress` modifier depends on the focus system choosing the
/// expected view. An NSPopover can become key before that focus transaction is
/// complete, so this responder claims focus from the popover window itself.
private struct WallpaperThemeChoiceKeyCapture: NSViewRepresentable {
    let onAction: (WallpaperThemeChoiceKeyAction) -> Void

    func makeNSView(context: Context) -> WallpaperThemeChoiceKeyCaptureView {
        let view = WallpaperThemeChoiceKeyCaptureView()
        view.onAction = onAction
        return view
    }

    func updateNSView(_ nsView: WallpaperThemeChoiceKeyCaptureView, context: Context) {
        nsView.onAction = onAction
        nsView.requestFocusIfNeeded()
    }
}

private final class WallpaperThemeChoiceKeyCaptureView: NSView {
    var onAction: ((WallpaperThemeChoiceKeyAction) -> Void)?

    private var keyWindowObserver: KeyWindowObserverToken?
    private var keyMonitor: KeyMonitorToken?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // The responder is keyboard-only; leave all mouse events to the picker.
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeKeyWindowObserver()
        removeKeyMonitor()

        guard let window else { return }
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.requestFocusIfNeeded()
            }
        }
        keyWindowObserver = KeyWindowObserverToken(observer)
        let monitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown,
            handler: { [weak self] event in
                guard let self,
                    let action = self.action(for: event)
                else {
                    return event
                }

                Task { @MainActor [weak self] in
                    self?.onAction?(action)
                }
                return nil
            }
        )
        if let monitor {
            keyMonitor = KeyMonitorToken(monitor)
        }

        requestFocusIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.requestFocusIfNeeded()
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            removeKeyWindowObserver()
            removeKeyMonitor()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func keyDown(with event: NSEvent) {
        guard let action = action(for: event) else {
            super.keyDown(with: event)
            return
        }
        onAction?(action)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let action = action(for: event) else {
            return super.performKeyEquivalent(with: event)
        }
        onAction?(action)
        return true
    }

    func requestFocusIfNeeded() {
        guard let window, window.isKeyWindow else { return }
        if window.firstResponder !== self {
            _ = window.makeFirstResponder(self)
        }
    }

    private func action(for event: NSEvent) -> WallpaperThemeChoiceKeyAction? {
        let reservedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.intersection(reservedModifiers).isEmpty else {
            return nil
        }
        return WallpaperThemeChoiceKeyAction(keyCode: event.keyCode)
    }

    private func removeKeyWindowObserver() {
        if let keyWindowObserver {
            NotificationCenter.default.removeObserver(keyWindowObserver.value)
            self.keyWindowObserver = nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor.value)
            self.keyMonitor = nil
        }
    }

    deinit {
        if let keyWindowObserver {
            NotificationCenter.default.removeObserver(keyWindowObserver.value)
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor.value)
        }
    }
}

private final class KeyWindowObserverToken: @unchecked Sendable {
    let value: NSObjectProtocol

    init(_ value: NSObjectProtocol) {
        self.value = value
    }
}

private final class KeyMonitorToken: @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }
}

private extension WallpaperThemeChoice {
    var labelFont: Font {
        switch fontStyle {
        case .rounded:
            return .system(size: 12, weight: .semibold, design: .rounded)
        case .monospaced:
            return .system(size: 11, weight: .semibold, design: .monospaced)
        case .serif:
            return .system(size: 12, weight: .semibold, design: .serif)
        }
    }

    var iconName: String {
        switch self {
        case .backend(let backend):
            switch backend {
            case .haishoku: return "drop.fill"
            case .fastColorthief: return "bolt.fill"
            case .schemer2: return "square.grid.3x3.fill"
            case .colorz: return "circle.hexagongrid.fill"
            case .modernColorthief: return "sparkles"
            case .wal: return "paintbrush.fill"
            case .okthief: return "wand.and.stars"
            case .colorthief: return "eyedropper.full"
            case .matugen: return "paintpalette.fill"
            }
        case .matugen:
            return "wand.and.stars"
        }
    }

    var gradient: LinearGradient {
        let colors: [Color]

        switch self {
        case .backend(let backend):
            switch backend {
            case .haishoku: colors = [Color(hue: 0.56, saturation: 0.82, brightness: 0.88), Color(hue: 0.72, saturation: 0.72, brightness: 0.62)]
            case .fastColorthief: colors = [Color(hue: 0.08, saturation: 0.9, brightness: 0.98), Color(hue: 0.98, saturation: 0.76, brightness: 0.78)]
            case .schemer2: colors = [Color(hue: 0.47, saturation: 0.68, brightness: 0.76), Color(hue: 0.63, saturation: 0.72, brightness: 0.55)]
            case .colorz: colors = [Color(hue: 0.77, saturation: 0.7, brightness: 0.86), Color(hue: 0.92, saturation: 0.72, brightness: 0.64)]
            case .modernColorthief: colors = [Color(hue: 0.34, saturation: 0.76, brightness: 0.78), Color(hue: 0.52, saturation: 0.82, brightness: 0.52)]
            case .wal: colors = [Color(hue: 0.63, saturation: 0.75, brightness: 0.78), Color(hue: 0.04, saturation: 0.8, brightness: 0.72)]
            case .okthief: colors = [Color(hue: 0.15, saturation: 0.82, brightness: 0.92), Color(hue: 0.54, saturation: 0.75, brightness: 0.62)]
            case .colorthief: colors = [Color(hue: 0.92, saturation: 0.74, brightness: 0.84), Color(hue: 0.31, saturation: 0.72, brightness: 0.62)]
            case .matugen: colors = [Color.accentColor, Color.accentColor.opacity(0.6)]
            }
        case .matugen(let scheme):
            switch scheme {
            case .schemeContent: colors = [Color(hue: 0.56, saturation: 0.65, brightness: 0.82), Color(hue: 0.68, saturation: 0.56, brightness: 0.6)]
            case .schemeExpressive: colors = [Color(hue: 0.89, saturation: 0.78, brightness: 0.9), Color(hue: 0.12, saturation: 0.9, brightness: 0.82)]
            case .schemeFidelity: colors = [Color(hue: 0.05, saturation: 0.8, brightness: 0.9), Color(hue: 0.58, saturation: 0.72, brightness: 0.74)]
            case .schemeFruitSalad: colors = [Color(hue: 0.31, saturation: 0.74, brightness: 0.78), Color(hue: 0.08, saturation: 0.82, brightness: 0.86)]
            case .schemeMonochrome: colors = [Color(white: 0.78), Color(white: 0.28)]
            case .schemeNeutral: colors = [Color(hue: 0.1, saturation: 0.18, brightness: 0.85), Color(hue: 0.58, saturation: 0.18, brightness: 0.48)]
            case .schemeRainbow: colors = [Color(hue: 0.78, saturation: 0.78, brightness: 0.88), Color(hue: 0.34, saturation: 0.8, brightness: 0.7)]
            case .schemeTonalSpot: colors = [Color(hue: 0.61, saturation: 0.6, brightness: 0.84), Color(hue: 0.9, saturation: 0.5, brightness: 0.66)]
            case .schemeVibrant: colors = [Color(hue: 0.98, saturation: 0.9, brightness: 0.92), Color(hue: 0.47, saturation: 0.88, brightness: 0.76)]
            }
        }

        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
