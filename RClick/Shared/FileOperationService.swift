import AppKit
import Foundation
import OSLog

@MainActor
final class FileOperationService {
    private let appState: AppState
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "RClick", category: "FileOperation")

    init(appState: AppState) {
        self.appState = appState
    }

    func getUniqueFilePath(dir: String, ext: String) -> String {
        let fileManager = FileManager.default
        let baseFileName = String(localized: "Untitled")
        var filePath = "\(dir)\(baseFileName)\(ext)"
        var counter = 1

        while fileManager.fileExists(atPath: filePath) {
            let newFileName = "\(baseFileName)\(counter)"
            filePath = "\(dir)\(newFileName)\(ext)"
            counter += 1
        }

        return filePath
    }

    func copyPath(_ target: [String]) {
        guard let dirPath = target.first else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(dirPath.removingPercentEncoding ?? dirPath, forType: .string)
    }

    func deleteFolderOrFile(_ target: [String], _ trigger: String) {
        logger.info("deleteFolderOrFile trigger:\(trigger)")
        let fm = FileManager.default

        if trigger == "ctx-container" {
            let alert = NSAlert()
            alert.messageText = "警告"
            alert.informativeText = "无法删除当前文件夹，请选择文件或子文件夹进行删除。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.runModal()
            return
        }

        for item in target {
            let decodedPath = item.removingPercentEncoding ?? item

            if PathSecurityChecker.isProtectedFolder(decodedPath) {
                let alert = NSAlert()
                alert.messageText = "警告"
                alert.informativeText = "无法删除系统保护文件夹：\(decodedPath)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "确定")
                alert.runModal()
                logger.warning("试图删除受保护的系统文件夹，操作已被阻止: \(decodedPath)")
                continue
            }

            guard let permDir = appState.dirs.first(where: { item.contains($0.url.path()) }) else {
                continue
            }

            var isStale = false
            do {
                let folderURL = try URL(resolvingBookmarkData: permDir.bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)

                if isStale {
                    logger.warning("Bookmark is stale for \(permDir.url.path)")
                }

                guard folderURL.startAccessingSecurityScopedResource() else {
                    logger.warning("fail access scope \(permDir.url.path)")
                    continue
                }
                defer { folderURL.stopAccessingSecurityScopedResource() }
                try fm.removeItem(atPath: item.removingPercentEncoding ?? item)
            } catch {
                logger.error("delete \(target) file run error \(error)")
            }
        }
    }

    func createFile(rid: String, target: [String]) {
        guard let fileType = appState.getFileType(rid: rid), let dirPath = target.first else {
            logger.warning("when createFile,but not have fileType \(rid)")
            return
        }

        let ext = fileType.ext
        logger.info("create file dir:\(dirPath) -- ext \(ext)")
        let filePath = getUniqueFilePath(dir: dirPath.removingPercentEncoding ?? dirPath, ext: ext)
        let fileURL = URL(fileURLWithPath: filePath)

        guard let dir = appState.dirs.first(where: { dirPath.contains($0.url.path) }) else {
            return
        }

        var isStale = false
        do {
            let folderURL = try URL(resolvingBookmarkData: dir.bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)

            if isStale {
                logger.warning("Bookmark is stale for \(dir.url.path)")
            }

            guard folderURL.startAccessingSecurityScopedResource() else {
                logger.warning("fail access scope \(dir.url.path)")
                return
            }
            defer { folderURL.stopAccessingSecurityScopedResource() }

            do {
                let fileManager = FileManager.default

                if let templateUrl = fileType.template {
                    try fileManager.copyItem(at: templateUrl, to: fileURL)
                    logger.info("已成功复制模板到目标路径: \(fileURL.path)")
                } else if let defaultTemplateURL = Bundle.main.url(forResource: "template", withExtension: ext.replacingOccurrences(of: ".", with: "")) {
                    logger.info("使用模板创建文件，模板路径: \(defaultTemplateURL.path)")
                    try fileManager.copyItem(at: defaultTemplateURL, to: fileURL)
                    logger.info("已成功复制模板到目标路径: \(fileURL.path)")
                } else {
                    logger.warning("模板文件不存在: \(ext)")
                    try Data().write(to: fileURL)
                }
            } catch let error as NSError {
                switch error.domain {
                case NSCocoaErrorDomain:
                    switch error.code {
                    case NSFileNoSuchFileError:
                        logger.error("文件不存在: \(filePath)")
                    case NSFileWriteOutOfSpaceError:
                        logger.error("磁盘空间不足")
                    case NSFileWriteNoPermissionError:
                        logger.error("没有写入权限: \(filePath)")
                    default:
                        logger.error("创建文件错误: \(error.localizedDescription) (错误码: \(error.code))")
                    }
                default:
                    logger.error("未处理的错误: \(error.localizedDescription) (错误码: \(error.code))")
                }
            }
        } catch {
            logger.error("Failed to resolve bookmark: \(error)")
        }
    }

    func unhideFilesAndDirs(_ target: [String], _ trigger: String) {
        logger.info("开始取消隐藏文件和目录，目标路径: \(target)")
        guard let dirPath = target.first else { return }
        let fileManager = FileManager.default
        let path = dirPath.removingPercentEncoding ?? dirPath
        logger.info("处理主目录: \(path)")
        var url = URL(fileURLWithPath: path)

        do {
            let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isHiddenKey], options: [.skipsPackageDescendants])
            for case var fileURL in contents {
                do {
                    var resourceValues = URLResourceValues()
                    resourceValues.isHidden = false
                    try fileURL.setResourceValues(resourceValues)
                    logger.info("成功取消隐藏: \(fileURL.path)")
                } catch {
                    logger.error("取消隐藏失败: \(fileURL.path): \(error)")
                }
            }
        } catch {
            logger.error("获取目录内容失败: \(error)")
        }

        do {
            var resourceValues = URLResourceValues()
            resourceValues.isHidden = false
            try url.setResourceValues(resourceValues)
            logger.info("成功取消隐藏主目录: \(path)")
        } catch {
            logger.error("取消隐藏主目录失败: \(path): \(error)")
        }
        logger.info("取消隐藏操作完成，共处理目录: \(path)")
    }

    func hideFilesAndDirs(_ target: [String], _ trigger: String) {
        logger.info("开始隐藏文件和目录，目标路径: \(target), 触发器: \(trigger)")
        let fileManager = FileManager.default

        if trigger == "ctx-container", let dirPath = target.first {
            let path = dirPath.removingPercentEncoding ?? dirPath
            logger.info("处理主目录: \(path)")
            let url = URL(fileURLWithPath: path)

            do {
                let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsPackageDescendants])
                for case var fileURL in contents {
                    if PathSecurityChecker.isProtectedFolder(fileURL.path) {
                        logger.warning("跳过受保护的文件路径: \(fileURL.path)")
                        continue
                    }
                    do {
                        var resourceValues = URLResourceValues()
                        resourceValues.isHidden = true
                        try fileURL.setResourceValues(resourceValues)
                        logger.info("成功隐藏: \(fileURL.path)")
                    } catch {
                        logger.error("隐藏失败: \(fileURL.path): \(error)")
                    }
                }
            } catch {
                logger.error("获取目录内容失败: \(error)")
            }
        } else if trigger == "ctx-items" {
            for dirPath in target {
                let path = dirPath.removingPercentEncoding ?? dirPath
                logger.info("处理路径: \(path)")
                var url = URL(fileURLWithPath: path)

                if PathSecurityChecker.isProtectedFolder(path) {
                    logger.warning("跳过受保护的文件路径: \(path)")
                    continue
                }
                do {
                    var resourceValues = URLResourceValues()
                    resourceValues.isHidden = true
                    try url.setResourceValues(resourceValues)
                    logger.info("成功隐藏: \(path)")
                } catch {
                    logger.error("隐藏失败: \(path): \(error)")
                }
            }
        }
        logger.info("隐藏操作完成")
    }

    func showAirDrop(_ target: [String], _ trigger: String) {
        logger.info("showAirDrop trigger:\(trigger)")
        let fm = FileManager.default
        var fileURLs: [URL] = []

        if trigger == "ctx-container" {
            let alert = NSAlert()
            alert.messageText = "警告"
            alert.informativeText = "无法共享当前文件夹，请选择文件或子文件夹进行共享。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.runModal()
            return
        }

        for item in target {
            let decodedPath = item.removingPercentEncoding ?? item
            logger.info("airdrop path \(decodedPath)")

            if PathSecurityChecker.isProtectedFolder(decodedPath) {
                let alert = NSAlert()
                alert.messageText = "警告"
                alert.informativeText = "无法分享系统保护文件夹：\(decodedPath)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "确定")
                alert.runModal()
                logger.warning("试图分享受保护的系统文件夹，操作已被阻止: \(decodedPath)")
                continue
            }

            var isDir: ObjCBool = false
            if fm.fileExists(atPath: decodedPath, isDirectory: &isDir), isDir.boolValue {
                logger.warning("不能通过 AirDrop 分享文件夹: \(decodedPath)")
                let alert = NSAlert()
                alert.messageText = "提示"
                alert.informativeText = "不能通过 AirDrop 分享文件夹：\(decodedPath)"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "确定")
                alert.runModal()
                continue
            }

            fileURLs.append(URL(fileURLWithPath: decodedPath))
        }

        guard !fileURLs.isEmpty else { return }

        if let airDropService = NSSharingService(named: .sendViaAirDrop) {
            airDropService.perform(withItems: fileURLs)
            logger.info("已通过 AirDrop 分享文件: \(fileURLs.map { $0.path }.joined(separator: ", "))")
        } else {
            logger.warning("无法获取 AirDrop 服务")
        }
    }
}
