import SwiftUI

@main
struct StickerRescueApp: App {
    @State private var model = StickerLibraryModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
    }
}
