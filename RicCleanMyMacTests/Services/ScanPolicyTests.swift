import Foundation
import Testing
@testable import RicCleanMyMac

@Suite("ScanPolicy")
struct ScanPolicyTests {
    private let home = URL(fileURLWithPath: "/Users/test")

    private func classify(_ path: String, scanRoot: String? = nil) -> ScanPolicy.Classification {
        ScanPolicy.classify(
            URL(fileURLWithPath: path),
            homeDirectory: home,
            bootVolumeName: "Macintosh HD",
            scanRoot: scanRoot.map { URL(fileURLWithPath: $0) }
        )
    }

    @Test("System zones are skipped", arguments: [
        "/System/Library",
        "/usr/bin",
        "/var/db/x",
        "/private/var/folders/ab",
        "/Network/Servers",
        "/Volumes/External/Photos"
    ])
    func systemZonesAreSkipped(path: String) {
        #expect(classify(path) == .skipped(reason: "System"))
    }

    @Test("Protected zones are scanned but read-only", arguments: [
        "/Applications/Safari.app",
        "/Library/Preferences",
        "/private/etc/hosts",
        "/Users/Shared/file",
        "/Users/test/Library/Preferences"
    ])
    func protectedZonesAreReadOnly(path: String) {
        #expect(classify(path) == .readOnly)
    }

    @Test("User folders and cleanable zones are scanned normally", arguments: [
        "/",
        "/Users",
        "/Users/test/Documents",
        "/Users/test/Library/Caches/com.example",
        "/tmp/x",
        "/usr/local/bin"
    ])
    func userZonesAreScanned(path: String) {
        #expect(classify(path) == .scanned)
    }

    @Test("Another user's home is skipped")
    func otherUserIsSkipped() {
        #expect(classify("/Users/someone") == .skipped(reason: "Other user"))
    }

    @Test("An external volume is scanned when it is the scan root")
    func externalVolumeAsRootIsScanned() {
        #expect(classify("/Volumes/External/Photos", scanRoot: "/Volumes/External") == .scanned)
    }

    @Test("Library cache folders stay in place, their contents do not")
    func keptFolders() {
        let caches = home.appendingPathComponent("Library/Caches")

        #expect(ScanPolicy.isKeptFolder(caches, homeDirectory: home))
        #expect(!ScanPolicy.isKeptFolder(caches.appendingPathComponent("com.example"), homeDirectory: home))
    }
}
