//
//  RelativeTime.swift
//  Puck
//
//  Sidebar/tab timestamps. Port of chat-web's relative-time.ts, brought over
//  with the chat UI (2026-08-15) rather than reimplemented -- its rules are
//  the ones the sidebar was designed around.
//
//  Deliberately coarser than RelativeDateTimeFormatter: this is a glanceable
//  hint next to a session title, so "12분" beats "12 minutes ago", and
//  anything older than a week collapses to a date.
//
//  `now` is injected so it is testable without faking the clock -- the same
//  reason the TS version took it as a parameter.
//

import Foundation

enum RelativeTime {
    static func short(since date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let seconds = now.timeIntervalSince(date)
        // A clock that moved backwards (NTP correction, timezone edit) must
        // not render a negative age.
        guard seconds >= 0 else { return "방금" }

        let minutes = Int(seconds / 60)
        if minutes < 1 { return "방금" }
        if minutes < 60 { return "\(minutes)분" }

        let hours = minutes / 60
        if hours < 24 { return "\(hours)시간" }

        let days = hours / 24
        if days == 1 { return "어제" }
        if days < 7 { return "\(days)일" }

        let components = Calendar.current.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day else { return "" }
        return "\(month)월 \(day)일"
    }
}
