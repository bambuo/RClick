//
//  SettingsWindow.swift
//  RClick
//
//  Created by 李旭 on 2024/9/25.
//

import SwiftUI

struct SettingsWindow: Scene {
    var appState: AppState
    
    @Environment(UpdateManager.self) var updateManager: UpdateManager
    
    let onAppear: () -> Void

    var body: some Scene {
        Window("Settings", id: Constants.settingsWindowID) {
            SettingsView()
                .environment(appState)
                .onAppear {
                    onAppear()
                }
                .frame(minWidth: 800, minHeight: 500)
                .sheet(isPresented: Bindable(updateManager).showUpdateSheet) {
                    UpdateView(updateManager: updateManager)
                }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 800, height: 500)
    }
    
}
