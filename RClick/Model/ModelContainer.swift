//
//  ModelContainer.swift
//  RClick
//
//  Created by 李旭 on 2025/10/3.
//

import Foundation
import SwiftData

// 共享 ModelContainer 配置工具类
class SharedDataManager {
    static let appGroupIdentifier = Constants.suitName

    static let sharedModelContainer: ModelContainer = {
        do {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            let storeURL = appSupport.appendingPathComponent("RClickDatabase.sqlite")

            let configuration = ModelConfiguration(
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )

            let container = try ModelContainer(
                for: PersistentPermDir.self,
                configurations: configuration
            )

            return container
        } catch {
            fatalError("Failed to create shared model container: \(error)")
        }
    }()
}
