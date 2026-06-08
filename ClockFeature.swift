// ClockFeature.swift
import Foundation

struct ClockFeature {

    func currentTime() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "HH:mm"
        return "Sono le \(f.string(from: Date()))."
    }

    func currentDate() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "EEEE d MMMM yyyy"
        let s = f.string(from: Date())
        return "Oggi è \(s)."
    }
}
