import Foundation

struct NewFile: RCBase {
    static func == (lhs: NewFile, rhs: NewFile) -> Bool {
        lhs.id == rhs.id
    }

    var ext: String
    var name: String
    var enabled = true
    var idx: Int
    var icon: String
    var id: String
    var openApp: URL?
    var template: URL?

    init(ext: String, name: String, enabled: Bool = true, idx: Int, icon: String = "document", id: String = UUID().uuidString) {
        self.ext = ext
        self.name = name
        self.enabled = enabled
        self.idx = idx
        self.icon = icon
        self.id = id
    }
}

extension NewFile {
    static let all: [NewFile] = [.txt, .md, .json, .docx, .pptx, .xlsx]

    static let json = NewFile(ext: ".json", name: "JSON", idx: 0, icon: "icon-file-json")
    static let txt = NewFile(ext: ".txt", name: "TXT", idx: 1, icon: "icon-file-txt")
    static let md = NewFile(ext: ".md", name: "Markdown", idx: 2, icon: "icon-file-md")
    static let docx = NewFile(ext: ".docx", name: "DOCX", idx: 3, icon: "icon-file-docx")
    static let pptx = NewFile(ext: ".pptx", name: "PPTX", idx: 4, icon: "icon-file-pptx")
    static let xlsx = NewFile(ext: ".xlsx", name: "XLSX", idx: 5, icon: "icon-file-xlsx")
}
