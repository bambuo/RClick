import AppKit
import Foundation
import OSLog
import UserNotifications

@MainActor
final class CommandRunnerService {
    private let appState: AppState
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "RClick", category: "CommandRunner")
    private var lastConfirmedAt: Date?
    private let confirmInterval: TimeInterval

    init(appState: AppState, confirmInterval: TimeInterval = 15 * 60) {
        self.appState = appState
        self.confirmInterval = confirmInterval
        requestNotificationPermission()
    }

    func runCommand(rid: String, target: [String]) {
        guard let command = appState.quickCommands.first(where: { $0.id == rid && $0.enabled }) else {
            logger.warning("Quick command not found or disabled: \(rid)")
            return
        }

        guard !target.isEmpty else {
            logger.warning("No targets for command: \(command.name)")
            return
        }

        let resolved = command.resolvedCommand(forPaths: target)
        logger.info("Resolved command: \(resolved)")

        let needsConfirm = shouldConfirm(for: command)

        if needsConfirm {
            showConfirmation(command: command, resolved: resolved) { [weak self] confirmed in
                if confirmed {
                    self?.lastConfirmedAt = Date()
                    self?.execute(resolved: resolved, commandName: command.name)
                }
            }
        } else {
            execute(resolved: resolved, commandName: command.name)
        }
    }

    private func shouldConfirm(for command: QuickCommand) -> Bool {
        guard let lastConfirm = lastConfirmedAt else {
            return true
        }
        return Date().timeIntervalSince(lastConfirm) > confirmInterval
    }

    private func showConfirmation(command: QuickCommand, resolved: String, completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Run Quick Command?")
        alert.informativeText = "\(command.name)\n\n\(resolved)"
        alert.alertStyle = command.dangerous ? .warning : .informational
        alert.addButton(withTitle: String(localized: "Run"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.suppressionButton?.title = String(localized: "Don't ask again for 15 minutes")
        alert.showsSuppressionButton = true

        let response = alert.runModal()
        if let suppressionButton = alert.suppressionButton, suppressionButton.state == .on {
            lastConfirmedAt = Date()
        }
        completion(response == .alertFirstButtonReturn)
    }

    private func execute(resolved: String, commandName: String) {
        logger.info("Executing: \(resolved)")

        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", resolved]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
            task.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            let exitCode = task.terminationStatus

            if exitCode == 0 {
                logger.info("[\(commandName)] succeeded\n\(output)")
            } else {
                logger.error("[\(commandName)] failed (exit \(exitCode))\nstderr: \(errorOutput)\nstdout: \(output)")
            }

            showNotification(commandName: commandName, success: exitCode == 0, message: errorOutput.isEmpty ? output : errorOutput)
        } catch {
            logger.error("[\(commandName)] launch error: \(error.localizedDescription)")
            showNotification(commandName: commandName, success: false, message: error.localizedDescription)
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [logger] granted, error in
            if let error {
                logger.warning("Notification permission denied: \(error.localizedDescription)")
            }
        }
    }

    private func showNotification(commandName: String, success: Bool, message: String) {
        let content = UNMutableNotificationContent()
        content.title = success ? "✅ \(commandName)" : "❌ \(commandName)"
        content.body = message.isEmpty
            ? (success ? String(localized: "Command completed successfully") : String(localized: "Command failed"))
            : String(message.prefix(200))
        content.sound = success ? .default : .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { [logger] error in
            if let error {
                logger.warning("Failed to deliver notification: \(error.localizedDescription)")
            }
        }
    }
}
