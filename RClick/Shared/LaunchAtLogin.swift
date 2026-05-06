//
//  LaunchAtLogin.swift
//  RClick
//  from https://github.com/sindresorhus/LaunchAtLogin-Modern
//  Created by 李旭 on 2024/12/19.
//

import Foundation
import OSLog
import SwiftUI
import ServiceManagement

public enum LaunchAtLogin {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LaunchAtLogin", category: "main")
    fileprivate static let observable = Observable()

    public static var isEnabled: Bool {
        get { observable.isEnabled }
        set {
            guard newValue != observable.isEnabled else { return }
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                observable.isEnabled = SMAppService.mainApp.status == .enabled
            } catch {
                logger.error("Failed to \(newValue ? "enable" : "disable") launch at login: \(error.localizedDescription)")
                observable.isEnabled = SMAppService.mainApp.status == .enabled
            }
        }
    }

    public static var wasLaunchedAtLogin: Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        return event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}

extension LaunchAtLogin {
    @Observable
    final class Observable {
        var isEnabled: Bool = SMAppService.mainApp.status == .enabled
    }
}

extension LaunchAtLogin {
    public struct Toggle<Label: View>: View {
        @Bindable private var launchAtLogin = LaunchAtLogin.observable
        private let label: Label

        public init(@ViewBuilder label: () -> Label) {
            self.label = label()
        }

        public var body: some View {
            let _ = launchAtLogin.isEnabled
            let binding = Binding(
                get: { LaunchAtLogin.isEnabled },
                set: { LaunchAtLogin.isEnabled = $0 }
            )
            SwiftUI.Toggle(isOn: binding) { label }
        }
    }
}

extension LaunchAtLogin.Toggle<Text> {
    public init(_ titleKey: LocalizedStringKey) {
        label = Text(titleKey)
    }

    public init(_ title: some StringProtocol) {
        label = Text(title)
    }

    public init() {
        self.init("Launch at login")
    }
}
