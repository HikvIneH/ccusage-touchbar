// A notification as a limit crosses 80% and 95%, once per window, and one when that window resets.
//   defaults write com.hikvineh.ccusagebar alerts -array 70 90    # other thresholds
//   defaults write com.hikvineh.ccusagebar alerts -array          # none
import UserNotifications

final class Alerts: NSObject, UNUserNotificationCenterDelegate {
    private let thresholds = (UserDefaults.standard.array(forKey: "alerts") as? [Int]) ?? [80, 95]
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        guard !thresholds.isEmpty else { return }
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func check(_ u: Usage) {
        // Stale numbers could announce a crossing that already reset.
        guard !thresholds.isEmpty, !u.stale else { return }
        // Per limit: the minute its window resets, and the highest threshold already announced in it.
        var seen = UserDefaults.standard.dictionary(forKey: "alerted") as? [String: [Double]] ?? [:]
        for r in u.rows {
            guard let window = r.resetsAt else { continue }
            var told = 0.0
            if let prev = seen[r.title], prev.count == 2 {
                told = prev[1]
                if prev[0] != window {
                    if told > 0 { post("\(r.title) limit reset", "Back to \(Int(r.pct))%.") }
                    told = 0
                }
            }
            if let t = thresholds.map(Double.init).filter({ $0 <= r.pct && $0 > told }).max() {
                post("\(r.title) limit at \(Int(r.pct))%", r.sub.isEmpty ? "" : "\(r.sub.capitalizedFirst) (\(until(window))).")
                told = t
            }
            seen[r.title] = [window, told]
        }
        UserDefaults.standard.set(seen, forKey: "alerted")
    }

    private func post(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    // Shown even though this app counts as frontmost-capable; there is no window to show it in instead.
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
