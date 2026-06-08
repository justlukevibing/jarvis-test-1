// AssistantView.swift — v2 "Cinematographic JARVIS"
// Layout riprogettato ispirato all'estetica originale:
//   - Sfondo nero puro (#000)
//   - HUD superiore: JARVIS centrato + stato in alto a sinistra
//   - Orb al centro con tutta la scena
//   - Messaggi sotto l'orb, font monospace, bordo ciano sottile
//   - HUD inferiore: icone piatte con bordo ciano, nessun fill
//   - Pulsante info in alto a destra (stile originale)
//   - Pulsante chiudi rimosso dalla UI (si chiude con ⌥ Space o Esc)

import SwiftUI

// MARK: - AssistantView

struct AssistantView: View {

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewModel: AssistantViewModel

    @State private var appeared = false

    // Colore unico di tutta l'interfaccia
    private let teal = Color(red: 0, green: 220/255, blue: 200/255)

    var body: some View {
        ZStack {
            // Sfondo: nero assoluto
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── HUD Top ──
                hudTop
                    .padding(.horizontal, 22)
                    .padding(.top, 18)

                Spacer(minLength: 0)

                // ── Orb centrale ──
                OrbView(
                    state: appState.assistantState,
                    audioLevel: appState.audioLevel
                )
                .frame(width: 300, height: 300)
                .scaleEffect(appeared ? 1.0 : 0.75)
                .opacity(appeared ? 1.0 : 0)

                Spacer(minLength: 0)

                // ── Area messaggi ──
                messageArea
                    .padding(.horizontal, 24)
                    .frame(minHeight: 52)

                Spacer(minLength: 12)

                // ── HUD Bottom ──
                hudBottom
            }
        }
        .frame(width: 480, height: 540)
        .clipShape(RoundedRectangle(cornerRadius: 0))
        // Nessun corner radius — bordo netto come l'app originale
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(teal.opacity(0.12), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: teal.opacity(0.12), radius: 40, x: 0, y: 20)
        .shadow(color: .black.opacity(0.8), radius: 24, x: 0, y: 12)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { appeared = true }
        }
        .onKeyPress(.escape) {
            NotificationCenter.default.post(name: .jarvisClosePopup, object: nil)
            return .handled
        }
    }

    // MARK: - HUD Top

    private var hudTop: some View {
        ZStack {
            // Titolo centrato
            Text("JARVIS")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(teal.opacity(0.65))
                .tracking(6)

            HStack {
                // Stato a sinistra
                Text(appState.assistantState.description.uppercased())
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(teal.opacity(0.38))
                    .tracking(3)
                    .animation(.easeInOut(duration: 0.3), value: appState.assistantState)

                Spacer()

                // Pulsante info a destra
                Button {
                    // Future: mostra info/settings
                } label: {
                    ZStack {
                        Circle()
                            .stroke(teal.opacity(0.28), lineWidth: 0.5)
                            .frame(width: 20, height: 20)
                        Text("i")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(teal.opacity(0.38))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Message Area

    private var messageArea: some View {
        VStack(spacing: 6) {
            if !appState.lastUserMessage.isEmpty {
                HUDMessageBubble(
                    text: appState.lastUserMessage,
                    isUser: true,
                    teal: teal
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if !appState.lastAssistantResponse.isEmpty {
                HUDMessageBubble(
                    text: appState.lastAssistantResponse,
                    isUser: false,
                    teal: teal
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.35), value: appState.lastUserMessage)
        .animation(.easeOut(duration: 0.35), value: appState.lastAssistantResponse)
    }

    // MARK: - HUD Bottom

    private var hudBottom: some View {
        VStack(spacing: 0) {
            // Separatore
            Rectangle()
                .fill(teal.opacity(0.08))
                .frame(height: 0.5)

            // Barra icone
            HStack(spacing: 0) {
                HUDButton(icon: "clock", action: {})
                HUDButton(icon: "square.and.arrow.up", action: {})
                HUDButton(
                    icon: appState.assistantState == .listening ? "mic.fill" : "mic",
                    isActive: appState.assistantState == .listening,
                    action: {
                        if appState.assistantState == .listening {
                            viewModel.stopListening()
                        } else {
                            viewModel.startListening()
                        }
                    }
                )
                HUDButton(icon: "record.circle", action: {})
                HUDButton(icon: "shield.lefthalf.filled", action: {})
            }
            .frame(height: 52)
        }
    }
}

// MARK: - HUDMessageBubble

/// Bolla messaggio stile HUD militare:
/// font monospaced, bordo ciano sottile, sfondo quasi trasparente
struct HUDMessageBubble: View {
    let text: String
    let isUser: Bool
    let teal: Color

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            Text(text)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(teal.opacity(isUser ? 0.6 : 0.88))
                .tracking(0.5)
                .lineSpacing(2)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(teal.opacity(isUser ? 0.04 : 0.06))
                .overlay(
                    Rectangle()
                        .stroke(teal.opacity(isUser ? 0.2 : 0.14), lineWidth: 0.5)
                )

            if !isUser { Spacer(minLength: 60) }
        }
    }
}

// MARK: - HUDButton

/// Pulsante icona per la barra inferiore.
/// Stile: trasparente, icona ciano a bassa opacità, nessun bordo.
struct HUDButton: View {
    let icon: String
    var isActive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    private let teal = Color(red: 0, green: 220/255, blue: 200/255)

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .light))
                .foregroundColor(
                    isActive
                    ? teal.opacity(0.9)
                    : teal.opacity(isHovered ? 0.75 : 0.38)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    teal.opacity(
                        isActive ? 0.08 : (isHovered ? 0.04 : 0)
                    )
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let jarvisClosePopup  = Notification.Name("jarvisClosePopup")
    static let jarvisTogglePopup = Notification.Name("jarvisTogglePopup")
}

// MARK: - Previews

#Preview("Idle") {
    AssistantView()
        .environmentObject(AppState.shared)
        .environmentObject(AssistantViewModel(appState: AppState.shared))
}

#Preview("Speaking") {
    AssistantView()
        .environmentObject({
            let s = AppState.shared
            s.assistantState = .speaking
            s.lastUserMessage = "Che ore sono?"
            s.lastAssistantResponse = "Sono le 14:32 di venerdì."
            s.audioLevel = 0.6
            return s
        }())
        .environmentObject(AssistantViewModel(appState: AppState.shared))
}
