# BT - Bluetooth Research & Hacking Tool

A Bluetooth research and hacking tool built with Zig, GTK4, and Cairo.

## Features

- Native GTK4 UI for cross-platform compatibility
- Bluetooth device scanning and enumeration
- Low-level Bluetooth protocol analysis
- Custom Cairo graphics rendering

## Prerequisites

### System Dependencies

- Zig 0.13.0 or later
- GTK4 development libraries
- Cairo development libraries
- BlueZ (Bluetooth stack for Linux)

#### Ubuntu/Debian

```bash
sudo apt update
sudo apt install zig
sudo apt install libgtk-4-dev
sudo apt install libcairo2-dev
sudo apt install libbluetooth-dev
```

#### Fedora

```bash
sudo dnf install zig
sudo dnf install gtk4-devel
sudo dnf install cairo-devel
sudo dnf install bluez-libs-devel
```

#### Arch Linux

```bash
sudo pacman -S zig
sudo pacman -S gtk4
sudo pacman -S cairo
sudo pacman -S bluez-libs
```

### VSCode Setup

1. Install the recommended extension: `ziglang.vscode-zig`
2. Install Zig Language Server (ZLS):
   ```bash
   # Using your package manager or from source
   # Arch: sudo pacman -S zls
   # Or build from source: https://github.com/zigtools/zls
   ```

## Building

```bash
# Build the project
zig build

# Build and run
zig build run

# Run tests
zig build test
```

## Project Structure

```
bt/
├── src/
│   └── main.zig           # Main application entry point
├── include/               # C header files (if needed)
├── .vscode/              # VSCode configuration
│   ├── settings.json     # Editor settings
│   ├── tasks.json        # Build tasks
│   ├── launch.json       # Debug configuration
│   └── extensions.json   # Recommended extensions
├── build.zig             # Build configuration
├── build.zig.zon         # Package manifest
├── .gitignore
└── README.md
```

## Development

### Running with Permissions

Bluetooth operations typically require elevated privileges:

```bash
sudo zig build run
```

### VSCode Tasks

- `Ctrl+Shift+B` - Build the project
- `F5` - Build and run with debugger
- Use the Command Palette to run tests

## Security Notice

This tool is intended for authorized security testing, research, and educational purposes only. Ensure you have proper authorization before scanning or interacting with Bluetooth devices.

## License

TBD
