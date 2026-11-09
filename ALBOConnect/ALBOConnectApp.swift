import SwiftUI

@main struct ALBOConnectApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).tint(Brand.blue)
                .alert("Hinweis", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                    Button("OK") { store.error = nil }
                } message: { Text(store.error ?? "") }
        }
    }
}

enum Brand {
    static let blue = Color(red: 0.02, green: 0.36, blue: 0.75)
    static let ink = Color(red: 0.07, green: 0.16, blue: 0.27)
    static let background = Color(uiColor: .systemGroupedBackground)
}
