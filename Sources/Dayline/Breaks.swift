import Domain
import Foundation
import UserNotifications

/// "Time for a break": one notification once you've been at your Mac for the
/// chosen time without a break, then quiet until you take one. Never during a
/// call. Clicking it only dismisses it.
final class Breaks {
    private let engine: TrackingEngine
    /// The stretch already reminded about, so it is sent once.
    private var remindedStretch: Int64?

    init(engine: TrackingEngine) {
        self.engine = engine
    }

    /// Called with today's segments on every refresh.
    func check(segments: [Segment], now: Int64) {
        guard engine.breakReminder, case .tracking = engine.phase, !engine.inCall,
              let start = BreakReminder.stretchStart(segments: segments, now: now),
              start != remindedStretch else { return }
        let minutes = (now - start) / 60
        guard minutes >= engine.breakMinutes else { return }
        remindedStretch = start
        send(minutes: minutes, stretch: start)
    }

    private func send(minutes: Int64, stretch: Int64) {
        guard let center = Recap.center else { return }
        let text = BreakReminder.text(minutes: minutes)
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        center.add(UNNotificationRequest(identifier: "break-\(stretch)", content: content, trigger: nil)) { error in
            Log.line("break reminder sent\(error.map { ", failed: \($0.localizedDescription)" } ?? "")")
        }
    }
}
