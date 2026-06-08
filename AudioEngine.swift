// AudioEngine.swift
// Motore audio centrale di JARVIS.
//
// Responsabilità:
//   1. Aprire il microfono tramite AVAudioEngine
//   2. Misurare il livello RMS frame-by-frame (per animare l'orb)
//   3. Fornire il buffer audio raw a SpeechRecognizer (per STT)
//
// Architettura: un solo AVAudioEngine, due consumatori sullo stesso tap.
// Questo evita conflitti tra AVAudioSession multipli.
//
// Flusso:
//   AVAudioEngine (inputNode)
//       └── installTap(onBus:)
//             ├── → RMS calculation → AppState.audioLevel
//             └── → SFSpeechAudioBufferRecognitionRequest

import AVFoundation
import Combine

// MARK: - AudioEngine

@MainActor
final class AudioEngine: ObservableObject {

    // MARK: Published
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var currentLevel: Float = 0.0  // 0.0 – 1.0 normalizzato

    // MARK: Private
    private let engine = AVAudioEngine()
    private var bufferCallback: ((AVAudioPCMBuffer) -> Void)?

    // Parametri RMS
    private let rmsSmoothing: Float = 0.15   // Fattore di smoothing (0=nessuno, 1=istantaneo)
    private var smoothedRMS: Float = 0.0

    // Formato audio ottimale per STT su Apple Silicon
    // SFSpeechRecognizer preferisce 16kHz mono — lo impostiamo esplicitamente
    private let preferredSampleRate: Double = 16_000
    private let preferredChannelCount: AVAudioChannelCount = 1

    // MARK: - Init

    init() {}

    // MARK: - Public API

    /// Avvia il motore audio e apre il microfono.
    /// - Parameter bufferCallback: closure chiamata per ogni buffer audio.
    ///   Viene usata da SpeechRecognizer per alimentare SFSpeechAudioBufferRecognitionRequest.
    func start(bufferCallback: @escaping (AVAudioPCMBuffer) -> Void) throws {
        guard !isRunning else { return }

        self.bufferCallback = bufferCallback

        let inputNode = engine.inputNode

        // Formato nativo del microfono (es. 48kHz stereo su MacBook)
        let nativeFormat = inputNode.outputFormat(forBus: 0)

        // Formato target per STT — mono, 16kHz
        // AVAudioEngine gestisce internamente il resampling se necessario
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: preferredSampleRate,
            channels: preferredChannelCount,
            interleaved: false
        ) else {
            throw AudioEngineError.formatCreationFailed
        }

        // Installa il tap sul bus di input
        // bufferSize: 4096 sample ≈ 85ms a 48kHz — abbastanza reattivo, non troppo frequente
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) {
            [weak self] (buffer, _) in

            guard let self = self else { return }

            // 1. Calcola RMS sul buffer nativo (qualsiasi sample rate)
            let rms = self.calculateRMS(buffer: buffer)

            // 2. Aggiorna il livello UI sul main thread con smoothing
            Task { @MainActor in
                self.updateLevel(rms: rms)
            }

            // 3. Converti al formato target e passa a SpeechRecognizer
            if let convertedBuffer = self.convert(buffer: buffer,
                                                   from: nativeFormat,
                                                   to: targetFormat) {
                self.bufferCallback?(convertedBuffer)
            }
        }

        // Avvia il motore
        engine.prepare()
        try engine.start()

        isRunning = true
        print("✅ AudioEngine avviato — formato: \(targetFormat)")
    }

    /// Ferma il motore e rimuove il tap.
    func stop() {
        guard isRunning else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        isRunning = false
        currentLevel = 0.0
        smoothedRMS = 0.0

        print("🔇 AudioEngine fermato")
    }

    // MARK: - RMS Calculation

    /// Calcola il Root Mean Square di un buffer PCM float32.
    /// RMS è la misura corretta del livello percepito (non il picco).
    private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sum: Float = 0.0

        // Media RMS su tutti i canali (di solito 1 o 2)
        for channel in 0..<channelCount {
            let data = channelData[channel]
            for frame in 0..<frameLength {
                let sample = data[frame]
                sum += sample * sample
            }
        }

        let meanSquare = sum / Float(frameLength * channelCount)
        return sqrt(meanSquare)
    }

    /// Aggiorna il livello pubblicato con smoothing esponenziale.
    /// Senza smoothing il valore sarebbe troppo "nervoso" per le animazioni.
    private func updateLevel(rms: Float) {
        // Smoothing: levata rapida, discesa più lenta (comportamento naturale del VU meter)
        let attack:  Float = rms > smoothedRMS ? 0.6 : 0.08
        smoothedRMS = smoothedRMS + (rms - smoothedRMS) * attack

        // Normalizza in 0..1 con scaling logaritmico (il volume umano è logaritmico)
        // -60dB = 0, 0dB = 1
        let db = 20 * log10(max(smoothedRMS, 1e-7))
        let normalized = max(0, min(1, (db + 60) / 60))

        currentLevel = normalized
    }

    // MARK: - Format Conversion

    /// Converte un buffer da un formato a un altro tramite AVAudioConverter.
    /// Necessario per adattare il formato nativo del microfono a quello richiesto da STT.
    private func convert(
        buffer: AVAudioPCMBuffer,
        from sourceFormat: AVAudioFormat,
        to targetFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {

        // Se i formati coincidono, nessuna conversione necessaria
        if sourceFormat.sampleRate == targetFormat.sampleRate &&
           sourceFormat.channelCount == targetFormat.channelCount {
            return buffer
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            return nil
        }

        // Calcola il numero di frame nel buffer convertito
        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let targetFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: targetFrameCapacity
        ) else { return nil }

        var error: NSError?
        var sourceConsumed = false

        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if sourceConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            sourceConsumed = true
            return buffer
        }

        if let error = error {
            print("⚠️ Conversione audio fallita: \(error.localizedDescription)")
            return nil
        }

        return outputBuffer
    }
}

// MARK: - AudioEngineError

enum AudioEngineError: LocalizedError {
    case formatCreationFailed
    case microphonePermissionDenied
    case engineStartFailed(Error)

    var errorDescription: String? {
        switch self {
        case .formatCreationFailed:
            return "Impossibile creare il formato audio"
        case .microphonePermissionDenied:
            return "Permesso microfono negato"
        case .engineStartFailed(let e):
            return "Motore audio non avviato: \(e.localizedDescription)"
        }
    }
}
