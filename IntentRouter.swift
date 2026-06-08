// IntentRouter.swift
import Foundation

@MainActor
final class IntentRouter {

    private let parser = IntentParser()
    private let clock = ClockFeature()
    private let reminders = RemindersFeature()

    func handle(_ text: String) async -> String {
        let intent = parser.parse(text)

        switch intent {
        case .currentTime:
            return clock.currentTime()
        case .currentDate:
            return clock.currentDate()
        case .remindersToday:
            return await reminders.todayList()
        case .remindersCount(let scope):
            return await reminders.count(scope: scope)
        case .stopListening:
            return "__STOP__"
        case .greeting:
            return greetingResponse()
        case .systemCheck:
            return "Sì, ti sento perfettamente. Sono operativo."
        case .freeform:
            // Fase 6: Ollama
            return "Non ho ancora capito come aiutarti con questa richiesta. Le funzioni disponibili sono: ora, data e promemoria."
        }
    }

    private func greetingResponse() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Buongiorno. Come posso aiutarti?"
        case 12..<17: return "Buon pomeriggio. Dimmi pure."
        case 17..<21: return "Buona sera. Sono in ascolto."
        default:       return "Ciao. Sono qui."
        }
    }
}
