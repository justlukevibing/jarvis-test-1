// JarvisApp.swift
// Entry point dell'applicazione JARVIS per macOS — aggiornato Fase 3.
// Aggiunge: iniezione AssistantViewModel, gestione notifiche popup.

import SwiftUI
import AppKit

@main
struct JarvisApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            Text("JARVIS v0.1")
                .padding()
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: Properties
    private var statusItem: NSStatusItem?
    private var popupWindowController: PopupWindowController?
    private var hotkey: GlobalHotkey?

    // Stato e ViewModel condivisi
    private let appState = AppState.shared
    private var viewModel: AssistantViewModel?

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Crea il ViewModel — unico per tutta la vita dell'app
        let vm = AssistantViewModel(appState: appState)
        self.viewModel = vm

        setupMenuBar()

        // Passa il ViewModel al PopupWindowController
        // così la view può accedervi via EnvironmentObject
        popupWindowController = PopupWindowController(appState: appState, viewModel: vm)

        setupGlobalHotkey()
        setupNotifications()

        print("✅ JARVIS avviato — Fase 3 (Speech Pipeline)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkey?.unregister()
        viewModel?.deactivate()
    }

    // MARK: Setup

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "waveform.circle.fill",
                               accessibilityDescription: "JARVIS")
        button.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Attiva JARVIS",
                                action: #selector(togglePopup),
                                keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Esci",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func setupGlobalHotkey() {
        hotkey = GlobalHotkey(keyCode: 49, modifierFlags: .maskAlternate) { [weak self] in
            self?.togglePopup()
        }
        let registered = hotkey?.register() ?? false
        if !registered {
            print("⚠️ Hotkey globale non registrata. Controlla il permesso Accessibilità.")
        }
    }

    /// Ascolta le notifiche inviate dalle SwiftUI view per chiudere il popup.
    /// Pattern: View → NotificationCenter → AppDelegate → PopupWindowController
    /// Questo evita di passare riferimenti al controller nelle view.
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClosePopup),
            name: .jarvisClosePopup,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(togglePopup),
            name: .jarvisTogglePopup,
            object: nil
        )
    }

    // MARK: Actions

    @objc func togglePopup() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.appState.isPopupVisible {
                self.closePopup()
            } else {
                self.openPopup()
            }
        }
    }

    @objc private func handleClosePopup() {
        DispatchQueue.main.async { [weak self] in
            self?.closePopup()
        }
    }

    private func openPopup() {
        popupWindowController?.show()
        // Attiva la pipeline speech quando il popup appare
        viewModel?.activate()
    }

    private func closePopup() {
        // Deattiva prima (ferma microfono, TTS, ecc.)
        viewModel?.deactivate()
        popupWindowController?.hide()
    }
}
