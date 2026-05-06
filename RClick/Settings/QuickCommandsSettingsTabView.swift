import SwiftUI

struct QuickCommandsSettingsTabView: View {
    @AppLog(category: "quick-commands")
    private var logger

    @Environment(AppState.self) var appState
    let messenger = Messenger.shared

    @State private var showAddSheet = false
    @State private var editingCommand: QuickCommand?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quick Commands", tableName: nil, bundle: .main, comment: "A label displayed above the list of quick commands.")
                    .font(.title2).fontWeight(.semibold)
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.body)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Presets", tableName: nil, bundle: .main, comment: "A heading for the list of presets.")
                    .font(.caption).foregroundColor(.secondary)
                    .padding(.leading, 4)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 6) {
                    ForEach(QuickCommand.presets) { preset in
                        presetCard(preset)
                    }
                }
            }

            Divider()

            if appState.quickCommands.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "terminal")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No Quick Commands Yet", tableName: nil, bundle: .main, comment: "A message displayed when the user has no quick commands.")
                        .font(.title3).foregroundColor(.secondary)
                    Text("Add a preset above or create a custom command", tableName: nil, bundle: .main, comment: "A description of the action of adding a quick command.")
                        .font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 50)
            } else {
                List {
                    ForEach(appState.quickCommands) { cmd in
                        quickCommandRow(cmd)
                    }
                }
                .listStyle(.inset)
            }

            HStack(spacing: 4) {
                Image(systemName: "info.circle").foregroundColor(.secondary)
                Text("Commands run via /bin/bash. Use variables: {path} {name} {dir} {ext} {name_no_ext} {all}", tableName: nil, bundle: .main, comment: "A description of the format of the commands that can be run by the app.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding()
        .sheet(isPresented: $showAddSheet) {
            QuickCommandEditorView(onSave: { cmd in
                appState.addQuickCommand(cmd)
                syncToExtension()
                showAddSheet = false
            })
        }
        .sheet(item: $editingCommand) { cmd in
            QuickCommandEditorView(existing: cmd, onSave: { updated in
                appState.updateQuickCommand(updated)
                syncToExtension()
                editingCommand = nil
            })
        }
    }

    @ViewBuilder
    private func presetCard(_ preset: QuickCommand) -> some View {
        Button {
            let alreadyExists = appState.quickCommands.contains { $0.name == preset.name && $0.template == preset.template }
            guard !alreadyExists else { return }
            let cmd = QuickCommand(
                id: UUID().uuidString,
                name: preset.name,
                icon: preset.icon,
                template: preset.template,
                enabled: true,
                dangerous: preset.dangerous,
                idx: appState.quickCommands.count
            )
            appState.addQuickCommand(cmd)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: preset.icon)
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.subheadline).fontWeight(.medium)
                    Text(preset.template)
                        .font(.caption2).foregroundColor(.secondary)
                        .lineLimit(1)
                        .fontDesign(.monospaced)
                }
                Spacer()
                Image(systemName: "plus.circle")
                    .font(.body).foregroundColor(.accentColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func quickCommandRow(_ cmd: QuickCommand) -> some View {
        HStack(spacing: 10) {
            Image(systemName: cmd.icon)
                .font(.title3)
                .foregroundColor(cmd.enabled ? .accentColor : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(cmd.name).font(.body).fontWeight(.medium)
                    if cmd.dangerous {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundColor(.orange)
                    }
                }
                Text(cmd.template)
                    .font(.caption).foregroundColor(.secondary)
                    .lineLimit(1)
                    .fontDesign(.monospaced)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { cmd.enabled },
                set: { _ in
                    appState.toggleQuickCommand(id: cmd.id)
                    syncToExtension()
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            Button {
                editingCommand = cmd
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Edit"))

            Button {
                if let index = appState.quickCommands.firstIndex(of: cmd) {
                    appState.deleteQuickCommand(index: index)
                    syncToExtension()
                }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Delete"))
        }
        .padding(.vertical, 4)
    }

    private func syncToExtension() {
        messenger.sendMessage(name: "running", data: MessagePayload(action: .running, target: []))
    }
}
