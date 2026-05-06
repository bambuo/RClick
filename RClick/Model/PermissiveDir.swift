import Foundation
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "RClick", category: "permissive_dir")

struct PermissiveDir: RCBase {
    var id: String
    var url: URL
    var bookmark: Data

    init?(id: String = UUID().uuidString, permUrl url: URL) {
        self.id = id
        self.url = url
        guard url.startAccessingSecurityScopedResource() else {
            logger.error("Fail to start access security scoped resource on \(url.path)")
            return nil
        }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            bookmark = try url.bookmarkData(options: .withSecurityScope)
        } catch {
            logger.error("Bookmark creation failed: \(error.localizedDescription)")
            return nil
        }
    }
}

extension PermissiveDir {
    static var home: PermissiveDir? {
        guard let pw = getpwuid(getuid()),
              let home = pw.pointee.pw_dir
        else {
            return nil
        }
        let path = FileManager.default.string(withFileSystemRepresentation: home, length: strlen(home))
        let url = URL(fileURLWithPath: path)
        return PermissiveDir(permUrl: url)
    }

    static var application: PermissiveDir? {
        PermissiveDir(permUrl: URL(fileURLWithPath: "/Applications"))
    }

    static var volumes: [PermissiveDir] {
        let volumes = (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [], options: .skipHiddenVolumes) ?? []).dropFirst()
        return volumes.compactMap { PermissiveDir(permUrl: $0) }
    }

    static var defaultFolders: [PermissiveDir] {
        [.home].compactMap { $0 } + volumes
    }
}
