import SwiftUI
import SwiftData

@main
@MainActor struct KlarApp:App {
    private let container: ModelContainer
    @StateObject private var store: AppStore

    init() {
        do {
            let model = try ModelContainer(for:LocalRecord.self)
            container = model
            _store = StateObject(wrappedValue:AppStore(context:model.mainContext))
        } catch {
            fatalError("Lokale Datenbank konnte nicht geöffnet werden: \(error.localizedDescription)")
        }
    }

    var body:some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .task { await store.bootstrap() }
        }.modelContainer(container)
    }
}
