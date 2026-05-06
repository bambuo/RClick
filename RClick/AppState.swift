//
//  File.swift
//  RClick
//
//  Created by 李旭 on 2024/9/26.
//

import Foundation
import OrderedCollections
import OSLog
import SwiftUI

@MainActor
@Observable
class AppState {
    static let shared = AppState()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "RClick", category: "AppState")

    var apps: [OpenWithApp] = []
    var dirs: [PermissiveDir] = []
    var actions: [RCAction] = []
    var newFiles: [NewFile] = []
    var commonDirs: [CommonDir] = []
    var isInExtension: Bool

    var showMenuBar: Bool = true


    init(isInExtension: Bool = false) {
        self.isInExtension = isInExtension
        Task {
            try? load()
        }
    }
    
    // Apps
    @MainActor func deleteApp(index: Int) {
        apps.remove(at: index)
        do {
            try save()
            // 使用 result
        } catch {
            // 处理错误
            logger.info("save error: \(error.localizedDescription)")
        }
    }

    @MainActor func addApp(item: OpenWithApp) {
        logger.info("start add app")
        apps.append(item)
        
        do {
            try save()
            // 使用 result
        } catch {
            // 处理错误
            logger.info("save error: \(error.localizedDescription)")
        }
    }
    
    @MainActor
    func updateApp(id: String, itemName: String, arguments: [String], environment: [String: String]) {
        if let index = apps.firstIndex(where: { $0.id == id }) {
            var updatedApp = apps[index]
            updatedApp.itemName = itemName
            updatedApp.arguments = arguments
            updatedApp.environment = environment
            apps[index] = updatedApp
            try? save()
        }
    }
    
    func getAppItem(rid: String) -> OpenWithApp? {
        return apps.first { $0.id == rid }
    }
    
    func getFileType(rid: String) -> NewFile? {
        return newFiles.first(where: { nf in
            rid == nf.id
        })
    }
    
    @MainActor func addNewFile(_ item: NewFile) {
        logger.info("start add new file type")
        newFiles.append(item)
        
        do {
            try save()
            // 使用 result
        } catch {
            // 处理错误
            logger.info("save error: \(error.localizedDescription)")
        }
    }
    
    func getActionItem(rid: String) -> RCAction? {
        actions.first(where: { rcAtion in
            rcAtion.id == rid
        })
    }
    
    // Action
    @MainActor func toggleActionItem() {
        try? save()
    }

    @MainActor func resetActionItems() {
        actions = RCAction.all
        try? save()
    }
    
    @MainActor func resetFiletypeItems() {
        newFiles = NewFile.all
        try? save()
    }
    
    // Permission
    @MainActor func deletePermissiveDir(index: Int) {
        dirs.remove(at: index)

        try? save()
    }

    @MainActor func hasParentBookmark(of url: URL) -> Bool {
        return false
//        let storedUrls = dirs.map { $0.url }
//        for storedURL in storedUrls {
//            // 确保 storedURL 是一个目录，并且传入的 URL 以 storedURL 的路径为前缀
//            if url.path.hasPrefix(storedURL.path) {
//                return true
//            }
//        }
//        return false
    }
    
    @MainActor
    private func save() throws {
        let encoder = PropertyListEncoder()
        let appItemsData = try encoder.encode(OrderedSet(apps))
        let actionItemsData = try encoder.encode(OrderedSet(actions))
        let filetypeItemsData = try encoder.encode(OrderedSet(newFiles))
        let permDirsData = try encoder.encode(OrderedSet(dirs))
        let commonDirsData = try encoder.encode(OrderedSet(commonDirs))
        UserDefaults.group.set(appItemsData, forKey: StorageKey.apps)
        UserDefaults.group.set(actionItemsData, forKey: StorageKey.actions)
        UserDefaults.group.set(filetypeItemsData, forKey: StorageKey.fileTypes)
        UserDefaults.group.set(permDirsData, forKey: StorageKey.permDirs)
        UserDefaults.group.set(commonDirsData, forKey: StorageKey.commonDirs)
    }
    
    @MainActor
    func savePermissiveDir() throws {
        let encoder = PropertyListEncoder()
        let permDirsData = try encoder.encode(OrderedSet(dirs))
        UserDefaults.group.set(permDirsData, forKey: StorageKey.permDirs)
    }

    //  保存常用文件夹
    @MainActor
    func saveCommonDir() throws {
        let encoder = PropertyListEncoder()
        let commonDirsData = try encoder.encode(OrderedSet(commonDirs))
        UserDefaults.group.set(commonDirsData, forKey: StorageKey.commonDirs)
        logger.info("save common dirs success")
    }
    
    @MainActor func refresh() {
        _ = try? load()
    }
    
    @MainActor func sync() {
        _ = try? save()
    }
    
    @MainActor
    private func load() throws {
        let decoder = PropertyListDecoder()
        if !isInExtension {
            if let permDirsData = UserDefaults.group.data(forKey: StorageKey.permDirs) {
                dirs = try decoder.decode([PermissiveDir].self, from: permDirsData)
                logger.info("load permDir success, \(self.dirs.count) directories")

                for dir in dirs {
                    var isStale = false
                    do {
                        let folderURL = try URL(resolvingBookmarkData: dir.bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)

                        if isStale {
                            logger.warning("Bookmark is stale for \(dir.url.path)")
                        }

                        logger.info("Bookmark validated for \(folderURL.path)")
                    } catch {
                        logger.error("Failed to resolve bookmark: \(error.localizedDescription)")
                    }
                }
                 
            } else {
                logger.warning("load permission dirfailed")
               
                dirs = []
            }
        }

        if let commonDirsData = UserDefaults.group.data(forKey: StorageKey.commonDirs) {
            commonDirs = try decoder.decode([CommonDir].self, from: commonDirsData)
                
            logger.info("load common dirs success")
        } else {
            logger.warning("load common dirs failed")
            commonDirs = []
        }
        
        if let actionData = UserDefaults.group.data(forKey: StorageKey.actions) {
            actions = try decoder.decode([RCAction].self, from: actionData)
            logger.info("load actions success")
        } else {
            logger.warning("load actions failed")
            actions = RCAction.all
        }
        
        if let filetypeItemData = UserDefaults.group.data(forKey: StorageKey.fileTypes) {
            newFiles = try decoder.decode([NewFile].self, from: filetypeItemData)
            logger.info("load filetype success")
        } else {
            logger.warning("load  new file type failed")
            newFiles = NewFile.all
        }
        
        if let appItemData = UserDefaults.group.data(forKey: StorageKey.apps) {
            apps = try decoder.decode([OpenWithApp].self, from: appItemData)
            logger.info("load apps success")
        } else {
            logger.warning("load apps failed, use defaults")
            apps = OpenWithApp.defaultApps
            try? save()
        }
    }
}
