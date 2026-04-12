import SwiftUI
import ImagePicker
import AppKit

@main
struct ImagePickerApp: App {
    @StateObject private var settingsManager = SettingsManager()
    
    init() {
        registerFonts()
        configureWindow()
    }

    var body: some Scene {
        WindowGroup("Wallpaper Switcher", id: "main") {
            WallpaperSwitcherView()
                .environmentObject(settingsManager)
                .background(.ultraThinMaterial)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1000, height: 700)

        WindowGroup("Settings", id: "settings") {
            SettingsView(settingsManager: settingsManager)
                .frame(minWidth: 600, minHeight: 500)
                .background(.ultraThinMaterial)
        }
        .windowResizability(.contentSize)
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
