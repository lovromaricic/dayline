import Domain
import Foundation
import UserNotifications

/// Sends the end-of-day recap (spec 5.5): once a day, at the chosen hour or
/// within three hours after it (a Mac asleep at 18:00 still gets it at
/// 19:30, not at midnight). Do Not Disturb and Focus are left to macOS.
final class Recap: NSObject, UNUserNotificationCenterDelegate {
    private let engine: TrackingEngine
    /// Clicking the notification opens that day in the timeline.
    var onOpenDay: ((Int64) -> Void)?

    static let window: Int64 = 3 * 3600

    init(engine: TrackingEngine) {
        self.engine = engine
        super.init()
        Self.center?.delegate = self
    }

    /// nil outside an app bundle (swift run), where the API would trap.
    private static var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    static func requestPermission() {
        center?.requestAuthorization(options: [.alert, .sound]) { granted, error in
            Log.line("recap permission \(granted)\(error.map { " \($0.localizedDescription)" } ?? "")")
        }
    }

    /// Called with today's report on every refresh.
    func check(report r: DayReport, now: Int64) {
        guard let hour = engine.recapHour, r.isToday, case .tracking = engine.phase else { return }
        let due = r.dayStart + Int64(hour) * 3600
        guard now >= due, now < due + Self.window, engine.recapSentDay != r.dayStart, let recap = DayRecap(report: r) else { return }
        engine.recapSentDay = r.dayStart
        send(recap, dayStart: r.dayStart)
    }

    private func send(_ recap: DayRecap, dayStart: Int64) {
        guard let center = Self.center else { return }
        let content = UNMutableNotificationContent()
        content.title = recap.title
        content.body = recap.body
        content.userInfo = ["dayStart": dayStart]
        center.add(UNNotificationRequest(identifier: "recap-\(dayStart)", content: content, trigger: nil)) { error in
            Log.line("recap sent\(error.map { ", failed: \($0.localizedDescription)" } ?? "")")
        }
    }

    // Show it even while Dayline counts as the active app.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        if let day = response.notification.request.content.userInfo["dayStart"] as? Int64 {
            DispatchQueue.main.async { self.onOpenDay?(day) }
        }
        done()
    }
}
