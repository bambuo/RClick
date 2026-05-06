//
//  CommonDirsSettingTabView.swift
//  RClick
//
//  Created by 李旭 on 2024/4/10.
//

import SwiftUI

struct CommonDirsSettingTabView: View {
    @AppLog(category: "settings-general")
    private var logger
    
    @Environment(AppState.self) var appState
    
    @State private var showCommonDirImporter = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Section {
                List {
                    ForEach(appState.commonDirs) { item in
                        HStack {
                            Image(systemName: "folder")
                            Text(verbatim: item.url.path)
                            Spacer()
                            Button {
                                removeCommonDir(item)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Common Folders").font(.title3).fontWeight(.semibold)
                    Spacer()
                    Button {
                        showCommonDirImporter = true
                    } label: { Label("Add", systemImage: "folder.badge.plus") }
                }
            } footer: {
                Text("Quick access to frequently used folders")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .fileImporter(
                isPresented: $showCommonDirImporter,
                allowedContentTypes: [.directory],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                    case .success(let urls):
                        if let url = urls.first {
                            let commonDir = CommonDir(id: UUID().uuidString, name: url.lastPathComponent, url: url, icon: "folder")
                            if !appState.commonDirs.contains(where: { $0.url == commonDir.url }) {
                                appState.commonDirs.append(commonDir)
                                try? appState.saveCommonDir()
                            }
                        }
                    case .failure(let error):
                        logger.error("Failed to select common folder: \(error.localizedDescription)")
                }
            }
        }
    }

    @MainActor private func removeCommonDir(_ item: CommonDir) {
        if let index = appState.commonDirs.firstIndex(of: item) {
            appState.commonDirs.remove(at: index)
            try? appState.saveCommonDir()
        }
    }
}
