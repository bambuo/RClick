# 渐进式代码质量迭代计划

**范围**: RClick 全项目 | **日期**: 2026-05-06 | **基于**: 代码架构审查 + 命名与语法审计

---

## 设计原则

1. **渐进式、可增量交付**：每个 Phase 完成后项目可正常构建、功能不变
2. **错误修复优先于现代化**：安全与正确性先于风格演进
3. **每次变更后验证构建**：`xcodebuild -project RClick.xcodeproj -scheme RClick -configuration Debug ARCHS=arm64 build`
4. **向后兼容**：所有迭代对用户透明，不改变运行时行为

---

## Phase 0: 紧急修复 — 安全与正确性（预估影响 6 个文件）

> **目标**：消灭所有运行时崩溃风险和资源泄漏，不涉及架构变更。

### 0.1 `fatalError()` → `throws`

- **位置**: [RCBase.swift#L62](file:///Users/johana/Codes/github/RClick/RClick/Model/RCBase.swift)
- **问题**：Bookmark 创建失败时 `fatalError()` 直接终止进程。用户目录被移动后 Release 构建必然崩溃。
- **实现**：

```swift
// 改前
init(id: String = UUID().uuidString, permUrl url: URL) {
    ...
    do {
        bookmark = try url.bookmarkData(options: .withSecurityScope)
    } catch {
        logger.warning("\(error.localizedDescription)")
        fatalError()  // ❌
    }
}

// 改后：改为可失败初始化器
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
```

- **参考**：[SE-0112 Improved NSError Bridging](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0112-nserror-bridging.md) — 可恢复错误使用 throws；[App Sandbox Design Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/AppSandboxDesignGuide/AppSandboxInDepth/AppSandboxInDepth.html) — 明确 Bookmark 是可恢复操作

### 0.2 `try!` 和 `as!` 强制解包替换

- **位置**：[Messager.swift#L49](file:///Users/johana/Codes/github/RClick/RClick/Shared/Messager.swift)、[L74](file:///Users/johana/Codes/github/RClick/RClick/Shared/Messager.swift)、[StringExtension.swift#L100](file:///Users/johana/Codes/github/RClick/RClick/Shared/StringExtension.swift)、[FinderSyncExt.swift#L171](file:///Users/johana/Codes/github/RClick/FinderSyncExt/FinderSyncExt.swift)

- **实现**：

```swift
// Messager.swift L49 — 改前
let data = try! encoder.encode(messsagePayload)

// 改后
func createMessageData(messsagePayload: MessagePayload) -> String? {
    do {
        let data = try JSONEncoder().encode(messsagePayload)
        return String(data: data, encoding: .utf8)
    } catch {
        logger.error("Failed to encode MessagePayload: \(error)")
        return nil
    }
}
// 调用处使用 guard let / if let 安全解包

// Messager.swift L74 — 改前
let payload = reconstructEntry(messagePayload: notification.object as! String)

// 改后
guard let messageString = notification.object as? String else {
    logger.warning("Received notification with unexpected object type")
    return
}
let payload = reconstructEntry(messagePayload: messageString)

// FinderSyncExt.swift L171 — 改前
menuItem.image = NSImage(systemSymbolName: item.icon, accessibilityDescription: item.name)!

// 改后
menuItem.image = NSImage(systemSymbolName: item.icon, accessibilityDescription: item.name)
    ?? NSImage(systemSymbolName: "questionmark.square.dashed", accessibilityDescription: "unknown")
```

- **参考**：[Swift API Design Guidelines — "Avoid force-unwraps"](https://www.swift.org/documentation/api-design-guidelines/#strive-for-fluent-usage)；SE-0335 (`if let`/`guard let` 语法糖)

### 0.3 Security-Scoped Bookmark 资源泄漏修复

- **位置**：[AppState.swift#L208-L226](file:///Users/johana/Codes/github/RClick/RClick/AppState.swift)
- **问题**：`load()` 中循环调用 `startAccessingSecurityScopedResource()`，但对应的 `stopAccessing` 调用被注释掉。
- **实现**：

```swift
// 改前（AppState.load() 中）
let success = folderURL.startAccessingSecurityScopedResource()
if success {
    logger.info("startAccessingSecurityScopedResource success")
    // folderURL.stopAccessingSecurityScopedResource()  ← 被注释！
}

// 改后：按需访问，用完即放（不全局保持）
// 移除 AppState.load() 中的 startAccessing。改为在每次文件操作时：
func deleteFoldorFile(_ target: [String], _ trigger: String) {
    // ... 找到 permDir ...
    let folderURL = try URL(resolvingBookmarkData: permDir.bookmark, 
                            options: .withSecurityScope, relativeTo: nil, 
                            bookmarkDataIsStale: &isStale)
    guard folderURL.startAccessingSecurityScopedResource() else {
        logger.warning("fail access scope")
        return
    }
    defer { folderURL.stopAccessingSecurityScopedResource() }  // ✅ 保证释放
    try fm.removeItem(atPath: item)
}
```

- **参考**：[App Sandbox Design Guide / "Accessing Files Outside Your Container"](https://developer.apple.com/library/archive/documentation/Security/Conceptual/AppSandboxDesignGuide/AppSandboxInDepth/AppSandboxInDepth.html#//apple_ref/doc/uid/TP40011183-CH3-SW16) — 明确要求配对调用

### 0.4 `lazy var` 在 `@MainActor` 类中的并发风险

- **位置**：[FinderSyncExt.swift#L38](file:///Users/johana/Codes/github/RClick/FinderSyncExt/FinderSyncExt.swift)
- **问题**：Swift 6 严格并发下 `lazy var` 初始化非原子，多线程可能触发多次 init。

```swift
// 改前
lazy var appState: AppState = .init(inExt: true)

// 改后：在 init() 中直接赋值
var appState: AppState

override init() {
    self.appState = AppState(inExt: true)
    super.init()
    // ...
}
```

- **参考**：[SE-0411: `@lazy` global and static variables](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0411-lazy-variables.md)；[Swift Concurrency: Actor Reentrancy](https://developer.apple.com/videos/play/wwdc2021/10134/)

### 0.5 `print()` → `@AppLog` / `os.Logger`

- **位置**：共 11 处。`Updater.swift`（5 处）、`RClickApp.swift`（3 处）、`AppState.swift`、`AppsSettingsTabView.swift`、`Utils.swift` 各 1 处
- **示例**：

```swift
// Utils.swift — 改前
public static func isProtectedFolder(_ path: String) -> Bool {
    print("isProtectedFolder: \(path)")
    return Constants.protectedDirs.contains { protectedPath in
        print("Comparing with protected path: \(protectedPath)")
        return path == protectedPath
    }
}

// 改后
@AppLog(category: "Utils")
private static var logger

public static func isProtectedFolder(_ path: String) -> Bool {
    logger.debug("isProtectedFolder: \(path)")
    return Constants.protectedDirs.contains { protectedPath in
        return path == protectedPath
    }
}
```

- **参考**：[WWDC 2020 "Explore logging in Swift"](https://developer.apple.com/videos/play/wwdc2020/10168/) — `os.Logger` 相比 `print` 的优势

### Phase 0 验证

```bash
# 清除 App Group 缓存，排除旧数据干扰
defaults delete group.cn.wflixu.RClick

# Debug 构建
xcodebuild -project RClick.xcodeproj -scheme RClick \
  -configuration Debug -derivedDataPath build ARCHS=arm64 build

# 验证无新增 warning（注意：修复前应记录现有 warning 列表）
# 手动测试：Bookmark 失败场景（非授权目录）不应崩溃
```

---

## Phase 1: 命名规范化 & 拼写修复（预估影响 10 个文件）

> **目标**：消除拼写错误、统一命名风格、提高可读性。仅涉及变量名/类型名/函数名重命名，不改逻辑。

### 1.1 拼写错误修复

| 当前 | 修正 | 位置 |
|------|------|------|
| `Messager` | `Messenger` | [Messager.swift](file:///Users/johana/Codes/github/RClick/RClick/Shared/Messager.swift) |
| `messsagePayload` | `messagePayload` | Messager.swift L47 |
| `recievedMessage` | `receivedMessage` | Messager.swift L72 |
| `volumns` | `volumes` | [RCBase.swift L125](file:///Users/johana/Codes/github/RClick/RClick/Model/RCBase.swift) |
| `deleteFoldorFile` | `deleteFolderOrFile` | [RClickApp.swift L375](file:///Users/johana/Codes/github/RClick/RClick/RClickApp.swift) |

- **实现方式**：在 Xcode 中使用 Refactor → Rename 进行全局重命名，确保所有引用同步更新。
- **参考**：[Swift API Design Guidelines / "Spelling"](https://www.swift.org/documentation/api-design-guidelines/#spelling) — Follow American English spelling

### 1.2 模糊缩写替换

| 当前 | 修正 | 理由 |
|------|------|------|
| `cdirs` | `commonDirs` | 每次阅读需脑内展开，且与其他属性风格不一致 |
| `rcitem` | `matchedItem` | `rc` 前缀无信息量，实际语义是「匹配到的 item」 |
| `triggerManKind` | `triggerMenuKind` | `Man` = menu? 歧义 |
| `tagRidDict` | `tagToRidMap` | Swift 惯例用 Map 而非 Dict |
| `bus` | `messageHandlers` | 字典名 bus 语义偏远 |
| `inExt` | `isInExtension` | `inExt` 可读为 "in extra" |

- **参考**：[Swift API Design Guidelines / "Clarity at the point of use"](https://www.swift.org/documentation/api-design-guidelines/#clarity-at-the-point-of-use)；[SE-0306 `ExpressibleBy` Adoption](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md) 中 Swift 社区对 actor/class 命名的讨论

### 1.3 同概念异名统一

```
PermDir (Models.swift, @Model class)  ──┐
                                         ├──→ 统一为 PermissionDirectory（@Model class）
PermissiveDir (RCBase.swift, struct) ──┘

RCBase protocol ──→ 删除，直接用 Codable & Identifiable & Hashable 约束
```

`RCBase` 实际上只是 `Hashable, Identifiable, Codable` 的组合。Swift 中这种「标记协议」价值不大，直接让各模型声明对应约束即可。

- **参考**：[Swift API Design Guidelines / "Protocol Naming"](https://www.swift.org/documentation/api-design-guidelines/#protocols) — Protocols that describe what something is should read as nouns

### 1.4 Views 中 `EnvironmentObject` 命名统一

| 当前 | 文件 |
|------|------|
| `@EnvironmentObject var appState` | ActionSettingsTabView |
| `@EnvironmentObject var store` | GeneralSettingsTabView, CommonDirsSettingTabView |

全部统一为 `@EnvironmentObject var appState`。

### 1.5 `Key` 枚举命名风格统一 + 移动

```swift
// 改前：大写 + 下划线 与 camelCase 混在同一个枚举
enum Key {
    static let apps = "RCLICK_APPs"              // 全大写
    static let showMenuBarExtra = "showMenuBarExtra"  // camelCase
    static let showInDock = "SHOW_IN_DOCK"       // 全大写
}

// 改后：统一为 camelCase。Key 从 StringExtension.swift 移到 Constants.swift
enum StorageKey {
    static let apps = "rclick_apps"
    static let actions = "rclick_actions"
    static let fileTypes = "rclick_file_types"
    static let permissionDirectories = "rclick_permission_dirs"
    static let commonDirectories = "rclick_common_dirs"
    static let showMenuBarExtra = "show_menu_bar_extra"
    static let showInDock = "show_in_dock"
    static let messageFromFinder = "rclick_message_from_finder"
    static let messageFromApp = "rclick_message_from_app"
}
```

- **参考**：[Swift API Design Guidelines / "General Conventions"](https://www.swift.org/documentation/api-design-guidelines/#general-conventions) — Names of types and properties are UpperCamelCase; names for everything else are lowerCamelCase

### 1.6 类型命名具体化

| 当前 | 修正 |
|------|------|
| `Utils` | `PathSecurityChecker` |
| `Constants.HomedirPath`（运行时计算） | 从 `Constants` 中移出，放到一个 `RuntimePaths` namespace 或改为 `static let` |

### Phase 1 验证

```bash
# 构建验证（重命名不应引入编译错误）
xcodebuild -project RClick.xcodeproj -scheme RClick \
  -configuration Debug -derivedDataPath build ARCHS=arm64 build 2>&1 | grep -E "error:|warning:"

# 清除缓存重新构建
rm -rf build/ModuleCache.noindex
```

---

## Phase 2: Swift 语法现代化（预估影响 8 个文件）

> **目标**：使用 Swift 5.5 - 6.0 引入的现代语法替换过时模式，消除冗余。

### 2.1 `ObservableObject` → `@Observable` 宏

**影响类**：`AppState`、`UpdateManager`、`UpdatePreferences`、`LaunchAtLogin.Observable`

- **参考**：WWDC 2023 ["Discover Observation in SwiftUI"](https://developer.apple.com/videos/play/wwdc2023/10149/) + [Migrating from the ObservableObject protocol to the Observable macro](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro)

```swift
// AppState — 改前
@MainActor
class AppState: ObservableObject {
    @Published var apps: [OpenWithApp] = []
    @Published var commonDirs: [CommonDir] = []
    // ...
}

// AppState — 改后
@MainActor
@Observable
class AppState {
    var apps: [OpenWithApp] = []
    var commonDirs: [CommonDir] = []
    // ...
}
```

```swift
// RClickApp.swift — 改前
@StateObject var appState = AppState.shared
@StateObject private var updateManager = UpdateManager(...)

// 改后
@State var appState = AppState.shared
@State private var updateManager = UpdateManager(...)
```

```swift
// SettingsWindow.swift — 改前
@ObservedObject var appState: AppState

// 改后
var appState: AppState  // @Observable 宏自动跟踪属性访问
```

```swift
// 各 Settings View — 改前
@EnvironmentObject var appState: AppState
@EnvironmentObject var store: AppState

// 改后
@Environment(AppState.self) var appState  // @Observable 使用新的 @Environment API
```

**迁移检查清单**：
- [ ] `@Published` 删除（属性自动 observed）
- [ ] `@StateObject` → `@State`
- [ ] `@ObservedObject` → 无包装器（普通 var）
- [ ] `@EnvironmentObject` → `@Environment(Type.self)`
- [ ] `objectWillChange.send()` → 自动（Observable 宏内部处理）

### 2.2 `DispatchQueue.main.asyncAfter` → Swift Concurrency

- **位置**：[RClickApp.swift#L97](file:///Users/johana/Codes/github/RClick/RClick/RClickApp.swift)

```swift
// 改前
DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
    self.sendObserveDirMessage()
}

// 改后
Task {
    try? await Task.sleep(for: .seconds(3))
    sendObserveDirMessage()
}
```

- **参考**：[SE-0316 Global Actors](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0316-global-actors.md)；[WWDC 2021 "Meet async/await in Swift"](https://developer.apple.com/videos/play/wwdc2021/10132/)

### 2.3 移除 `Task { await MainActor.run { } }` 冗余

- **位置**：[AppState.swift#L26-L29](file:///Users/johana/Codes/github/RClick/RClick/AppState.swift)

```swift
// 改前（类已标记 @MainActor）
init(inExt: Bool = false) {
    self.inExt = inExt
    Task {
        await MainActor.run {  // ← 冗余
            logger.info("start load")
            try? load()
        }
    }
}

// 改后
init(inExt: Bool = false) {
    self.inExt = inExt
    Task { try? load() }
}
```

- **参考**：[SE-0316 Global Actors](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0316-global-actors.md) — `@MainActor` 类型的实例方法自动运行在主 actor 上

### 2.4 移除 `NSLog`

- **位置**：[FinderSyncExt.swift#L115](file:///Users/johana/Codes/github/RClick/FinderSyncExt/FinderSyncExt.swift)

```swift
// 改前
NSLog("requestBadgeIdentifierForURL: %@", url.path as NSString)

// 改后
logger.trace("requestBadgeIdentifierForURL: \(url.path)")
```

### 2.5 替换 `Logger` 手动创建为 `@AppLog` 统一

- **位置**：[FinderSyncExt.swift#L21](file:///Users/johana/Codes/github/RClick/FinderSyncExt/FinderSyncExt.swift)、[RCBase.swift#L6-L8](file:///Users/johana/Codes/github/RClick/RClick/Model/RCBase.swift)、[MenuItemClickable.swift#L13](file:///Users/johana/Codes/github/RClick/FinderSyncExt/MenuItemClickable.swift)

有些文件使用 `private let logger = Logger(...)` 手动创建，应统一为 `@AppLog` 属性包装器。

### 2.6 SWIFT_VERSION 统一

`project.pbxproj` 中 4 个 target 写的是 `SWIFT_VERSION = 5.0`，与项目规范 Swift 6.2+ 不符。统一为 6.0（Xcode 16 支持的最高显式版本），确保 Swift 6 语言模式全面生效。

### Phase 2 验证

```bash
# Xcode 设置 SWIFT_VERSION = 6.0 后全量构建
xcodebuild -project RClick.xcodeproj -scheme RClick \
  -configuration Debug -derivedDataPath build ARCHS=arm64 build

# 验证 Strict Concurrency Checking = Complete 无 error
# 在 Xcode build settings 中确认 SWIFT_STRICT_CONCURRENCY = complete
```

---

## Phase 3: 逻辑抽取 — Service 层引入（预估影响 3 个文件）

> **目标**：将 `AppDelegate` 中的复杂业务逻辑抽取为独立 Service，保持 `actionHandler` 作为轻量路由器。

### 3.1 抽取文件操作为 FileOperationService

新建 `RClick/Shared/FileOperationService.swift`：

```swift
import AppKit
import Foundation

@AppLog(category: "FileOperationService")
private var logger

struct FileOperationService {
    let appState: AppState

    func deleteItems(_ target: [String], trigger: String) {
        // 迁移自 deleteFoldorFile()
        let fm = FileManager.default
        guard trigger != "ctx-container" else {
            showAlert(title: "Warning", message: "Cannot delete current folder...")
            return
        }
        for item in target {
            let decodedPath = item.removingPercentEncoding ?? item
            guard !PathSecurityChecker.isProtectedFolder(decodedPath) else { continue }
            // ... Bookmark 安全域访问 + defer stopAccessing ...
        }
    }

    func createFile(rid: String, target: [String]) {
        // 迁移自 createFile()
    }

    func getUniqueFilePath(dir: String, ext: String) -> String {
        // 迁移自 getUniqueFilePath()
    }

    private func showAlert(title: String, message: String) {
        // 迁移通用 NSAlert 模式
    }
}
```

新建 `RClick/Shared/VisibilityService.swift`、`RClick/Shared/AppLaunchService.swift`、`RClick/Shared/AirDropService.swift` 同理。

### 3.2 AppDelegate 瘦身

```swift
// RClickApp.swift — 改后
func applicationDidFinishLaunching(_ aNotification: Notification) {
    // ... 原有设置 ...

    messager.on(name: Key.messageFromFinder) { payload in
        self.logger.info("recive mess from finder by app \(payload.description)")
        switch payload.action {
        case "open":
            AppLaunchService(appState: appState).open(rid: payload.rid, target: payload.target)
        case "actioning":
            self.actionHandler(rid: payload.rid, target: payload.target, trigger: payload.trigger)
        case "Create File":
            FileOperationService(appState: appState).createFile(rid: payload.rid, target: payload.target)
        case "common-dirs":
            FileOperationService(appState: appState).openCommonDirs(target: payload.target)
        case "heartbeat":
            // heartbeat 逻辑保留（很短）
            ...
        }
    }
}

func actionHandler(rid: String, target: [String], trigger: String) {
    guard let rcitem = appState.getActionItem(rid: rid) else { return }
    switch rcitem.id {
    case "copy-path":
        NSPasteboard.general.clearContents()
        if let path = target.first {
            NSPasteboard.general.setString(path.removingPercentEncoding ?? path, forType: .string)
        }
    case "delete-direct":
        FileOperationService(appState: appState).deleteItems(target, trigger: trigger)
    case "hide":
        VisibilityService.hide(target, trigger: trigger)
    case "unhide":
        VisibilityService.unhide(target, trigger: trigger)
    case "airdrop":
        AirDropService.share(target, trigger: trigger)
    default:
        logger.warning("no action id matched")
    }
}
```

- **参考**：[Swift 设计模式：Strategy 模式](https://www.swift.org/documentation/server/guides/) 中推荐的为不同行为创建独立类型的做法；[Swift Forums: "MVC to MVVM or other refactoring"](https://forums.swift.org/t/swiftui-architecture-which-one/56703)

### Phase 3 验证

```bash
# 构建 + 功能回归测试
xcodebuild -project RClick.xcodeproj -scheme RClick \
  -configuration Debug -derivedDataPath build ARCHS=arm64 build

# 手动测试：逐一验证每个菜单项功能正常
#   1. 复制路径（文件 + 文件夹）
#   2. 直接删除（文件 + 文件夹）
#   3. 隐藏/取消隐藏（文件 + 文件夹）
#   4. AirDrop 分享
#   5. 用 Terminal/VSCode 打开文件夹
#   6. 新建各类文件模板
```

---

## Phase 4: IPC 通信类型安全化（预估影响 2 个文件）

> **目标**：用强类型枚举替代字符串匹配，使编译器能检查所有 case 是否被处理。

### 4.1 定义强类型 Action 枚举

在 `Messager.swift` 或新建 `RClick/Shared/IPCProtocol.swift`：

```swift
enum MessengerAction: String, Codable, CaseIterable {
    case open
    case actioning
    case createFile = "Create File"
    case commonDirs = "common-dirs"
    case heartbeat
    case running
    case quit
}

enum TriggerKind: String, Codable {
    case contextItems = "ctx-items"
    case contextContainer = "ctx-container"
    case contextSidebar = "ctx-sidebar"
    case toolbar
}

struct MessagePayload: Codable {
    var action: MessengerAction  // 改前 var action: String
    var target: [String] = []
    var rid: String = ""
    var trigger: TriggerKind = .toolbar

    enum CodingKeys: String, CodingKey {
        case action, target, rid, trigger
    }
}
```

### 4.2 AppDelegate 路由改为穷举 switch

```swift
// 改前
switch payload.action {
case "open": ...
case "Create File": ...
default: ...
}

// 改后：编译器强制检查所有 case
switch payload.action {
case .open:
    AppLaunchService(appState: appState).open(rid: payload.rid, target: payload.target)
case .actioning:
    actionHandler(rid: payload.rid, target: payload.target, trigger: payload.trigger)
case .createFile:
    FileOperationService(appState: appState).createFile(rid: payload.rid, target: payload.target)
case .commonDirs:
    FileOperationService(appState: appState).openCommonDirs(target: payload.target)
case .heartbeat:
    handleHeartbeat()
case .running: break   // App 不处理 running（App 发送它）
case .quit: break      // App 不处理 quit（App 发送它）
}
// 无需 default，编译器保证穷举
```

- **参考**：[SE-0292 `Codable` 对 RawRepresentable 的默认实现](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0292-codable-rawrepresentable.md)；[Swift API Design Guidelines / "Omit needless words"](https://www.swift.org/documentation/api-design-guidelines/#omit-needless-words)

### Phase 4 验证

```bash
# 构建。编译器会检查 switch 是否穷举所有 case
xcodebuild ...

# 手动测试：确认新增一个 action 时编译器报 warning，不会静默 fall through
```

---

## Phase 5: 持久化层统一（预估影响 4 个文件）

> **目标**：将 `PropertyListEncoder/Decoder` 手工序列化替换为 SwiftData 统一管理，消除双轨持久化。

### 5.1 将 `OpenWithApp`、`RCAction`、`NewFile`、`CommonDir` 转为 `@Model class`

```swift
// Models.swift — 合并 RCBase.swift 中的所有模型

@Model
final class OpenWithApp {
    var id: String
    var url: URL
    var itemName: String
    var arguments: [String]
    var environment: [String: String]
    
    init(appURL url: URL) {
        self.id = url.path
        self.url = url
        self.itemName = url.deletingPathExtension().lastPathComponent
        self.arguments = []
        self.environment = [:]
    }
    
    static var defaultApps: [OpenWithApp] { [.terminal, .vscode].compactMap { $0 } }
    static var terminal: OpenWithApp? { OpenWithApp(appURL: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")) }
    static var vscode: OpenWithApp? { ... }
}

@Model
final class RCAction {
    @Attribute(.unique) var id: String
    var name: String
    var enabled: Bool
    var index: Int
    var icon: String
    
    static var all: [RCAction] { [.copyPath, .deleteDirect, .airdrop, .hideFileDir, .unhideFileDir] }
}
// ... NewFile, CommonDir, PermissionDirectory 同理
```

### 5.2 删除 AppState 中的 `save()/load()` 手工序列化

替换为 SwiftData 的 `ModelContext.insert()` / `FetchDescriptor`：

```swift
// AppState.swift — 改后
@Observable
class AppState {
    private let modelContext: ModelContext
    
    var apps: [OpenWithApp] {
        (try? modelContext.fetch(FetchDescriptor<OpenWithApp>())) ?? []
    }
    var actions: [RCAction] {
        (try? modelContext.fetch(FetchDescriptor<RCAction>())) ?? []
    }
    // ... 同模式
    
    init(modelContext: ModelContext = SharedDataManager.sharedModelContainer.mainContext) {
        self.modelContext = modelContext
    }
    
    func addApp(_ item: OpenWithApp) {
        modelContext.insert(item)
        try? modelContext.save()
    }
}
```

### 5.3 Unified `ModelContainer`

```swift
// ModelContainer.swift — 改后
static var sharedModelContainer: ModelContainer = {
    let container = try ModelContainer(
        for: PermissionDirectory.self, OpenWithApp.self, RCAction.self, NewFile.self, CommonDir.self,
        configurations: ModelConfiguration(url: storeURL)
    )
    return container
}()
```

### Phase 5 验证

```bash
# 完整迁移后，清除旧 UserDefaults 数据
defaults delete group.cn.wflixu.RClick

# 构建 + 验证 SwiftData 正常读写
xcodebuild ...

# 手动测试：
#   1. 首次启动加载默认数据
#   2. 修改配置后重启，数据持久化正常
#   3. Extension 进程能正常读取数据
```

---

## Phase 6: 清理死代码 & 可选优化（预估影响 4 个文件）

### 6.1 删除 MenuItemClickable.swift 中的废弃代码

[MenuItemClickable.swift](file:///Users/johana/Codes/github/RClick/FinderSyncExt/MenuItemClickable.swift) 中大量代码被注释掉且未被引用，整体评估是否需要保留。

### 6.2 移除 `HasParentBookmark`

[AppState.swift#L137-L141](file:///Users/johana/Codes/github/RClick/RClick/AppState.swift)：方法体完全注释，返回固定 `false`。

### 6.3 WezTerm 硬编码路径移除

[RClickApp.swift#L449-L470](file:///Users/johana/Codes/github/RClick/RClick/RClickApp.swift)：把 `/Users/lixu/play/rpm/target/debug/rpm` 改为配置项或通过 `OpenWithApp` 的 `arguments` 传递。

### 6.4 参考源适配

这些是当前的遗留开发痕迹，属于一般代码卫生范畴，无特定规范要求，但 [项目 AGENTS.md](file:///Users/johana/Codes/github/RClick/AGENTS.md) 中明确要求「AppKit 仅用于系统集成」和「文件路径不要硬编码」，Phase 6.3 即违反后者。

---

## 附录 A：变更文件影响矩阵

| 文件 | Phase 0 | Phase 1 | Phase 2 | Phase 3 | Phase 4 | Phase 5 | Phase 6 |
|------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `RCBase.swift` | ● | ● | ● | | | ● | |
| `Messager.swift` | ● | ● | | | ● | | |
| `StringExtension.swift` | ● | ● | | | | | |
| `FinderSyncExt.swift` | ● | ● | ● | | | | ● |
| `AppState.swift` | ● | ● | ● | | | ● | ● |
| `RClickApp.swift` | ● | ● | ● | ● | ● | ● | ● |
| `Updater.swift` | ● | | ● | | | | |
| `UpdaterView.swift` | | | ● | | | | |
| `Utils.swift` | ● | ● | | | | | |
| `SettingsWindow.swift` | | | ● | | | | |
| `AppsSettingsTabView.swift` | ● | ● | ● | | | | |
| `CommonDirsSettingTabView.swift` | | ● | | | | | |
| `Models.swift` | | ● | | | | ● | |
| `ModelContainer.swift` | | | | | | ● | |
| `AppLogger.swift` | | | ● | | | | |
| `MenuItemClickable.swift` | | | ● | | | | ● |
| `project.pbxproj` | | | ● | | | | |
| **新建** `FileOperationService.swift` | | | | ● | | | |
| **新建** `IPCProtocol.swift` | | | | | ● | | |

## 附录 B：参考引源汇总

| 引用 | 相关 Phase | 链接 |
|------|:---:|------|
| Swift API Design Guidelines | P1, P4 | https://www.swift.org/documentation/api-design-guidelines/ |
| SE-0112 Improved NSError Bridging | P0 | https://github.com/swiftlang/swift-evolution/blob/main/proposals/0112-nserror-bridging.md |
| App Sandbox Design Guide | P0 | https://developer.apple.com/library/archive/documentation/Security/Conceptual/AppSandboxDesignGuide/ |
| SE-0316 Global Actors | P2 | https://github.com/swiftlang/swift-evolution/blob/main/proposals/0316-global-actors.md |
| SE-0411 Lazy Variables | P0 | https://github.com/swiftlang/swift-evolution/blob/main/proposals/0411-lazy-variables.md |
| SE-0292 Codable RawRepresentable | P4 | https://github.com/swiftlang/swift-evolution/blob/main/proposals/0292-codable-rawrepresentable.md |
| WWDC 2023 — Discover Observation in SwiftUI | P2 | https://developer.apple.com/videos/play/wwdc2023/10149/ |
| WWDC 2021 — Meet async/await in Swift | P2 | https://developer.apple.com/videos/play/wwdc2021/10132/ |
| WWDC 2020 — Explore logging in Swift | P0 | https://developer.apple.com/videos/play/wwdc2020/10168/ |
| Swift Observation Migration Guide | P2 | https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro |
| Swift Forums: SwiftUI Architecture | P3 | https://forums.swift.org/t/swiftui-architecture-which-one/56703 |
| Apple: Adopting Swift Concurrency | P2 | https://developer.apple.com/documentation/swift/swift-concurrency |
| AGENTS.md (project) | All | /Users/johana/Codes/github/RClick/AGENTS.md |
