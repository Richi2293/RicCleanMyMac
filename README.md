# RicCleanMyMac

An open source macOS application to optimize and clean your Mac system, similar to "Clean My Mac" but completely free and open source.

## ⚠️ Warning

**This project is currently under active development and is NOT considered safe or fully tested.**

- Use at your own risk
- Always backup your important data before using
- Test carefully in a safe environment
- Report any issues you encounter
- The application may contain bugs or unexpected behavior

## Features

- **Safe Cleanup**: Scan and clean temporary files, cache, and system logs
- **Full Control**: No automatic deletion - every operation requires explicit confirmation
- **Lightweight Architecture**: No background processes, complete shutdown when the app is terminated
- **Modern Interface**: Modern UI based on SwiftUI with sidebar navigation

## Requirements

- macOS 12.0 (Monterey) or later
- Xcode 14.0 or later (to build from source)

## Installation

### From Source

1. Clone the repository:
```bash
git clone https://github.com/tuousername/RicCleanMyMac.git
cd RicCleanMyMac
```

2. Open the project in Xcode:
```bash
open RicCleanMyMac.xcodeproj
```

3. Select the "RicCleanMyMac" scheme and press ⌘R to build and run

## Usage

1. Launch the application
2. Click "Scan" in the dashboard to find files to clean
3. Select the items you want to delete
4. Click "Cleanup" and confirm the operation
5. The app will show the freed space

## Security

- The app **DOES NOT delete** any file without your explicit confirmation
- Every cleanup operation requires a confirmation dialog
- Strict path validation to prevent accidental deletions
- Safe directory whitelist

## Development

### Project Structure

```
RicCleanMyMac/
├── App/              # Entry point and AppDelegate
├── Views/            # SwiftUI interface
├── Services/         # Business logic
├── Models/           # Data models
└── Utilities/        # Helper functions
```

### Build for Release

1. Select the "RicCleanMyMac" scheme
2. Product → Scheme → Edit Scheme → Build Configuration: Release
3. Product → Archive
4. Export the app from the Organizer

## Contributing

Contributions are welcome! For more information, see [CONTRIBUTING.md](CONTRIBUTING.md) (to be created).

## License

[To be defined: MIT, Apache 2.0, or GPL]

## Notes

- **The app is under active development and is NOT production-ready**
- **This software has NOT been thoroughly tested and may contain bugs**
- **Use with caution and always backup your data before use**
- All features are subject to change
- Security and stability are priorities, but cannot be guaranteed at this stage
