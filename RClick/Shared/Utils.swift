import Foundation
import OSLog

public class PathSecurityChecker {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "RClick", category: "PathSecurityChecker")

    public static func isProtectedFolder(_ path: String) -> Bool {
        return Constants.protectedDirs.contains { protectedPath in
            path == protectedPath
        }
    }

    public static func getRealHomeDir() -> String {
        let fullPath = NSHomeDirectory()
        let components = fullPath.components(separatedBy: "/")
        let limitedComponents = Array(components.prefix(3))
        return limitedComponents.joined(separator: "/")
    }
}
