import AppKit
import Foundation
import OSLog

@MainActor
final class AppLaunchService {
    private let appState: AppState
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "RClick", category: "AppLaunch")

    init(appState: AppState) {
        self.appState = appState
    }

    func openApp(rid: String, target: [String]) {
        logger.info("openApp called, rid=\(rid), targets=\(target)")
        guard let app = appState.getAppItem(rid: rid) else {
            logger.warning("when openapp,but not have app \(rid), available apps: \(self.appState.apps.map { $0.id })")
            return
        }

        logger.info("opening with app: \(app.name), url: \(app.url.path)")
        let appUrl = app.url
        let config = NSWorkspace.OpenConfiguration()
        config.promptsUserIfNeeded = true

        for dirPath in target {
            let decodedPath = dirPath.removingPercentEncoding ?? dirPath
            let dir = URL(fileURLWithPath: decodedPath, isDirectory: false)
            logger.info("opening path: \(decodedPath) with app: \(appUrl.path())")

            config.arguments = app.arguments
            config.environment = app.environment

            if appUrl.path.hasSuffix("WezTerm.app") {
                launchViaWezTerm(appUrl)
            } else {
                let dirPath = dir.path
                NSWorkspace.shared.open([dir], withApplicationAt: appUrl, configuration: config) { [logger] runningApp, error in
                    if let error {
                        logger.error("Error opening application: \(error.localizedDescription)")
                    } else if let runningApp {
                        logger.info("Successfully opened application: \(runningApp.localizedName ?? "Unknown") for path: \(dirPath)")
                    } else {
                        logger.warning("NSWorkspace.open completed without runningApp or error for \(dirPath)")
                    }
                }
            }
        }
    }

    private func launchViaWezTerm(_ appUrl: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/Users/lixu/play/rpm/target/debug/rpm")
        process.arguments = ["--name", "arg2"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                logger.info("Process output: \(output)")
            }
        } catch {
            logger.error("Process error: \(error)")
        }
    }
}
