// PopupWindow.swift — v2
// Aggiornato per la nuova dimensione del popup: 480×540
// Nessun corner radius sulla NSPanel (il clip avviene in SwiftUI)

import AppKit
import SwiftUI

final class PopupWindowController {

    private var panel: NSPanel?
    private let appState: AppState
    private let viewModel: AssistantViewModel
    private var isVisible: Bool = false

    // Dimensioni aggiornate per il nuovo layout
    private let windowWidth:  CGFloat = 480
    private let windowHeight: CGFloat = 540

    init(appState: AppState, viewModel: AssistantViewModel) {
        self.appState = appState
        self.viewModel = viewModel
        createPanel()
    }

    private func createPanel() {
        let styleMask: NSWindow.StyleMask = [
            .borderless,
            .fullSizeContentView,
            .nonactivatingPanel
        ]

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false  // La shadow è gestita in SwiftUI per controllo totale
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = true
        panel.acceptsMouseMovedEvents = true

        let contentView = AssistantView()
            .environmentObject(appState)
            .environmentObject(viewModel)

        panel.contentView = NSHostingView(rootView: contentView)
        centerPanel(panel)
        self.panel = panel
    }

    func show() {
        guard let panel = panel, !isVisible else { return }
        centerPanel(panel)
        panel.alphaValue = 0
        panel.orderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.20
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }

        isVisible = true
        Task { @MainActor in appState.isPopupVisible = true }
    }

    func hide() {
        guard let panel = panel, isVisible else { return }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        }

        isVisible = false
        Task { @MainActor in
            appState.isPopupVisible = false
            appState.reset()
        }
    }

    func toggle() { isVisible ? hide() : show() }

    private func centerPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        let x = f.midX - windowWidth / 2
        let y = f.midY - windowHeight / 2 + f.height * 0.05
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
