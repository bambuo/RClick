//
//  StringExtension.swift
//  RClick
//
//  Created by 李旭 on 2024/4/5.
//

import Foundation
import OSLog

let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
var subsystem: String { bundleIdentifier }

private let logger = Logger(subsystem: subsystem, category: "user_defaults")

enum NewFileExtension: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case none = "(none)"
    case swift
    case txt
}

extension String {
    func toDictionary(separator: Character = " ") -> [String: String] {
        split(separator: separator)
            .map { $0.split(separator: "=") }
            .filter { $0.count == 2 }
            .reduce(into: [String: String]()) { result, pair in
                let key = String(pair[0])
                let value = String(pair[1])
                result[key] = value
            }
    }
}

extension Dictionary {
    func toString(separator: String = " ") -> String {
        compactMap { "\($0)=\($1)" }.joined(separator: separator)
    }
}

func loadLocalizationKeys(from tableName: String, bundle: Bundle = .main) -> [String: String] {
    var keyToLocalizedString = [String: String]()
    var localizedStringToKey = [String: String]()

    if let path = bundle.path(forResource: tableName, ofType: "strings"),
       let strings = NSDictionary(contentsOfFile: path) as? [String: String]
    {
        for (key, value) in strings {
            keyToLocalizedString[key] = value
            localizedStringToKey[value] = key
        }
    }
    return localizedStringToKey
}

extension String {
    static func key(forLocalizedString localizedString: String, in tableName: String, bundle: Bundle = .main) -> String? {
        let localizedStringToKey = loadLocalizationKeys(from: tableName, bundle: bundle)
        return localizedStringToKey[localizedString]
    }
}

// if let key = String.key(forLocalizedString: "Hello", in: "Localizable") {
//    print("The key for 'Hello' is \(key)")
// }

extension UserDefaults {
    static var group: UserDefaults {
        guard let defaults = UserDefaults(suiteName: "group.cn.wflixu.RClick") else {
            logger.critical("Failed to initialize App Group UserDefaults. Check entitlements and provisioning profile.")
            return .standard
        }
        return defaults
    }

    var showContextualMenuForItem: Bool {
        defaults(for: StorageKey.showContextualMenuForItem) ?? true
    }

    var showContextualMenuForContainer: Bool {
        defaults(for: StorageKey.showContextualMenuForContainer) ?? true
    }

    var showContextualMenuForSidebar: Bool {
        defaults(for: StorageKey.showContextualMenuForSidebar) ?? true
    }

    var showToolbarItemMenu: Bool {
        defaults(for: StorageKey.showToolbarItemMenu) ?? true
    }

    var copySeparator: String {
        let spparator = defaults(for: StorageKey.copySeparator) ?? ""
        return spparator.isEmpty ? " " : spparator
    }

    var newFileName: String {
        defaults(for: StorageKey.newFileName) ?? "Untitled"
    }

    var newFileExtension: NewFileExtension {
        let fileExtensionRaw = defaults(for: StorageKey.newFileExtension) ?? ""
        return NewFileExtension(rawValue: fileExtensionRaw) ?? .none
    }

    var showSubMenuForApplication: Bool {
        defaults(for: StorageKey.showSubMenuForApplication) ?? false
    }

    var showSubMenuForAction: Bool {
        defaults(for: StorageKey.showSubMenuForAction) ?? false
    }

    private func defaults<T>(for key: String) -> T? {
        if let value = object(forKey: key) as? T {
            return value
        } else {
            logger.warning("Missing key for \(key, privacy: .public), using default true value")
            return nil
        }
    }
}
