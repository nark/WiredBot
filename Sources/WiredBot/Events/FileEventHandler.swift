// WiredBot — FileEventHandler.swift
// Handles file upload events.

import Foundation
import WiredSwift

public final class FileEventHandler {

    public func handleUpload(message: P7Message, bot: BotController) {
        let path     = message.string(forField: "wired.file.path") ?? "unknown"
        let nick     = message.string(forField: "wired.user.nick") ?? "someone"
        let filename = (path as NSString).lastPathComponent

        BotLogger.info("File upload: \(filename) by \(nick)")

        let vars = ["nick": nick, "filename": filename, "path": path]
        if let match = bot.triggerEngine.matchEvent(eventType: "file_uploaded",
                                                    input: "\(filename) \(path)",
                                                    nick: nick,
                                                    variables: vars,
                                                    cooldownScope: path) {
            bot.fireEventTrigger(match)
        }
    }
}
