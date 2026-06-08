// SpeechSynthesizer.swift
// Text-to-speech di JARVIS tramite AVSpeechSynthesizer.
//
// Obiettivi:
//   - Voce italiana di alta qualità (Alice o altra Enhanced)
//   - Tono leggermente artificiale (pitch ridotto, rate calibrato)
//   - Pubblicazione del livello audio simulato durante il parlato
//     (il livello reale da TTS non è accessibile direttamente in macOS,
//      usiamo un'animazione sintetica sincronizzata con il testo)
//   - Callback onStart / onFinish per sincronizzare l'UI
//   - Interruzione immediata se arriva un nuovo comando

import AVFoundation
import Combine

// MARK: - VoiceConfig

/// Parametri della voce. Calibrati per suonare "artificiale ma credibile".
struct VoiceConfig {
    var rate: Float          // Velocità (AVSpeechUtteranceDefaultSpeechRate = 0.5)
    var pitch: Float         // Tono (1.0 = normale, < 1.0 = più grave)
    var volume: Float        // Volume (0.0 – 1.0)
    var preDelay: TimeInterval    // Pausa prima di parlare
    var postDelay: TimeInterval   // Pausa dopo aver parlato

    static let jarvis = VoiceConfig(
        rate: 0.52,       // Leggermente più lento del default per chiarezza
        pitch: 0.92,      // Leggermente più grave — suona più autorevole
        volume: 0.88,
        preDelay: 0.15,
        postDelay: 0.2
    )
}

// MARK: - SpeechSynthesizer

@MainActor
final class SpeechSynthesizer: NSObject, ObservableObject {

    // MARK: Published
    @Published private(set) var isSpeaking: Bool = false
    @Published private(set) var simulatedAudioLevel: Float = 0.0

    // MARK: Callbacks
    var onSpeakingStarted: (() -> Void)?
    var onSpeakingFinished: (() -> Void)?

    // MARK: Config
    let config: VoiceConfig

    // MARK: Private
    private let synthesizer = AVSpeechSynthesizer()
    private var selectedVoice: AVSpeechSynthesisVoice?
    private var audioLevelTimer: Timer?
    private var audioLevelPhase: Double = 0

    // MARK: - Init

    init(config: VoiceConfig = .jarvis) {
        self.config = config
        super.init()
        synthesizer.delegate = self
        selectedVoice = selectBestVoice()
        print("🔊 SpeechSynthesizer pronto — voce: \(selectedVoice?.name ?? "default")")
    }

    // MARK: - Voice Selection

    /// Seleziona la miglior voce italiana disponibile sul sistema.
    /// Priorità: Enhanced (neurale) > Premium > Default
    private func selectBestVoice() -> AVSpeechSynthesisVoice? {
        let italianVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("it") }

        // Log di debug — utile per sapere quali voci sono installate
        for voice in italianVoices {
            print("  🎙️ Voce disponibile: \(voice.name) [\(voice.quality.rawValue)]")
        }

        // Seleziona in ordine di preferenza
        let priorities: [AVSpeechSynthesisVoiceQuality] = [.enhanced, .default]

        for quality in priorities {
            if let voice = italianVoices.first(where: { $0.quality == quality }) {
                return voice
            }
        }

        // Fallback: qualsiasi voce italiana
        if let fallback = italianVoices.first {
            return fallback
        }

        // Ultimo fallback: voce di sistema (inglese)
        print("⚠️ Nessuna voce italiana trovata, uso il default di sistema")
        return AVSpeechSynthesisVoice(language: "it-IT")
    }

    // MARK: - Speak

    /// Legge il testo ad alta voce.
    /// Se sta già parlando, interrompe e riparte con il nuovo testo.
    func speak(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Interrompi eventuale parlato precedente
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = selectedVoice
        utterance.rate = config.rate
        utterance.pitchMultiplier = config.pitch
        utterance.volume = config.volume
        utterance.preUtteranceDelay = config.preDelay
        utterance.postUtteranceDelay = config.postDelay

        synthesizer.speak(utterance)

        print("🔊 TTS: \"\(text.prefix(60))...\"")
    }

    /// Interrompe il parlato immediatamente.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        stopAudioLevelSimulation()
    }

    // MARK: - Audio Level Simulation

    /// AVSpeechSynthesizer non espone il livello audio in real-time su macOS.
    /// Simuliamo un livello audio credibile usando una funzione sinusoidale
    /// con rumore, sincronizzata con la durata stimata del testo.
    ///
    /// In alternativa futura: usare AVAudioMix o reindirizzare TTS su AVAudioEngine
    /// per catturare il buffer e calcolarne l'RMS reale (complessità alta, rimandato).
    private func startAudioLevelSimulation(estimatedDuration: TimeInterval) {
        audioLevelPhase = 0
        let updateInterval: TimeInterval = 1.0 / 30.0  // 30fps per le animazioni

        audioLevelTimer = Timer.scheduledTimer(
            withTimeInterval: updateInterval,
            repeats: true
        ) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }

            Task { @MainActor in
                self.audioLevelPhase += updateInterval * 8.0

                // Onda composita: frequenza principale + armonica + rumore
                let primary = sin(self.audioLevelPhase) * 0.4
                let harmonic = sin(self.audioLevelPhase * 2.3) * 0.2
                let noise = Float.random(in: -0.1...0.1)

                let raw = Float(primary + harmonic) + noise
                self.simulatedAudioLevel = max(0, min(1, (raw + 0.5) * 0.8))
            }
        }
    }

    private func stopAudioLevelSimulation() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil

        withAnimation(.easeOut(duration: 0.3)) {
            simulatedAudioLevel = 0.0
        }
    }

    // MARK: - Utilities

    /// Stima la durata del parlato in secondi.
    /// Usata per calibrare la simulazione del livello audio.
    private func estimateDuration(for text: String) -> TimeInterval {
        let wordCount = text.split(separator: " ").count
        // A rate 0.52, circa 2.5 parole al secondo
        return TimeInterval(wordCount) / 2.5 + config.preDelay + config.postDelay
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechSynthesizer: AVSpeechSynthesizerDelegate {

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = true
            let duration = self.estimateDuration(for: utterance.speechString)
            self.startAudioLevelSimulation(estimatedDuration: duration)
            self.onSpeakingStarted?()
            print("▶️ TTS iniziato")
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = false
            self.stopAudioLevelSimulation()
            self.onSpeakingFinished?()
            print("✅ TTS completato")
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = false
            self.stopAudioLevelSimulation()
            print("⏹️ TTS interrotto")
        }
    }
}

// MARK: - SwiftUI Helpers

import SwiftUI

private func withAnimation<Result>(
    _ animation: Animation = .default,
    _ body: () throws -> Result
) rethrows -> Result {
    return try SwiftUI.withAnimation(animation, body)
}
