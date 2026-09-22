import Foundation
import Combine

/// Shared observable state driving the SwiftUI panel.
final class AppState: ObservableObject {
    @Published var mode: String = "idle"
    @Published var reason: String = "starting"
    @Published var sessions: [SessionRecord] = []
    @Published var manual: Bool = false
    let contract: Contract

    init(contract: Contract) {
        self.contract = contract
    }

    /// Note: `mode` is owned by the app's rotation/display logic, not the
    /// aggregate — so it is deliberately NOT set here (otherwise the floating
    /// light would snap back to the top-priority mode every poll).
    func update(_ agg: Aggregate) {
        reason = agg.reason
        sessions = agg.sessions
        manual = agg.manual
    }
}
