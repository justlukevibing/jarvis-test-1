// AppState.swift
// Stato globale condiviso dell'applicazione JARVIS
// Implementa il pattern singleton osservabile via SwiftUI

import Foundation
import SwiftUI
import Combine

// MARK: - AssistantState

/// Rappresenta tutti i possibili stati dell'assistente
/// Ogni stato corrisponde a un'animazione e comportamento visivo diverso
enum AssistantState: Equatable {
    case idle           // In attesa, nessuna attività
    case listening      // STT attivo, microfono aperto
    case processing     // AI sta elaborando la richiesta
    case speaking       // TTS sta leggendo la risposta
    case error(String)  // Errore con messaggio

    /// Descrizione leggibile (utile per debug e accessibility)
    var description: String {
        switch self {
        case .idle:           return "In attesa"
        case .listening:      return "In ascolto..."
        case .processing:     return "Elaboro..."
        case .speaking:       return "Rispondo..."
        case .error(let msg): return "Errore: \(msg)"
        }
    }

    /// Colore accent associato allo stato
    var accentColor: Color {
        switch self {
        case .idle:       return Color(red: 0.0, green: 0.8, blue: 1.0)   // Ciano
        case .listening:  return Color(red: 0.0, green: 1.0, blue: 0.5)   // Verde
        case .processing: return Color(red: 1.0, green: 0.6, blue: 0.0)   // Arancio
        case .speaking:   return Color(red: 0.4, green: 0.6, blue: 1.0)   // Blu
        case .error:      return Color(red: 1.0, green: 0.2, blue: 0.2)   // Rosso
        }
    }

    // Necessario per Equatable con associated value
    static func == (lhs: AssistantState, rhs: AssistantState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.listening, .listening),
             (.processing, .processing),
             (.speaking, .speaking):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - AppState

/// Singleton che funge da "source of truth" per tutta l'applicazione.
/// Viene iniettato nelle view tramite @ObservedObject o @EnvironmentObject.
@MainActor
final class AppState: ObservableObject {

    // MARK: Singleton
    static let shared = AppState()
    private init() {}

    // MARK: UI State

    /// Controlla se il popup è visibile
    @Published var isPopupVisible: Bool = false

    /// Stato corrente dell'assistente
    @Published var assistantState: AssistantState = .idle

    /// Ultimo messaggio dell'utente riconosciuto via STT
    @Published var lastUserMessage: String = ""

    /// Ultima risposta dell'assistente
    @Published var lastAssistantResponse: String = ""

    /// Intensità dell'onda sonora (0.0 - 1.0), aggiornata in real-time
    @Published var audioLevel: Float = 0.0

    // MARK: App Info

    let version = "0.1.0"
    let buildDate = "2025"

    // MARK: Helpers

    /// Transizione sicura verso un nuovo stato
    func transition(to newState: AssistantState) {
        withAnimation(.easeInOut(duration: 0.3)) {
            assistantState = newState
        }
    }

    /// Reset completo allo stato idle
    func reset() {
        withAnimation {
            assistantState = .idle
            audioLevel = 0.0
            lastUserMessage = ""
            lastAssistantResponse = ""
        }
    }
}
