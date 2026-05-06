import Foundation

struct CommonDir: RCBase {
    var id: String
    var name: String
    var url: URL
    var icon: String

    init(id: String, name: String, url: URL, icon: String) {
        self.id = id
        self.name = name
        self.url = url
        self.icon = icon
    }
}
