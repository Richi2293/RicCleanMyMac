# Testing and Deployment - RicCleanMyMac

## Testing During Development

### 1. Testing in Xcode

#### Run and Debug
- **Run (⌘R)**: Launches the app in debug mode
- **Test (⌘U)**: Runs all unit tests
- **Debug Console**: Displays logs and errors during execution

#### Breakpoints and Debugging
- Set breakpoints to debug execution flow
- Use `print()` or `os_log` for logging during development
- Verify that filesystem operations work correctly

#### Manual Testing
1. **Scan Test**:
   - Launch the app
   - Click "Scan" in the dashboard
   - Verify that temporary files, cache, and logs are found
   - Verify that sizes are calculated correctly

2. **Cleanup Test**:
   - After scanning, select some items
   - Click "Cleanup"
   - Verify that the confirmation dialog appears
   - Verify that files are only deleted after confirmation
   - Verify that the app updates correctly after cleanup

3. **Security Test**:
   - Verify that files outside allowed directories are not deleted
   - Verify that the whitelist works correctly
   - Attempt to delete critical system files (should not be possible)

4. **Shutdown Test**:
   - Start a scan
   - Close the app during scanning
   - Verify that all processes terminate completely
   - Verify with Activity Monitor that there are no leftover processes

### 2. Unit Testing

#### Test Structure
```
RicCleanMyMacTests/
├── FileScannerTests.swift
├── CleanupServiceTests.swift
├── DiskAnalyzerTests.swift
└── FileManagerExtensionsTests.swift
```

#### Tests to Implement

**FileScannerTests**:
- Test scanning existing directory
- Test scanning non-existent directory
- Test correct size calculation
- Test hidden file enumeration

**CleanupServiceTests**:
- Test path validation (whitelist)
- Test rejection of deletion outside whitelist
- Test correct deletion after confirmation
- Test error handling during deletion

**DiskAnalyzerTests**:
- Test available disk space calculation
- Test size formatting

### 3. Testing with Realistic Data

#### Test Environment Preparation
1. Create test directories with simulated temporary files
2. Use files of known sizes to verify calculations
3. Test with different cache and log sizes

#### Performance Testing
- Test scanning large directories (thousands of files)
- Verify that the UI remains responsive during long scans
- Test memory during intensive operations

### 4. Testing on Different macOS Versions

#### Supported Versions
- macOS 12.0 (Monterey)
- macOS 13.0 (Ventura)
- macOS 14.0 (Sonoma)
- macOS 15.0 (Sequoia) - if available

#### Cross-Version Testing
- Verify SwiftUI compatibility on all versions
- Test filesystem permissions on different versions
- Verify UI behavior on different resolutions

## Deployment and Distribution

### 1. Build for Release

#### Xcode Configuration
1. **Select Release Scheme**:
   - Product → Scheme → Edit Scheme
   - Set Build Configuration to "Release"

2. **Optimizations**:
   - Enable compiler optimizations
   - Remove debug symbols if necessary
   - Verify that there are no `print()` debug statements

3. **Archive**:
   - Product → Archive
   - Wait for build completion
   - Xcode Organizer will open automatically

### 2. Code Signing and Notarization

#### Code Signing (Optional but Recommended)
To distribute the app outside the App Store, code signing is required:

1. **Apple Developer Account**:
   - Developer Program subscription ($99/year) for distribution outside App Store
   - Or Developer ID for direct distribution

2. **Signing Configuration**:
   - Xcode → Target → Signing & Capabilities
   - Select developer team
   - Xcode will automatically handle provisioning

3. **Notarization**:
   - Required by macOS Catalina+ for apps not from App Store
   - Automatic process via Xcode Organizer
   - Security verification by Apple (24-48 hours)

#### Alternatives for Open Source
- **Optional Notarization**: Users can bypass with `xattr -cr` if necessary
- **Source Code Distribution**: Users can compile directly from Xcode
- **GitHub Releases**: Distribute `.zip` with compilation instructions

### 3. Distribution Methods

#### Option 1: GitHub Releases (Recommended for Open Source)

**Advantages**:
- Free
- Integrated with Git repository
- Easy for technical users
- No additional cost

**Process**:
1. Create release on GitHub:
   ```
   git tag v1.0.0
   git push origin v1.0.0
   ```
2. GitHub → Releases → Draft new release
3. Upload compiled app `.zip`
4. Add changelog and instructions

**Distribution Format**:
```
RicCleanMyMac-v1.0.0.zip
├── RicCleanMyMac.app
└── README.txt (installation instructions)
```

**User Instructions**:
- Download `.zip`
- Extract `.app`
- Move to `/Applications`
- First run: right-click → Open (to bypass Gatekeeper)

#### Option 2: Homebrew Cask (For Technical Users)

**Advantages**:
- Easy installation for Homebrew users
- Automatic updates
- Standard for macOS open source apps

**Process**:
1. Create Homebrew Cask formula
2. Add to `homebrew-cask` repository
3. Keep updated with new versions

**Example Formula**:
```ruby
cask 'riccleanmymac' do
  version '1.0.0'
  sha256 '...'
  
  url "https://github.com/tuousername/RicCleanMyMac/releases/download/v#{version}/RicCleanMyMac-#{version}.zip"
  name 'RicCleanMyMac'
  homepage 'https://github.com/tuousername/RicCleanMyMac'
  
  app 'RicCleanMyMac.app'
end
```

#### Option 3: Mac App Store (Future)

**Requirements**:
- Apple Developer Account ($99/year)
- Apple review process
- App Store guidelines compliance
- Sandboxing (might limit filesystem access)

**Advantages**:
- Official distribution
- Automatic updates
- Greater user trust

**Disadvantages**:
- Long review process
- Sandbox restrictions
- 30% commission on sales (not applicable if free)

### 4. Creating DMG (Disk Image)

#### For Professional Distribution

**Tools**:
- `create-dmg` (CLI tool)
- `DropDMG` (GUI app)
- Custom script

**DMG Structure**:
```
RicCleanMyMac.dmg
└── RicCleanMyMac.app
    └── Applications (alias)
```

**Process with create-dmg**:
```bash
# Install create-dmg
brew install create-dmg

# Create DMG
create-dmg \
  --volname "RicCleanMyMac" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "RicCleanMyMac.app" 200 190 \
  --hide-extension "RicCleanMyMac.app" \
  --app-drop-link 600 185 \
  "RicCleanMyMac-v1.0.0.dmg" \
  "build/"
```

### 5. CI/CD with GitHub Actions

#### Automate Build and Release

**GitHub Actions Workflow**:
```yaml
name: Build and Release

on:
  release:
    types: [created]

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build
        run: |
          xcodebuild -scheme RicCleanMyMac \
            -configuration Release \
            -archivePath build/RicCleanMyMac.xcarchive \
            archive
      - name: Export
        run: |
          xcodebuild -exportArchive \
            -archivePath build/RicCleanMyMac.xcarchive \
            -exportPath build/export \
            -exportOptionsPlist ExportOptions.plist
      - name: Create DMG
        run: |
          # Script to create DMG
      - name: Upload Release
        uses: softprops/action-gh-release@v1
        with:
          files: build/RicCleanMyMac.dmg
```

### 6. Versioning

#### Semantic Versioning
- **Major** (1.0.0): Incompatible changes
- **Minor** (0.1.0): Compatible new features
- **Patch** (0.0.1): Bug fixes

#### Info.plist
```xml
<key>CFBundleShortVersionString</key>
<string>1.0.0</string>
<key>CFBundleVersion</key>
<string>1</string>
```

## Pre-Release Checklist

### Functionality
- [ ] All tests pass
- [ ] No known critical bugs
- [ ] UI tested on different resolutions
- [ ] Acceptable performance

### Security
- [ ] Path validation implemented
- [ ] Directory whitelist working
- [ ] Deletion confirmation always required
- [ ] No files deleted without confirmation

### Architecture
- [ ] No background processes
- [ ] Complete shutdown verified
- [ ] No daemon or agent
- [ ] Memory managed correctly

### Documentation
- [ ] README.md updated
- [ ] Changelog created
- [ ] Clear installation instructions
- [ ] Screenshots or demo video (optional)

### Build
- [ ] Release build working
- [ ] App tested on target macOS
- [ ] Reasonable app size
- [ ] App icon created

## Tips for Open Source Distribution

### 1. Complete README
- Clear project description
- App screenshots
- Detailed installation instructions
- System requirements
- How to contribute

### 2. LICENSE File
- Choose appropriate license (MIT, Apache 2.0, GPL)
- Add LICENSE file in root

### 3. Contributing Guidelines
- Create CONTRIBUTING.md
- Explain how to contribute
- Guidelines for pull requests

### 4. Issue Templates
- Template for bug reports
- Template for feature requests
- Template for questions

### 5. Security Policy
- Create SECURITY.md
- Explain how to report vulnerabilities
- Responsible disclosure process

## Final Recommendation

For an open source project like RicCleanMyMac, I suggest:

1. **Initial Phase (MVP)**:
   - Distribution via GitHub Releases
   - Manual build for first versions
   - Focus on functionality and stability

2. **Growth Phase**:
   - Automate build with GitHub Actions
   - Add Homebrew Cask for easy installation
   - Create DMG for professional distribution

3. **Maturity Phase**:
   - Consider Mac App Store if necessary
   - Implement auto-update mechanism
   - Expand distribution channels

**Recommended Approach**: Start with simple GitHub Releases, then gradually expand based on community needs.
