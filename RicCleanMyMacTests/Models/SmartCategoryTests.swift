import Testing
@testable import RicCleanMyMac

@Suite("Smart categories")
struct SmartCategoryTests {
    private let homePath = "/Users/test"

    @Test("Cache counts only folders the user can delete, largest first")
    func cacheCountsOnlyDeletableFolders() {
        let smallCache = FileNode.directory(name: "Caches", children: [FileNode.file(name: "c1", size: 100)])
        let bigCache = FileNode.directory(name: ".cache", children: [FileNode.file(name: "c2", size: 900)])
        let protectedCache = FileNode.directory(
            name: "Caches",
            children: [FileNode.file(name: "c3", size: 5000)],
            status: .readOnly
        )
        let library = FileNode.directory(name: "Library", children: [smallCache, protectedCache])
        let project = FileNode.directory(name: "project", children: [bigCache])
        let home = FileNode.directory(name: homePath, children: [library, project])

        let cache = home.extractSmartCategories(homeDirectory: homePath).first { $0.id == "cache" }

        #expect(cache?.totalSize == 1000)
        #expect(cache?.nodes.first === bigCache)
    }

    @Test("Downloads matches only the Downloads folder of the home")
    func downloadsMatchesOnlyHomeDownloads() {
        let homeDownloads = FileNode.directory(name: "Downloads", children: [FileNode.file(name: "d", size: 300)])
        let otherDownloads = FileNode.directory(name: "Downloads", children: [FileNode.file(name: "x", size: 700)])
        let project = FileNode.directory(name: "project", children: [otherDownloads])
        let home = FileNode.directory(name: homePath, children: [homeDownloads, project])

        let downloads = home.extractSmartCategories(homeDirectory: homePath).first { $0.id == "downloads" }

        #expect(downloads?.totalSize == 300)
        #expect(downloads?.nodes.map(\.name) == ["Downloads"])
        #expect(downloads?.nodes.first === homeDownloads)
    }

    @Test("Categories without content are left out")
    func emptyCategoriesAreLeftOut() {
        let home = FileNode.directory(name: homePath, children: [FileNode.file(name: "notes.txt", size: 10)])

        #expect(home.extractSmartCategories(homeDirectory: homePath).isEmpty)
    }
}
