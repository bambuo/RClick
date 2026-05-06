//
//  ActionSettingsView.swift
//  RClick
//
//  Created by 李旭 on 2024/4/9.
//

import SwiftUI

struct ActionSettingsTabView: View {
    @Environment(AppState.self) var appState
    
    let messenger = Messenger.shared

    var body: some View {
        @Bindable var appState = appState
        VStack {
            HStack {
                
                Spacer()
                Button {
                    appState.resetActionItems()
                } label: {
                    Label("Reset", systemImage: "arrow.triangle.2.circlepath")
                        .font(.body)
                }
            }

            List {
                ForEach($appState.actions) { $item in
                    HStack {
                        Image(systemName: item.icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                        Text(LocalizedStringKey(item.name)).font(.title2)
                        Spacer()
                        Toggle("", isOn: $item.enabled)
                            .onChange(of: item.enabled) {
                                appState.toggleActionItem()
                                messenger.sendMessage(name: "running", data: MessagePayload(action: .running, target: []))
                            }
                            .toggleStyle(.switch)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                }
            }
        }
    }
}
