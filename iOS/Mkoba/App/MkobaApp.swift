import SwiftUI

@main
struct MkobaApp: App {
    @State private var model: AppModel

    init() {
        let inMemory = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        let persistence = PersistenceController(inMemory: inMemory)
        _model = State(initialValue: AppModel(
            store: CoreDataEventStore(container: persistence.container),
            api: APIClient(baseURL: AppConfig.apiBaseURL),
            device: DeviceIdentity.current()))
    }

    var body: some Scene {
        WindowGroup {
            GroupListView()
                .environment(model)
                .tint(Theme.green)
        }
    }
}

enum AppConfig {
    /// Injected through Info.plist from the build setting so debug and release can differ.
    static var apiBaseURL: URL {
        let raw = Bundle.main.object(forInfoDictionaryKey: "MKOBA_API_BASE_URL") as? String
        return URL(string: raw ?? "") ?? URL(string: "http://127.0.0.1:8080")!
    }
}
