// OrbView.swift — v2 "Cinematographic JARVIS"
// Redesign completo ispirato all'estetica del JARVIS originale:
//   - Sfera wireframe triangolata (griglia latitudine/longitudine)
//   - Anelli concentrici segmentati con prospettiva schiacciata
//   - Barre radiali reattive all'audio
//   - Monocromatico: solo ciano #00DCC8, nessun colore secondario
//   - Nessun particle system — la profondità viene dalla geometria
//
// Tutto disegnato con Canvas + TimelineView, zero dipendenze.

import SwiftUI

// MARK: - Design Constants

private enum JarvisColor {
    static let primary = Color(red: 0/255, green: 220/255, blue: 200/255)
    static let core    = Color(red: 0/255, green: 255/255, blue: 235/255)
    static let glow    = Color(red: 0/255, green: 160/255, blue: 150/255)
}

// MARK: - OrbConfig per stato

private struct OrbConfig {
    var scanSpeed:    Double  // velocità rotazione anelli
    var ringCount:    Int     // numero anelli concentrici
    var wireOpacity:  Double  // opacità griglia wireframe
    var ringOpacity:  Double  // opacità base anelli
    var pulseSpeed:   Double  // velocità barre radiali
    var statusLabel:  String

    static func config(for state: AssistantState) -> OrbConfig {
        switch state {
        case .idle:
            return OrbConfig(scanSpeed:1.0, ringCount:7, wireOpacity:0.50, ringOpacity:0.22, pulseSpeed:0.30, statusLabel:"IDLE")
        case .listening:
            return OrbConfig(scanSpeed:1.6, ringCount:8, wireOpacity:0.75, ringOpacity:0.42, pulseSpeed:0.80, statusLabel:"LISTENING")
        case .processing:
            return OrbConfig(scanSpeed:3.0, ringCount:9, wireOpacity:0.65, ringOpacity:0.35, pulseSpeed:1.80, statusLabel:"PROCESSING")
        case .speaking:
            return OrbConfig(scanSpeed:1.2, ringCount:7, wireOpacity:0.60, ringOpacity:0.38, pulseSpeed:0.60, statusLabel:"SPEAKING")
        case .error:
            return OrbConfig(scanSpeed:0.4, ringCount:5, wireOpacity:0.30, ringOpacity:0.15, pulseSpeed:0.20, statusLabel:"ERROR")
        }
    }
}

// MARK: - OrbView

struct OrbView: View {

    let state: AssistantState
    let audioLevel: Float

    // Dimensione dell'orb nel canvas
    private let canvasSize: CGFloat = 300
    private let sphereRadius: CGFloat = 68
    private let baseRingRadius: CGFloat = 74

    var body: some View {
        let cfg = OrbConfig.config(for: state)
        let audio = CGFloat(audioLevel)

        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                let cx = size.width / 2
                let cy = size.height / 2

                drawAmbientGlow(context: context, cx: cx, cy: cy, audio: audio)
                drawConcentricRings(context: context, cx: cx, cy: cy,
                                    t: t, cfg: cfg, audio: audio)
                drawRadialBars(context: context, cx: cx, cy: cy,
                               t: t, cfg: cfg, audio: audio)
                drawCoreDisk(context: context, cx: cx, cy: cy, audio: audio)
                drawWireframeSphere(context: context, cx: cx, cy: cy,
                                    t: t, cfg: cfg, audio: audio)
            }
            .frame(width: canvasSize, height: canvasSize)
        }
    }

    // MARK: - Layer: Ambient Glow

    private func drawAmbientGlow(context: GraphicsContext, cx: CGFloat, cy: CGFloat, audio: CGFloat) {
        let glowR = baseRingRadius * (2.2 + audio * 0.4)
        let opacity = 0.06 + audio * 0.06

        context.fill(
            Path(ellipseIn: CGRect(x: cx - glowR, y: cy - glowR, width: glowR*2, height: glowR*2)),
            with: .color(JarvisColor.glow.opacity(opacity))
        )
    }

    // MARK: - Layer: Concentric Rings

    /// Anelli con segmenti tratteggiati, sciacciati prospetticamente (scaleY < 1)
    /// per simulare la profondità dell'immagine di riferimento.
    private func drawConcentricRings(
        context: GraphicsContext,
        cx: CGFloat, cy: CGFloat,
        t: TimeInterval,
        cfg: OrbConfig,
        audio: CGFloat
    ) {
        let count = cfg.ringCount

        for i in 0..<count {
            let norm = CGFloat(i) / CGFloat(count - 1)

            // Raggio cresce verso l'esterno + boost audio
            let r = baseRingRadius + norm * baseRingRadius * 1.6 + audio * norm * 18

            // Prospettiva: sciacciato verso il basso (anelli = orbita ellittica)
            let scaleY: CGFloat = 0.20 + norm * 0.80

            // Opacità: più vicino al centro = più debole (suggerisce profondità)
            let depth = 1.0 - norm * 0.78
            let opacity = cfg.ringOpacity * Double(depth) * (0.5 + Double(norm) * 0.5)

            // Segmentazione: anelli non continui ma a dash
            let segCount = Int(38 + norm * 70)
            let gapRatio: CGFloat = 0.07 + norm * 0.055

            // Rotazione: direzione alternata per effetto vortice
            let rotDir: CGFloat = (i % 2 == 0) ? 1 : -1
            let rotOffset = CGFloat(t) * CGFloat(cfg.scanSpeed) * 0.04 * rotDir + norm * 1.2

            // Spessore cresce verso l'esterno
            let lineWidth: CGFloat = 0.4 + norm * 0.9

            for s in 0..<segCount {
                let a0 = CGFloat(s) / CGFloat(segCount) * .pi * 2 + rotOffset
                let a1 = (CGFloat(s) + 1.0 - gapRatio) / CGFloat(segCount) * .pi * 2 + rotOffset

                var path = Path()
                let steps = 20
                for step in 0...steps {
                    let angle = a0 + (a1 - a0) * CGFloat(step) / CGFloat(steps)
                    let x = cx + r * cos(angle)
                    // Applicazione dello schiacciamento prospettico
                    let y = cy + r * sin(angle) * scaleY

                    if step == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else          { path.addLine(to: CGPoint(x: x, y: y)) }
                }

                context.stroke(
                    path,
                    with: .color(JarvisColor.primary.opacity(opacity)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            }
        }
    }

    // MARK: - Layer: Radial Bars

    /// Barre radiali che reagiscono all'audio.
    /// Partono dalla superficie della sfera wireframe e crescono verso fuori,
    /// formando una corona circolare attorno al globo centrale.
    /// La sfera è circolare in proiezione 2D — nessuno scaleY qui.
    private func drawRadialBars(
        context: GraphicsContext,
        cx: CGFloat, cy: CGFloat,
        t: TimeInterval,
        cfg: OrbConfig,
        audio: CGFloat
    ) {
        let barCount = 64
        let gap: CGFloat = 2          // distanza tra superficie sfera e inizio barra
        let maxBarH: CGFloat = 10     // altezza massima: compatta e minimal
        let r0 = sphereRadius + gap   // raggio interno (sulla sfera)

        for i in 0..<barCount {
            let angle: CGFloat = CGFloat(i) / CGFloat(barCount) * .pi * 2

            // Due armoniche sfasate — aspetto organico, non periodico
            let n1 = sin(CGFloat(i) * 0.65 + CGFloat(t) * CGFloat(cfg.pulseSpeed) * 2.0) * 0.5
            let n2 = sin(CGFloat(i) * 1.37 + CGFloat(t) * CGFloat(cfg.pulseSpeed) * 3.1) * 0.3
            let amp = max(0, n1 + n2)

            let barH = amp * maxBarH * 0.6 + audio * maxBarH * 0.4
            let r1 = r0 + barH        // raggio esterno

            // Coordinate: sfera circolare, barre crescono radialmente
            let x0 = cx + r0 * cos(angle)
            let y0 = cy + r0 * sin(angle)
            let x1 = cx + r1 * cos(angle)
            let y1 = cy + r1 * sin(angle)

            let alpha = 0.20 + Double(audio) * 0.40 + Double(amp) * 0.20

            var barPath = Path()
            barPath.move(to: CGPoint(x: x0, y: y0))
            barPath.addLine(to: CGPoint(x: x1, y: y1))

            context.stroke(
                barPath,
                with: .color(JarvisColor.primary.opacity(alpha)),
                style: StrokeStyle(lineWidth: 0.9, lineCap: .round)
            )
        }
    }

    // MARK: - Layer: Core Disk

    /// Nucleo luminoso: alone concentrato al centro della sfera
    private func drawCoreDisk(context: GraphicsContext, cx: CGFloat, cy: CGFloat, audio: CGFloat) {
        let R = sphereRadius * 0.9 + audio * 5

        // Glow interno più intenso
        context.fill(
            Path(ellipseIn: CGRect(x: cx - R*0.5, y: cy - R*0.5, width: R, height: R)),
            with: .color(JarvisColor.core.opacity(0.08 + Double(audio) * 0.07))
        )
        context.fill(
            Path(ellipseIn: CGRect(x: cx - R*0.25, y: cy - R*0.25, width: R*0.5, height: R*0.5)),
            with: .color(JarvisColor.core.opacity(0.05 + Double(audio) * 0.04))
        )
    }

    // MARK: - Layer: Wireframe Sphere

    /// Sfera in filo di ferro con linee di latitudine e longitudine.
    /// È il nucleo centrale dell'orb, quello più iconico nell'immagine di riferimento.
    private func drawWireframeSphere(
        context: GraphicsContext,
        cx: CGFloat, cy: CGFloat,
        t: TimeInterval,
        cfg: OrbConfig,
        audio: CGFloat
    ) {
        let R = sphereRadius + CGFloat(audio) * 7
        let latLines = 8
        let lonLines = 12
        let lineW: CGFloat = 0.55

        // Latitudini (cerchi orizzontali)
        for i in 0...latLines {
            let phi: CGFloat = CGFloat(i) / CGFloat(latLines) * .pi
            let sinPhi = sin(phi)
            guard sinPhi > 0.05 else { continue }

            let rLat = R * sinPhi
            let yLat = cy + R * cos(phi)

            var path = Path()
            let steps = 64
            for s in 0...steps {
                let theta: CGFloat = CGFloat(s) / CGFloat(steps) * .pi * 2
                let x = cx + rLat * cos(theta)
                if s == 0 { path.move(to: CGPoint(x: x, y: yLat)) }
                else       { path.addLine(to: CGPoint(x: x, y: yLat)) }
            }
            path.closeSubpath()

            context.stroke(
                path,
                with: .color(JarvisColor.primary.opacity(cfg.wireOpacity * 0.85)),
                style: StrokeStyle(lineWidth: lineW, lineCap: .round)
            )
        }

        // Longitudini (meridiani, ruotano lentamente)
        for j in 0..<lonLines {
            let theta: CGFloat = CGFloat(j) / CGFloat(lonLines) * .pi * 2
                                + CGFloat(t) * 0.12 * CGFloat(cfg.scanSpeed) * 0.35

            var path = Path()
            let steps = 48
            for s in 0...steps {
                let phi: CGFloat = CGFloat(s) / CGFloat(steps) * .pi
                let x = cx + R * sin(phi) * cos(theta)
                let y = cy + R * cos(phi)
                if s == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else       { path.addLine(to: CGPoint(x: x, y: y)) }
            }

            context.stroke(
                path,
                with: .color(JarvisColor.primary.opacity(cfg.wireOpacity * 0.7)),
                style: StrokeStyle(lineWidth: lineW, lineCap: .round)
            )
        }
    }
}

// MARK: - Previews

#Preview("Idle") {
    ZStack { Color.black; OrbView(state: .idle, audioLevel: 0) }
        .frame(width: 360, height: 360)
}
#Preview("Listening") {
    ZStack { Color.black; OrbView(state: .listening, audioLevel: 0.65) }
        .frame(width: 360, height: 360)
}
#Preview("Processing") {
    ZStack { Color.black; OrbView(state: .processing, audioLevel: 0.1) }
        .frame(width: 360, height: 360)
}
