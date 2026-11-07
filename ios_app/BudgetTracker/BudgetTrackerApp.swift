import SwiftUI

@main
struct BudgetTrackerApp: App {
    init() {
        // Force database loading and table checking on application start
        _ = DatabaseManager.shared
    }
    
    var body: some Scene {
        WindowGroup {
            DashboardView()
                .preferredColorScheme(.dark)
        }
    }
}
