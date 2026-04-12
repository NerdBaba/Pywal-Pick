# Pywal Pick

Pywal Pick is a macOS application that lets you browse your wallpaper collection and apply them using `pywal` to generate color schemes for your system.

## Features

- **Wallpaper Browser**: Grid and Carousel views of your images with support for search and sorting (Name, Date, Size).
- **Advanced Color Filtering**: Filter your collection by color using k-means clustering.
- **Full Pywal Backend Support**: Seamlessly switch between all `wal` backends (e.g., colorthief, haishoku, schemer2 etc).
- **System Integration**: 
  - Automatically updates macOS system accent and highlight colors from the generated palette.
  - Optional Firefox theme synchronization via `pywalfox`.
  - Support for executing custom shell scripts after `wal` execution for deep system customization.
- **Keyboard Navigation**: Full arrow-key navigation and Enter to select.
- **Fast Performance**: Optimized thumbnail and image caching for smooth scrolling.
- **Customizable**: Configure your wallpaper folder, `wal` binary path, and grid layout in settings.

## Requirements

- macOS 14+
- `pywal` installed on your system

## Installation

1. Clone the repository.
2. Build the app bundle:
   ```bash
   ./build_app.sh
   ```
3. Run `WallpaperSwitcher.app`.

## Configuration

Open the Settings view within the app to configure:
- **Wallpaper Folder**: The directory where your wallpapers are stored.
- **Wal Path**: Path to the `wal` binary (e.g., `/opt/homebrew/bin/wal`).
- **Pywalfox**: Toggle to enable/disable Firefox theme synchronization.
