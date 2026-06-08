// RemindersFeature.swift
import EventKit
import Foundation

final class RemindersFeature {

    private let store = EKEventStore()

    // MARK: - Permission

    private func requestAccess() async -> Bool {
        if #available(macOS 14.0, *) {
            return (try? await store.requestFullAccessToReminders()) ?? false
        } else {
            return await withCheckedContinuation { cont in
                store.requestAccess(to: .reminder) { granted, _ in
                    cont.resume(returning: granted)
                }
            }
        }
    }

    // MARK: - Today

    func todayList() async -> String {
        guard await requestAccess() else {
            return "Non ho il permesso di accedere ai promemoria."
        }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return "Errore nel calcolo della data."
        }

        let pred = store.predicateForIncompleteReminders(
            withDueDateStarting: start,
            ending: end,
            calendars: nil
        )

        let reminders = await fetchReminders(matching: pred)

        if reminders.isEmpty {
            return "Non hai promemoria per oggi."
        }

        let titles = reminders.compactMap { $0.title }.filter { !$0.isEmpty }
        if titles.isEmpty { return "Hai \(reminders.count) promemoria per oggi, ma senza titolo." }

        let list = titles.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: ". ")

        return "Oggi hai \(titles.count) \(titles.count == 1 ? "promemoria" : "promemoria"): \(list)."
    }

    // MARK: - Count

    func count(scope: Intent.ReminderScope) async -> String {
        guard await requestAccess() else {
            return "Non ho il permesso di accedere ai promemoria."
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let start: Date
        let end: Date
        let label: String

        switch scope {
        case .tomorrow:
            guard let t = calendar.date(byAdding: .day, value: 1, to: today),
                  let e = calendar.date(byAdding: .day, value: 2, to: today) else {
                return "Errore nel calcolo della data."
            }
            start = t; end = e; label = "domani"

        case .thisWeek:
            guard let e = calendar.date(byAdding: .day, value: 7, to: today) else {
                return "Errore nel calcolo della data."
            }
            start = today; end = e; label = "nei prossimi 7 giorni"

        case .future:
            guard let e = calendar.date(byAdding: .year, value: 1, to: today) else {
                return "Errore nel calcolo della data."
            }
            start = today; end = e; label = "in programma"
        }

        let pred = store.predicateForIncompleteReminders(
            withDueDateStarting: start,
            ending: end,
            calendars: nil
        )

        let reminders = await fetchReminders(matching: pred)
        let n = reminders.count

        if n == 0 { return "Non hai promemoria \(label)." }
        return "Hai \(n) \(n == 1 ? "promemoria" : "promemoria") \(label)."
    }

    // MARK: - Private

    private func fetchReminders(matching pred: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { cont in
            store.fetchReminders(matching: pred) { results in
                cont.resume(returning: results ?? [])
            }
        }
    }
}
