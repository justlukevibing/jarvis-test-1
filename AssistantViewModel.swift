// AssistantViewModel.swift — Fase 4
import Foundation
import AVFoundation
import Combine

@MainActor
final class AssistantViewModel: ObservableObject {

    private let appState: AppState
    private let audioEngine: AudioEngine
    private let speechRecognizer: SpeechRecognizer
    private let speechSynthesizer: SpeechSynthesizer
    private let router = IntentRouter()

    private var cancellables = Set<AnyCancellable>()
    private var isInitialized = false
    private var permissionsGranted = false

    init(appState: AppState = .shared) {
        self.appState = appState
        self.audioEngine = AudioEngine()
        self.speechRecognizer = SpeechRecognizer(locale: Locale(identifier: "it-IT"))
        self.speechSynthesizer = SpeechSynthesizer(config: .jarvis)
        setupBindings()
    }

    // MARK: - Bindings

    private func setupBindings() {
        audioEngine.$currentLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in self?.appState.audioLevel = level }
            .store(in: &cancellables)

        speechSynthesizer.$simulatedAudioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                guard let self, self.speechSynthesizer.isSpeaking else { return }
                self.appState.audioLevel = level
            }
            .store(in: &cancellables)

        speechRecognizer.onPartialTranscript = { [weak self] partial in
            Task { @MainActor in self?.appState.lastUserMessage = partial }
        }

        speechRecognizer.onFinalTranscript = { [weak self] text in
            Task { @MainActor in await self?.handleUserInput(text) }
        }

        speechSynthesizer.onSpeakingStarted = { [weak self] in
            self?.appState.transition(to: .speaking)
        }

        speechSynthesizer.onSpeakingFinished = { [weak self] in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                self?.startListening()
            }
        }
    }

    // MARK: - Lifecycle

    func activate() {
        Task { await initialize(); greetUser() }
    }

    func deactivate() {
        speechSynthesizer.stop()
        audioEngine.stop()
        speechRecognizer.stopListening()
        appState.reset()
    }

    // MARK: - Init / Permissions

    private func initialize() async {
        guard !isInitialized else { startListening(); return }
        appState.transition(to: .processing)

        let speechOK = await speechRecognizer.requestPermission()
        let micOK    = await requestMicrophonePermission()
        permissionsGranted = speechOK && micOK

        if !permissionsGranted {
            appState.transition(to: .error("Permessi necessari non concessi"))
            return
        }
        isInitialized = true
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { cont.resume(returning: $0) }
        }
    }

    private func greetUser() {
        let hour = Calendar.current.component(.hour, from: Date())
        let msg: String
        switch hour {
        case 5..<12:  msg = "Buongiorno. Sono pronto."
        case 12..<17: msg = "Buon pomeriggio. Come posso aiutarti?"
        case 17..<21: msg = "Buona sera. Sono in ascolto."
        default:       msg = "Ciao. Sono qui."
        }
        appState.lastAssistantResponse = msg
        speechSynthesizer.speak(msg)
    }

    // MARK: - Listening

    func startListening() {
        guard permissionsGranted, !speechSynthesizer.isSpeaking else { return }
        do {
            let cb = try speechRecognizer.startListening()
            try audioEngine.start(bufferCallback: cb)
            appState.transition(to: .listening)
        } catch {
            appState.transition(to: .error(error.localizedDescription))
        }
    }

    func stopListening() {
        audioEngine.stop()
        speechRecognizer.stopListening()
        if appState.assistantState == .listening { appState.transition(to: .idle) }
    }

    // MARK: - Input Handling

    private func handleUserInput(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            startListening(); return
        }

        appState.lastUserMessage = text
        appState.transition(to: .processing)
        audioEngine.stop()
        speechRecognizer.stopListening()

        let response = await router.handle(text)

        // Comando stop
        if response == "__STOP__" { deactivate(); return }

        appState.lastAssistantResponse = response
        speechSynthesizer.speak(response)
    }
}
