//
//  RClickApp.swift
//  RClick
//
//  Created by 李旭 on 2024/4/4.
//
import AppKit
import Foundation
import SwiftUI
import SwiftData
import CoreServices

import OSLog

@main
struct RClickApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(StorageKey.showMenuBarExtra, store: .group) private var showMenuBarExtra = true

    @Environment(\.openWindow) var openWindow

    @AppLog(category: "main")
    private var logger
    let messenger = Messenger.shared

    @State var appState = AppState.shared

    @State private var updateManager = UpdateManager(
        owner: "wflixu",
        repo: "RClick",
        currentVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    )

    var body: some Scene {
        SettingsWindow(appState: appState, onAppear: {})
            .defaultAppStorage(.group)
            .environment(updateManager)
            .modelContainer(SharedDataManager.sharedModelContainer)

        // showMenuBarExtra 为 true 时显示菜单条
        MenuBarExtra(isInserted: $showMenuBarExtra) {
            MenuBarView()
        } label: {
            Image("MenuBar")
                .renderingMode(.template)
                .accessibilityLabel("RClick")
        }
        .defaultAppStorage(.group)
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    @AppLog(category: "AppDelegate")
    private var logger

    var appState: AppState = .shared
    var pluginRunning: Bool = false
    var heartBeatCount = 0

    let messenger = Messenger.shared
    var showMenuBarExtra = UserDefaults.group.bool(forKey: StorageKey.showMenuBarExtra)
    var showInDock = UserDefaults.group.bool(forKey: StorageKey.showInDock)
    var settingsWindow: NSWindow!

    private lazy var fileOperationService = FileOperationService(appState: appState)
    private lazy var appLaunchService = AppLaunchService(appState: appState)
    private lazy var commandRunnerService = CommandRunnerService(appState: appState)

    func applicationDidFinishLaunching(_ aNotification: Notification) {

        if showInDock {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }

        Task.detached(priority: .background) {
            let bundleID = Bundle.main.bundleIdentifier ?? "cn.wflixu.RClick"
            let log = Logger(subsystem: bundleID, category: "LaunchServices")
            Self.registerFinderExtension(logger: log)
        }

        messenger.on(name: StorageKey.messageFromFinder) { payload in

            self.logger.info("recive mess from finder by app \(payload.description)")
            guard let msgAction = payload.messageAction else {
                self.logger.warning("Unknown message action: \(payload.action)")
                return
            }
            switch msgAction {
            case .openApp:
                self.appLaunchService.openApp(rid: payload.rid, target: payload.target)
            case .performAction:
                self.actionHandler(rid: payload.rid, target: payload.target, trigger: payload.trigger)
            case .createFile:
                self.fileOperationService.createFile(rid: payload.rid, target: payload.target)
            case .openCommonDirs:
                self.openCommonDirs(target: payload.target)
            case .runQuickCommand:
                self.commandRunnerService.runCommand(rid: payload.rid, target: payload.target)
            case .heartbeat:
                self.logger.warning("message from finder plugin heartbeat")
                self.pluginRunning = true
                let target: [String] = self.appState.dirs.map { $0.url.path() }
                self.messenger.sendMessage(name: "running", data: MessagePayload(action: .running, target: target))
            case .running, .quit:
                self.logger.warning("Unexpected message action \(msgAction.rawValue, privacy: .public) from Finder")
            }
        }
        sendObserveDirMessage()
        
    }
    
    private static nonisolated func registerFinderExtension(logger: Logger) {
        let bundleURL = Bundle.main.bundleURL
        let appexPath = bundleURL.appendingPathComponent("Contents/PlugIns/FinderSyncExt.appex").path
        let bundleID = Bundle.main.bundleIdentifier ?? "cn.wflixu.RClick"
        let extensionID = "\(bundleID).FinderSyncExt"
        let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

        cleanLaunchServicesZombies(lsregisterPath: lsregisterPath, extensionID: extensionID, selfPath: bundleURL.path, logger: logger)

        let task = Process()
        task.launchPath = "/usr/bin/pluginkit"
        task.arguments = ["-v", "-a", appexPath]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                logger.info("pluginkit -a succeeded")
            } else {
                logger.warning("pluginkit -a returned \(task.terminationStatus)")
            }
        } catch {
            logger.warning("pluginkit failed: \(error.localizedDescription)")
        }

        let status = LSRegisterURL(bundleURL as CFURL, true)
        if status == noErr {
            logger.info("LSRegisterURL succeeded")
        } else {
            logger.warning("LSRegisterURL returned \(status)")
        }
    }

    private static nonisolated func cleanLaunchServicesZombies(lsregisterPath: String, extensionID: String, selfPath: String, logger: Logger) {
        let dump = Process()
        dump.launchPath = lsregisterPath
        dump.arguments = ["-dump"]
        let pipe = Pipe()
        dump.standardOutput = pipe
        dump.standardError = FileHandle.nullDevice

        do {
            try dump.run()
            dump.waitUntilExit()
        } catch {
            logger.warning("lsregister -dump failed: \(error.localizedDescription)")
            return
        }

        guard let raw = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else {
            return
        }

        let lines = raw.components(separatedBy: "\n")
        var zombiePaths = Set<String>()
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.contains("plugin Identifiers:") && line.contains(extensionID) {
                var j = i - 1
                while j >= 0, j >= i - 30 {
                    if lines[j].hasPrefix("path:") {
                        let path = lines[j].replacingOccurrences(of: "path:", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        if !path.isEmpty,
                           path != selfPath,
                           !path.hasPrefix(selfPath),
                           !FileManager.default.fileExists(atPath: path) {
                            zombiePaths.insert(path)
                        }
                        break
                    }
                    j -= 1
                }
            }
            i += 1
        }

        for zombie in zombiePaths {
            logger.info("Removing LS zombie: \(zombie)")
            let unreg = Process()
            unreg.launchPath = lsregisterPath
            unreg.arguments = ["-u", zombie]
            unreg.standardOutput = FileHandle.nullDevice
            unreg.standardError = FileHandle.nullDevice
            do {
                try unreg.run()
                unreg.waitUntilExit()
                logger.info("Unregistered zombie: \(zombie)")
            } catch {
                logger.warning("Failed to unregister zombie: \(zombie), \(error.localizedDescription)")
            }
        }

        if zombiePaths.isEmpty {
            logger.info("No Launch Services zombies found")
        } else {
            logger.info("Cleaned \(zombiePaths.count) zombie Launch Services entries")
        }
    }

    func openCommonDirs(target: [String]) {
        logger.info("开始打开常用目录，目标路径: \(target)")

        for dirPath in target {
            let path = dirPath.removingPercentEncoding ?? dirPath
            let url = URL(fileURLWithPath: path, isDirectory: true)

            logger.info("正在打开目录: \(path)")
            NSWorkspace.shared.open(url)
        }

        logger.info("常用目录打开操作完成")
    }

    func sendObserveDirMessage() {
        let target: [String] = appState.dirs.map { $0.url.path() }

        messenger.sendMessage(name: "running", data: MessagePayload(action: .running, target: target))
        if !pluginRunning {
            Task {
                try? await Task.sleep(for: .seconds(3))
                sendObserveDirMessage()
            }
        }
    }

    func actionHandler(rid: String, target: [String], trigger: String) {
        guard let action = appState.getActionItem(rid: rid) else {
            logger.warning("when createFile,but not have fileType ")
            return
        }

        switch action.id {
        case "copy-path":
            fileOperationService.copyPath(target)
        case "delete-direct":
            fileOperationService.deleteFolderOrFile(target, trigger)
        case "unhide":
            fileOperationService.unhideFilesAndDirs(target, trigger)
        case "hide":
            fileOperationService.hideFilesAndDirs(target, trigger)
        case "airdrop":
            fileOperationService.showAirDrop(target, trigger)
        default:
            logger.warning("no action id matched")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        messenger.sendMessage(name: "quit", data: MessagePayload(action: .quit))
        logger.info("applicationWillTerminate")
    }
}
