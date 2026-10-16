import Testing
@testable import RicCleanMyMac

@Suite("FileNode protection")
struct FileNodeTests {
    @Test("A file inside a read-only folder becomes read-only")
    func fileInheritsReadOnly() {
        let file = FileNode.file(name: "com.example.plist", size: 10)
        let folder = FileNode.directory(name: "Preferences", children: [file], status: .readOnly)

        #expect(file.status == .readOnly)
        #expect(!file.isDeletableByPolicy)
        withExtendedLifetime(folder) {}
    }

    @Test("A folder with a protected descendant is flagged, up to the root")
    func protectedDescendantFlagsAncestors() {
        let preferences = FileNode.directory(name: "Preferences", children: [], status: .readOnly)
        let library = FileNode.directory(name: "Library", children: [preferences])
        let documents = FileNode.directory(name: "Documents", children: [FileNode.file(name: "a.txt", size: 5)])
        let home = FileNode.directory(name: "/Users/test", children: [library, documents])

        #expect(home.containsProtectedItems)
        #expect(library.containsProtectedItems)
        #expect(!documents.containsProtectedItems)
        #expect(documents.isDeletableByPolicy)
    }

    @Test("Removing the protected child clears the flag and the size")
    func removingProtectedChildClearsFlag() {
        let protected = FileNode.file(name: "locked", size: 100, status: .readOnly)
        let normal = FileNode.file(name: "free", size: 50)
        let folder = FileNode.directory(name: "folder", children: [protected, normal])
        let root = FileNode.directory(name: "/", children: [folder])

        folder.removeChild(protected)

        #expect(!folder.containsProtectedItems)
        #expect(!root.containsProtectedItems)
        #expect(folder.size == 50)
        #expect(root.size == 50)
    }

    @Test("The path is rebuilt from the root name")
    func pathFromParents() {
        let file = FileNode.file(name: "f", size: 1)
        let folder = FileNode.directory(name: "a", children: [file])
        let root = FileNode.directory(name: "/Users/test", children: [folder])

        #expect(file.path == "/Users/test/a/f")
        withExtendedLifetime(root) {}
    }
}
