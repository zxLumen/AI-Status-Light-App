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

    func update(_ agg: Aggregate) {
        mode = agg.mode
        reason = agg.reason
        sessions = agg.sessions
        manual = agg.manual
    }
}
