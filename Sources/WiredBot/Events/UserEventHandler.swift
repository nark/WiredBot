// WiredBot — UserEventHandler.swift
// Handles wired.chat.user_* messages.

import Foundation
import WiredSwift

public final class UserEventHandler {

    public func handleUserList(message: P7Message, bot: BotController) {
        guard
            let chatID = message.uint32(forField: "wired.chat.id"),
            let userID = message.uint32(forField: "wired.user.id"),
            let nick   = message.string(forField: "wired.user.nick")
        else { return }
        bot.setNick(nick, forUser: userID, in: chatID)
    }

    public func handleUserJoin(message: P7Message, bot: BotController, connection: Connection) {
        guard
            let chatID = message.uint32(forField: "wired.chat.id"),
            let userID = message.uint32(forField: "wired.user.id"),
            let nick   = message.string(forField: "wired.user.nick")
        else { return }

        bot.setNick(nick, forUser: userID, in: chatID)

        // Don't greet ourselves
        guard nick != bot.config.identity.nick else { return }
        BotLogger.info("User '\(nick)' joined channel \(chatID)")

        let vars = ["nick": nick, "chatID": "\(chatID)", "userID": "\(userID)"]
        if let match = bot.triggerEngine.matchEvent(eventType: "user_join",
                                                    input: nick,
                                                    nick: nick,
                                                    chatID: chatID,
                                                    variables: vars) {
            bot.fireEventTrigger(match)
        }
    }

    public func handleUserLeave(message: P7Message, bot: BotController, connection: Connection) {
        guard
            let chatID = message.uint32(forField: "wired.chat.id"),
            let userID = message.uint32(forField: "wired.user.id")
        else { return }

        let nick = bot.nick(ofUser: userID, in: chatID) ?? "User\(userID)"
        BotLogger.info("User '\(nick)' left channel \(chatID)")
        bot.removeUser(userID, from: chatID)

        guard nick != bot.config.identity.nick else { return }
        let vars = ["nick": nick, "chatID": "\(chatID)", "userID": "\(userID)"]
        if let match = bot.triggerEngine.matchEvent(eventType: "user_leave",
                                                    input: nick,
                                                    nick: nick,
                                                    chatID: chatID,
                                                    variables: vars) {
            bot.fireEventTrigger(match)
        }
    }

    public func handleUserStatus(message: P7Message, bot: BotController) {
        guard
            let chatID = message.uint32(forField: "wired.chat.id"),
            let userID = message.uint32(forField: "wired.user.id")
        else { return }
        let oldNick = bot.nick(ofUser: userID, in: chatID) ?? "User\(userID)"
        let nick = message.string(forField: "wired.user.nick") ?? oldNick
        let status = message.string(forField: "wired.user.status") ?? ""
        bot.setNick(nick, forUser: userID, in: chatID)

        guard nick != bot.config.identity.nick else { return }

        let vars = [
            "nick": nick,
            "oldNick": oldNick,
            "status": status,
            "chatID": "\(chatID)",
            "userID": "\(userID)"
        ]

        if oldNick != nick,
           let match = bot.triggerEngine.matchEvent(eventType: "user_nick_changed",
                                                    input: "\(oldNick) \(nick)",
                                                    nick: nick,
                                                    chatID: chatID,
                                                    variables: vars) {
            bot.fireEventTrigger(match)
        }

        if let match = bot.triggerEngine.matchEvent(eventType: "user_status_changed",
                                                    input: status.isEmpty ? nick : "\(nick) \(status)",
                                                    nick: nick,
                                                    chatID: chatID,
                                                    variables: vars) {
            bot.fireEventTrigger(match)
        }
    }
}
