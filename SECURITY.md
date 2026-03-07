# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| dev     | Yes       |

## Reporting a Vulnerability

If you discover a security vulnerability in RicCleanMyMac, please report it responsibly.

### How to Report

1. **Do NOT open a public issue** for security vulnerabilities
2. Send an email or contact the maintainer privately via [GitHub](https://github.com/Richi2293)
3. Include a detailed description of the vulnerability
4. Provide steps to reproduce the issue if possible

### What to Expect

- Acknowledgment within 48 hours
- An assessment of the vulnerability within 7 days
- A fix or mitigation plan as soon as possible

### Scope

The following are in scope for security reports:

- File deletion outside the allowed directory whitelist
- Bypassing user confirmation dialogs
- Unauthorized access to system files
- Data exfiltration or privacy violations
- Any operation that could damage the user's system

### Out of Scope

- Issues that require physical access to the machine
- Social engineering attacks
- Issues in third-party dependencies (report those upstream)

## Security Design Principles

RicCleanMyMac is built with security as a core principle:

- **No automatic deletion**: Every file operation requires explicit user confirmation
- **Directory whitelist**: Only predefined safe directories can be cleaned
- **Path validation**: Strict validation prevents path traversal attacks
- **No background processes**: The app runs only when actively used
- **No network access**: No data is sent to external servers
- **Open source**: All code is publicly auditable

Thank you for helping keep RicCleanMyMac safe!
