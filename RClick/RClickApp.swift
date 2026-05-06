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

    func applicationDidFinishLaunching(_ aNotification: Notification) {

        if showInDock {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
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
