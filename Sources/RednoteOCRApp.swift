import SwiftUI

@main
struct RednoteOCRApp: App {
    @StateObject private var recipeLibraryStore = RecipeLibraryStore()
    @StateObject private var shoppingCartStore = ShoppingCartStore()
    @StateObject private var openAISettingsStore = OpenAISettingsStore()
    @StateObject private var localBackendSettingsStore = LocalBackendSettingsStore()
    @StateObject private var categoryStore = CategoryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(recipeLibraryStore)
                .environmentObject(shoppingCartStore)
                .environmentObject(openAISettingsStore)
                .environmentObject(localBackendSettingsStore)
                .environmentObject(categoryStore)
        }
    }
}
