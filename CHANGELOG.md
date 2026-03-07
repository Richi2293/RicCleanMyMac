# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial project structure with SwiftUI interface
- Dashboard view with system overview
- File scanning for temporary files, cache, and system logs
- Cleanup service with user confirmation dialogs
- Disk space analysis and visualization
- Space usage breakdown by category
- Safe directory whitelist for path validation
- Sidebar navigation with modern macOS design
- English language support

### Security
- Mandatory confirmation dialog before any file deletion
- Strict path validation against allowed directories whitelist
- No background processes or daemons
- Complete app shutdown on termination
