import SwiftUI
import SwiftData
import FirebaseCore

@main
struct KurierXApp: App {
    @StateObject private var session = SessionStore()
    private let container: ModelContainer

    init() {
        let schema = Schema([
            Shift.self, Route.self, Customer.self, FinancialEntry.self, Goal.self,
            CalendarPlan.self, FuelEntry.self, AdvanceEntry.self, SalaryEntry.self,
            AuditEntry.self, AppPreference.self
        ])
        container = try! ModelContainer(for: schema)
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil, FirebaseApp.app() == nil { FirebaseApp.configure() }
    }

    var body: some Scene {
        WindowGroup { RootView().environmentObject(session) }
            .modelContainer(container)
    }
}
