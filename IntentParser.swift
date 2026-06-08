// IntentParser.swift
// Classifica il testo in ingresso in un Intent riconoscibile.
//
// Approccio: keyword matching su testo normalizzato.
// - Nessuna rete, nessun modello, latenza zero.
// - NaturalLanguage framework per rimozione diacritici e lowercasing.
// - In Fase 6 Ollama gestirà i casi non riconosciuti (Intent.freeform).
//
// Aggiungere nuovi intenti: basta aggiungere un caso all'enum
// e le keywords corrispondenti nel dizionario.

import Foundation
import NaturalLanguage

// MARK: - Intent

/// Tutti i comandi che JARVIS sa riconoscere.
enum Intent: Equatable {
    case currentTime            // "che ore sono"
    case currentDate            // "che giorno è oggi"
    case remindersToday         // "cosa devo fare oggi"
    case remindersCount(scope: ReminderScope)  // "quanti promemoria ho domani"
    case stopListening          // "stop" / "fermati" / "chiudi"
    case greeting               // "ciao" / "salve"
    case systemCheck            // "funziona" / "mi senti" / "test"
    case freeform(text: String) // tutto il resto → Fase 6: Ollama

    enum ReminderScope: Equatable {
        case tomorrow
        case thisWeek
        case future     // generico "futuri"
    }
}

// MARK: - IntentParser

/// Analizza il testo e restituisce l'Intent più probabile.
struct IntentParser {

    // MARK: - Public API

    /// Punto di ingresso principale.
    /// - Parameter text: trascrizione grezza dallo STT
    /// - Returns: Intent classificato
    func parse(_ text: String) -> Intent {
        let normalized = normalize(text)
        return classify(normalized, original: text)
    }

    // MARK: - Normalization

    /// Normalizza il testo per il matching:
    /// lowercase + rimozione diacritici + trim whitespace.
    ///
    /// "Che Óre Sono?" → "che ore sono"
    /// Questo permette al matching di funzionare indipendentemente
    /// da accenti, maiuscole e punteggiatura dello STT.
    private func normalize(_ text: String) -> String {
        text
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Classification

    private func classify(_ n: String, original: String) -> Intent {

        // ── Stop / chiudi ──
        let stopKeywords = ["stop", "fermati", "chiudi", "esci", "basta", "silenzio"]
        if containsAny(n, keywords: stopKeywords) { return .stopListening }

        // ── Saluto ──
        let greetingKeywords = ["ciao", "salve", "buongiorno", "buonasera", "buon pomeriggio", "buonanotte"]
        if containsAny(n, keywords: greetingKeywords) { return .greeting }

        // ── Test sistema ──
        let testKeywords = ["mi senti", "funziona", "test", "prova", "sei li", "ci sei"]
        if containsAny(n, keywords: testKeywords) { return .systemCheck }

        // ── Data ──
        // Prima controlliamo "giorno" / "data" perché "ora" potrebbe apparire in "ancora"
        let dateKeywords = ["che giorno", "giorno e oggi", "giorno oggi",
                            "che data", "data di oggi", "quanti ne abbiamo"]
        if containsAny(n, keywords: dateKeywords) { return .currentDate }

        // ── Ora ──
        let timeKeywords = ["che ore", "che ora", "dimmi l ora", "dimmi le ore",
                            "ora e", "ore sono", "ora sono", "orario"]
        if containsAny(n, keywords: timeKeywords) { return .currentTime }

        // ── Promemoria: conteggio futuro ──
        // Deve venire PRIMA di remindersToday per evitare conflitti
        if containsAny(n, keywords: ["domani"]) &&
           containsAny(n, keywords: ["promemoria", "devo fare", "ricordami", "appuntament"]) {
            return .remindersCount(scope: .tomorrow)
        }

        if containsAny(n, keywords: ["settimana", "questa settimana", "nei prossimi giorni"]) &&
           containsAny(n, keywords: ["promemoria", "devo fare", "appuntament"]) {
            return .remindersCount(scope: .thisWeek)
        }

        let futureCountKeywords = ["quanti promemoria", "quante cose devo",
                                   "quanti appuntamenti", "promemoria futuri",
                                   "promemoria ho in totale"]
        if containsAny(n, keywords: futureCountKeywords) {
            return .remindersCount(scope: .future)
        }

        // ── Promemoria: oggi ──
        let remindersTodayKeywords = [
            "cosa devo fare", "promemoria di oggi", "promemoria oggi",
            "cosa ho oggi", "impegni di oggi", "impegni oggi",
            "cosa ho in agenda", "agenda di oggi", "agenda oggi",
            "appuntamenti di oggi", "appuntamenti oggi", "to do"
        ]
        if containsAny(n, keywords: remindersTodayKeywords) { return .remindersToday }

        // ── Fallback: freeform ──
        // Testo non riconosciuto → in Fase 6 verrà gestito da Ollama
        return .freeform(text: original)
    }

    // MARK: - Helpers

    /// Controlla se il testo normalizzato contiene almeno una delle keywords.
    private func containsAny(_ text: String, keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }
}
