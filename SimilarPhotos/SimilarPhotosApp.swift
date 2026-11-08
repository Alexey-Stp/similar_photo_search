import Presentation
import SwiftUI

@main
struct SimilarPhotosApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootHost()
                .environment(\.viewModelFactory, container)
        }
    }
}
