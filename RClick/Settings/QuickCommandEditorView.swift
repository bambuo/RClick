import SwiftUI

struct QuickCommandEditorView: View {
    var existing: QuickCommand?
    var onSave: (QuickCommand) -> Void

    @State private var name: String = ""
    @State private var icon: String = "terminal"
    @State private var template: String = ""
    @State private var isDangerous: Bool = false

    @Environment(\.dismiss) var dismiss

    private let iconOptions = [
        ("terminal", "Terminal"),
        ("hammer", "Hammer"),
        ("shield.slash", "Shield"),
        ("signature", "Signature"),
        ("ellipsis.curlybraces", "Info"),
        ("rectangle.compress.vertical", "Compress"),
        ("archivebox", "Archive"),
        ("wrench", "Wrench"),
        ("gearshape", "Gear"),
        ("play", "Play"),
        ("scissors", "Scissors"),
        ("arrow.triangle.merge", "Merge"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text(existing == nil
                ? String(localized: "Add Quick Command", comment: "A label displayed above a form to add a new quick command.")
                : String(localized: "Edit Quick Command", comment: "A label displayed above the Quick Command editor."))
                .font(.title2).fontWeight(.bold)

            Form {
                TextField(String(localized: "Name"), text: $name, prompt: Text(String(localized: "e.g. Remove Quarantine", comment: "A placeholder text for the name of a quick command.")))
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Icon").font(.caption).foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        ForEach(iconOptions.prefix(8), id: \.0) { (key, label) in
                            iconButton(key: key)
                        }
                    }
                    HStack(spacing: 4) {
                        ForEach(iconOptions.suffix(from: 8), id: \.0) { (key, label) in
                            iconButton(key: key)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Command Template", comment: "A label displayed above the command template field.")
                        .font(.caption).foregroundColor(.secondary)
                    TextEditor(text: $template)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 50)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    Text("Available: {path} {name} {dir} {ext} {name_no_ext} {all}", comment: "A list of placeholders that can be used in a quick command template.")
                        .font(.caption2).foregroundColor(.blue)
                }

                Toggle(String(localized: "Mark as dangerous", comment: "A toggle to mark a quick command as dangerous."), isOn: $isDangerous)
            }
            .formStyle(.grouped)

            GroupBox(label: Text("Preview", comment: "A label displayed in a group box that shows the preview of a quick command.").font(.caption)) {
                Text(resolvePreview())
                    .font(.system(.callout, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    let cmd = QuickCommand(
                        id: existing?.id ?? UUID().uuidString,
                        name: name,
                        icon: icon,
                        template: template,
                        enabled: existing?.enabled ?? true,
                        dangerous: isDangerous,
                        idx: existing?.idx ?? 0
                    )
                    onSave(cmd)
                }
                .disabled(name.isEmpty || template.isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 500, height: 420)
        .onAppear {
            if let cmd = existing {
                name = cmd.name
                icon = cmd.icon
                template = cmd.template
                isDangerous = cmd.dangerous
            }
        }
    }

    private func iconButton(key: String) -> some View {
        Button {
            icon = key
        } label: {
            Image(systemName: key)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .background(icon == key
            ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.2))
            : RoundedRectangle(cornerRadius: 6).fill(Color.clear)
        )
    }

    private func resolvePreview() -> String {
        guard !template.isEmpty else {
            return "command \"{path}\""
        }
        return template
            .replacing("{path}", with: "/Users/me/Download/App.app")
            .replacing("{name}", with: "App.app")
            .replacing("{dir}", with: "/Users/me/Download")
            .replacing("{ext}", with: ".app")
            .replacing("{name_no_ext}", with: "App")
            .replacing("{all}", with: "\"/Users/me/file1\" \"/Users/me/file2\"")
    }
}
