import SwiftUI
import PywalPick
import AppKit

@main
struct PywalPickApp: App {
    @StateObject private var settingsManager = SettingsManager()
    
    init() {
        registerFonts()
        configureWindow()
    }

    var body: some Scene {
        WindowGroup("Pywal Pick", id: "main") {
            WallpaperSwitcherView()
                .environmentObject(settingsManager)
                .background(.regularMaterial)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1000, height: 700)

        WindowGroup("Settings", id: "settings") {
            SettingsView(settingsManager: settingsManager)
                .frame(minWidth: 720, minHeight: 520)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 780, height: 560)
    }
    
    private func registerFonts() {
        if let fontURL = Bundle.main.url(forResource: "NunitoSans-Variable", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        }
    }
    
    private func configureWindow() {
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                window.titlebarAppearsTransparent = true
                window.isOpaque = false
                window.backgroundColor = .clear
                window.styleMask.insert(.fullSizeContentView)
            }
        }
    }
}
