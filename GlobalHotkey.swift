// GlobalHotkey.swift
// Registra una hotkey globale di sistema tramite CGEventTap.
// Funziona anche quando l'app non è in foreground.
//
// NOTA: Richiede il permesso "Accessibilità" in
// Preferenze di Sistema → Privacy e sicurezza → Accessibilità
// L'app deve richiedere questo permesso al primo avvio.

import Cocoa
import Carbon

// MARK: - GlobalHotkey

/// Wrapper semplice per una hotkey globale basata su CGEventTap.
/// Alternativa: RegisterEventHotKey (Carbon API) — più semplice ma deprecata.
/// Scelta CGEventTap: moderna, supportata, non deprecata.
final class GlobalHotkey {

    // MARK: Types
    typealias Handler = () -> Void

    // MARK: Properties
    private let keyCode: CGKeyCode
    private let modifierFlags: CGEventFlags
    private let handler: Handler
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // MARK: Init
    init(keyCode: Int, modifierFlags: CGEventFlags, handler: @escaping Handler) {
        self.keyCode = CGKeyCode(keyCode)
        self.modifierFlags = modifierFlags
        self.handler = handler
    }

    // MARK: Register / Unregister

    /// Registra la hotkey. Restituisce true se la registrazione ha avuto successo.
    @discardableResult
    func register() -> Bool {
        // Verifica permesso Accessibilità
        guard checkAccessibilityPermission() else {
            requestAccessibilityPermission()
            return false
        }

        // Callback C-style: CGEventTap richiede una funzione C pura,
        // usiamo un puntatore non gestito per passare self
        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard type == .keyDown,
                      let userInfo = userInfo else {
                    return Unmanaged.passRetained(event)
                }

                let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(userInfo).takeUnretainedValue()

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags.intersection([.maskAlternate, .maskCommand,
                                                      .maskControl, .maskShift])

                if CGKeyCode(keyCode) == hotkey.keyCode && flags == hotkey.modifierFlags {
                    DispatchQueue.main.async {
                        hotkey.handler()
                    }
                    // Consume l'evento (non lo propaga ad altre app)
                    return nil
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: selfPtr
        )

        guard let tap = tap else {
            print("❌ Impossibile creare CGEventTap")
            Unmanaged.passUnretained(self).release()
            return false
        }

        self.eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source

        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("✅ Hotkey globale registrata (⌥ Space)")
        return true
    }

    /// Rimuove la hotkey e libera le risorse
    func unregister() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        print("🔇 Hotkey globale rimossa")
    }

    // MARK: Accessibility

    private func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    private func requestAccessibilityPermission() {
        let alert = NSAlert()
        alert.messageText = "JARVIS ha bisogno dell'accesso Accessibilità"
        alert.informativeText = """
            Per usare la hotkey globale (⌥ Space), JARVIS deve avere il permesso di Accessibilità.

            Vai in: Preferenze di Sistema → Privacy e sicurezza → Accessibilità
            e aggiungi JARVIS alla lista.
            """
        alert.addButton(withTitle: "Apri Preferenze di Sistema")
        alert.addButton(withTitle: "Ignora")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
        }
    }
}

// MARK: - Carbon Fallback (Fase futura)
// Se CGEventTap dovesse dare problemi, RegisterEventHotKey è l'alternativa Carbon:
//
// var hotKeyRef: EventHotKeyRef?
// var gMyHotKeyID = EventHotKeyID()
// gMyHotKeyID.signature = OSType("swft".utf8.reduce(0) { $0 << 8 + OSType($1) })
// gMyHotKeyID.id = 1
// RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), gMyHotKeyID,
//                     GetApplicationEventTarget(), 0, &hotKeyRef)
