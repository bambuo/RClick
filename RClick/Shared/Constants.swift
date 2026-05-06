//
//  Constants.swift
//  RClick
//
//  Created by 李旭 on 2024/9/25.
//

import Foundation


public enum Constants {
    static let HomedirPath = PathSecurityChecker.getRealHomeDir()
    /// The identifier for the settings window.
    static let settingsWindowID = "rclick-settings"
    static let protectedDirs = [
        HomedirPath + "/Desktop/",
        HomedirPath + "/Desktop/danger/",
        HomedirPath + "/Applications/",
        "/Applications/",
        "/System/",
        "/Library/",
        "/Users/",
        "/usr/",
        "/bin/",
        "/sbin/",
        "/var/"
    ]
    static let suitName = "group.cn.wflixu.RClick"

}

enum StorageKey {
    static let showContextualMenuForItem = "SHOW_CONTEXTUAL_MENU_FOR_ITEM"
    static let showContextualMenuForContainer = "SHOW_CONTEXTUAL_MENU_FOR_CONTAINER"
    static let showContextualMenuForSidebar = "SHOW_CONTEXTUAL_MENU_FOR_SIDEBAR"
    static let showToolbarItemMenu = "SHOW_TOOLBAR_ITEM_MENU"
    static let showDockIcon = "SHOW_DOCK_ICON"

    static let globalApplicationArgumentsString = "GLOBAL_APPLICATION_ARGUMENTS_STRING"
    static let globalApplicationEnvironmentString = "GLOBAL_APPLICATION_ENVIRONMENT_STRING"

    static let copySeparator = "COPY_SEPARATOR"
    static let newFileName = "NEW_FILE_NAME"
    static let newFileExtension = "NEW_FILE_EXTENSION"

    static let showSubMenuForApplication = "SHOW_SUB_MENU_FOR_APPLICATION"
    static let showSubMenuForAction = "SHOW_SUB_MENU_FOR_ACTION"
    static let messageFromFinder = "RCLICK_FINDER_Main"
    static let messageFromMain = "RCLICK_MAIN_FINDER"

    static let apps = "RCLICK_APPs"
    static let actions = "RCLICK_ACTIONS"
    static let fileTypes = "RCLICK_FILE_TYPES"
    static let permDirs = "RCLICK_PERMISSIVE_DIRS"
    static let commonDirs = "RCLICK_COMMON_DIRS"
    static let quickCommands = "RCLICK_QUICK_COMMANDS"
    static let showMenuBarExtra = "showMenuBarExtra"
    static let showInDock = "SHOW_IN_DOCK"
}
