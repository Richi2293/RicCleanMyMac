# Contributing to RicCleanMyMac

Thank you for your interest in contributing to RicCleanMyMac! This document provides guidelines to help you get started.

## How to Contribute

### Reporting Bugs

1. Check if the bug has already been reported in [Issues](https://github.com/Richi2293/RicCleanMyMac/issues)
2. If not, open a new issue with:
   - A clear and descriptive title
   - Steps to reproduce the problem
   - Expected behavior vs actual behavior
   - macOS version and Xcode version
   - Screenshots if applicable

### Suggesting Features

1. Open a new issue with the label `enhancement`
2. Describe the feature and why it would be useful
3. Include mockups or examples if possible

### Submitting Pull Requests

1. Fork the repository
2. Create a new branch from `dev`:
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. Make your changes
4. Test your changes thoroughly
5. Commit with clear, descriptive messages in English
6. Push to your fork and open a Pull Request against the `dev` branch

## Development Setup

### Requirements

- macOS 12.0 (Monterey) or later
- Xcode 14.0 or later
- Swift 5.7 or later

### Getting Started

```bash
git clone https://github.com/Richi2293/RicCleanMyMac.git
cd RicCleanMyMac
open RicCleanMyMac.xcodeproj
```

See [docs/BUILD_INSTRUCTIONS.md](docs/BUILD_INSTRUCTIONS.md) for detailed build instructions.

## Code Guidelines

### General

- Write clear, readable, and easy-to-understand code
- Follow Swift and SwiftUI best practices
- Prefer simple and explicit solutions over clever or over-engineered ones
- Code (variable names, functions, classes, comments) must be in **English**

### Swift Specific

- Never use `any` type - use explicit types, `unknown`, or generics
- Use `async/await` for asynchronous operations
- Follow Swift naming conventions (camelCase for variables/functions, PascalCase for types)

### Security

- Never delete files without explicit user confirmation
- Always validate paths against the directory whitelist
- No background processes or daemons

### Project Structure

```
RicCleanMyMac/
├── App/              # Entry point and AppDelegate
├── Views/            # SwiftUI interface
├── Services/         # Business logic
├── Models/           # Data models
└── Utilities/        # Helper functions and extensions
```

## Pull Request Guidelines

- Keep PRs focused on a single change
- Include a clear description of what the PR does and why
- Reference any related issues
- Make sure the project builds without errors
- Test on macOS 12.0+ if possible

## Code of Conduct

- Be respectful and constructive in all interactions
- Welcome newcomers and help them get started
- Focus on the code, not the person

## Questions?

If you have questions, feel free to open an issue with the label `question`.

Thank you for contributing!
