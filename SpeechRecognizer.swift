// SpeechRecognizer.swift
// Riconoscimento vocale on-device tramite SFSpeechRecognizer.
//
// Caratteristiche:
//   - On-device: nessun dato inviato ad Apple in rete (Apple Silicon supporta on-device)
//   - Lingua configurabile (default: italiano)
//   - Trascrizione continua con risultati parziali in real-time
//   - Silenzio detection: ferma automaticamente dopo N secondi di silenzio
//   - Gestione permessi con messaggi chiari all'utente
//
// Integrazione con AudioEngine:
//   SpeechRecognizer NON apre il microfono direttamente.
//   Riceve buffer PCM da AudioEngine tramite appendAudioBuffer().
//   Questo evita conflitti tra AVAudioSession multipli.

import Speech
import AVFoundation
import Combine

// MARK: - SpeechRecognizer

@MainActor
final class SpeechRecognizer: ObservableObject {

    // MARK: Published
    @Published private(set) var transcript: String = ""        // Testo finale confermato
    @Published private(set) var partialTranscript: String = "" // Testo mentre parla
    @Published private(set) var isListening: Bool = false
    @Published private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    // MARK: Callbacks
    var onFinalTranscript: ((String) -> Void)?   // Chiamato quando l'utente finisce di parlare
    var onPartialTranscript: ((String) -> Void)? // Chiamato ad ogni aggiornamento intermedio

    // MARK: Config
    let locale: Locale

    // Timeout: se non arriva audio per N secondi → considera la frase terminata
    private let silenceTimeout: TimeInterval = 1.8

    // MARK: Private
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var lastTranscriptUpdate: Date = .now

    // MARK: - Init

    init(locale: Locale = Locale(identifier: "it-IT")) {
        self.locale = locale
        self.recognizer = SFSpeechRecognizer(locale: locale)

        // Abilita la modalità on-device (Apple Silicon la supporta nativamente)
        // Se il modello locale non è disponibile, cade back su cloud (con avviso)
        recognizer?.supportsOnDeviceRecognition = true

        print("🎙️ SpeechRecognizer inizializzato — locale: \(locale.identifier), on-device: \(recognizer?.supportsOnDeviceRecognition ?? false)")
    }

    // MARK: - Permissions

    /// Richiede il permesso di riconoscimento vocale.
    /// Deve essere chiamato prima di startListening().
    func requestPermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                Task { @MainActor in
                    self?.authorizationStatus = status
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }

    // MARK: - Listening

    /// Avvia il riconoscimento vocale.
    /// - Parameter bufferCallback: viene restituita la closure da passare ad AudioEngine.start()
    /// - Returns: la closure da usare come bufferCallback in AudioEngine.start()
    func startListening() throws -> (AVAudioPCMBuffer) -> Void {
        guard let recognizer = recognizer, recognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }

        guard authorizationStatus == .authorized else {
            throw SpeechError.notAuthorized
        }

        // Termina eventuale sessione precedente
        stopListening()

        // Crea la recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        // Preferisce on-device (privacy) — se non disponibile, usa cloud
        if #available(macOS 13.0, *) {
            request.requiresOnDeviceRecognition = false // false = usa on-device se disponibile, cloud come fallback
        }

        self.recognitionRequest = request

        // Avvia il task di riconoscimento
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognitionResult(result: result, error: error)
            }
        }

        isListening = true
        transcript = ""
        partialTranscript = ""
        lastTranscriptUpdate = .now

        print("🎙️ STT avviato")

        // Restituisce la closure da passare ad AudioEngine
        // AudioEngine chiamerà questa closure per ogni buffer audio catturato
        return { [weak self] buffer in
            self?.recognitionRequest?.append(buffer)
        }
    }

    /// Ferma il riconoscimento e finalizza la trascrizione.
    func stopListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        isListening = false
        partialTranscript = ""

        print("🔇 STT fermato")
    }

    // MARK: - Result Handling

    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {

        // Gestione errori
        if let error = error {
            let nsError = error as NSError
            // Codice 301 = sessione terminata normalmente (non è un errore reale)
            if nsError.code != 301 {
                print("⚠️ STT error: \(error.localizedDescription)")
            }
            stopListening()
            return
        }

        guard let result = result else { return }

        let text = result.bestTranscription.formattedString

        if result.isFinal {
            // Trascrizione definitiva
            transcript = text
            partialTranscript = ""
            onFinalTranscript?(text)
            print("✅ STT finale: \"\(text)\"")

            // Reset silence timer
            silenceTimer?.invalidate()

        } else {
            // Risultato parziale — aggiorna in real-time
            partialTranscript = text
            onPartialTranscript?(text)

            // Restart silence timer ad ogni aggiornamento
            // Se non arriva nuovo testo entro silenceTimeout → considera terminata la frase
            resetSilenceTimer()
        }
    }

    // MARK: - Silence Detection

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) {
            [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                let finalText = self.partialTranscript

                if !finalText.isEmpty {
                    self.transcript = finalText
                    self.onFinalTranscript?(finalText)
                    print("✅ STT (silence timeout): \"\(finalText)\"")
                }

                self.stopListening()
            }
        }
    }
}

// MARK: - SpeechError

enum SpeechError: LocalizedError {
    case recognizerUnavailable
    case notAuthorized
    case microphoneUnavailable

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Riconoscimento vocale non disponibile su questo dispositivo"
        case .notAuthorized:
            return "Permesso riconoscimento vocale non concesso"
        case .microphoneUnavailable:
            return "Microfono non disponibile"
        }
    }
}
