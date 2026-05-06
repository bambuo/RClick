import Foundation

struct QuickCommand: RCBase {
    static func == (lhs: QuickCommand, rhs: QuickCommand) -> Bool {
        lhs.id == rhs.id
    }

    var id: String
    var name: String
    var icon: String
    var template: String
    var enabled = true
    var dangerous = false
    var idx: Int

    init(id: String = UUID().uuidString, name: String, icon: String, template: String, enabled: Bool = true, dangerous: Bool = false, idx: Int = 0) {
        self.id = id
        self.name = name
        self.icon = icon
        self.template = template
        self.enabled = enabled
        self.dangerous = dangerous
        self.idx = idx
    }
}

extension QuickCommand {
    func resolvedCommand(path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        let dir = url.deletingLastPathComponent().path
        let ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
        let nameWithoutExt = url.deletingPathExtension().lastPathComponent

        return template
            .replacing("{path}", with: path)
            .replacing("{name}", with: name)
            .replacing("{dir}", with: dir)
            .replacing("{ext}", with: ext)
            .replacing("{name_no_ext}", with: nameWithoutExt)
    }

    func resolvedCommand(forPaths paths: [String]) -> String {
        let all = paths.map { "\"\($0)\"" }.joined(separator: " ")
        let joined = template.replacing("{all}", with: all)
        if let first = paths.first {
            let url = URL(fileURLWithPath: first)
            let name = url.lastPathComponent
            let dir = url.deletingPathExtension().path
            let ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
            let nameWithoutExt = url.deletingPathExtension().lastPathComponent

            return joined
                .replacing("{path}", with: first)
                .replacing("{name}", with: name)
                .replacing("{dir}", with: dir)
                .replacing("{ext}", with: ext)
                .replacing("{name_no_ext}", with: nameWithoutExt)
        }
        return joined
    }

    static let presets: [QuickCommand] = [
        QuickCommand(
            name: "Remove Quarantine",
            icon: "shield.slash",
            template: "xattr -cr \"{path}\"",
            dangerous: true
        ),
        QuickCommand(
            name: "Make Executable",
            icon: "hammer",
            template: "chmod +x \"{path}\""
        ),
        QuickCommand(
            name: "Strip Code Sign",
            icon: "signature",
            template: "codesign --remove-signature \"{path}\"",
            dangerous: true
        ),
        QuickCommand(
            name: "Show File Info",
            icon: "ellipsis.curlybraces",
            template: "file \"{path}\""
        ),
        QuickCommand(
            name: "Zip File",
            icon: "rectangle.compress.vertical",
            template: "zip -r \"{name_no_ext}.zip\" \"{path}\""
        ),
    ]
}
