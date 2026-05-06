//
//  Messenger.swift
//  RClick
//
//  Created by 李旭 on 2024/4/9.
//

import AppKit
import Foundation

enum MessageAction: String, Codable {
    case openApp = "open"
    case performAction = "actioning"
    case createFile = "Create File"
    case openCommonDirs = "common-dirs"
    case heartbeat = "heartbeat"
    case runQuickCommand = "quick-command"
    case running = "running"
    case quit = "quit"
}

struct MessagePayload: Codable {
    var action: String = ""
    var target: [String] = []
    var rid: String = ""
    var trigger: String = ""

    init() {}

    init(action: MessageAction, target: [String] = [], rid: String = "", trigger: String = "") {
        self.action = action.rawValue
        self.target = target
        self.rid = rid
        self.trigger = trigger
    }

    var messageAction: MessageAction? {
        MessageAction(rawValue: action)
    }

    public var description: String {
        return "MessagePayload(action: \(action), target: \(target), rid:\(rid), trigger: \(trigger))"
    }
}

class Messenger {
    static let shared = Messenger()

    @AppLog(category: "messenger")
    private var logger

    let center: DistributedNotificationCenter = .default()
    var messageHandlers: [String: (_ payload: MessagePayload) -> Void] = [:]

    func sendMessage(name: String, data: MessagePayload) {
        guard let message = createMessageData(messagePayload: data) else {
            logger.error("Failed to create message data for \(name)")
            return
        }
        logger.warning("start sendMessage ... to \(name), payload: \(data.description)")
        center.postNotificationName(NSNotification.Name(name), object: message, userInfo: nil, deliverImmediately: true)
        logger.info("sendMessage posted: \(name)")
    }

    func createMessageData(messagePayload: MessagePayload) -> String? {
        do {
            let data = try JSONEncoder().encode(messagePayload)
            guard let string = String(data: data, encoding: .utf8) else {
                logger.warning("Failed to convert encoded data to UTF-8 string")
                return nil
            }
            return string
        } catch {
            logger.error("Failed to encode MessagePayload: \(error)")
            return nil
        }
    }

    func reconstructEntry(messagePayload: String) -> MessagePayload {
        guard let jsonData = messagePayload.data(using: .utf8) else {
            logger.warning("Invalid UTF-8 data in message payload")
            return MessagePayload()
        }
        do {
            return try JSONDecoder().decode(MessagePayload.self, from: jsonData)
        } catch {
            logger.warning("Failed to decode MessagePayload: \(error)")
            return MessagePayload()
        }
    }


    func on(name: String, handler: @escaping (MessagePayload) -> Void) {
        center.addObserver(self, selector: #selector(receivedMessage(_:)), name: NSNotification.Name(name), object: nil)
        messageHandlers.updateValue(handler, forKey: name)
    }

    @objc func receivedMessage(_ notification: NSNotification) {
        guard let messageString = notification.object as? String else {
            logger.warning("Received notification with unexpected object type: \(String(describing: notification.object))")
            return
        }
        logger.info("receivedMessage: name=\(notification.name.rawValue), object=\(messageString)")
        let payload = reconstructEntry(messagePayload: messageString)
        if let handler = messageHandlers[notification.name.rawValue] {
            handler(payload)
        } else {
            logger.warning("there no handler\(notification.name.rawValue)")
        }
    }
}
