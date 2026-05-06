import Foundation

protocol RCBase: Hashable, Identifiable, Codable {
    var id: String { get }
}
