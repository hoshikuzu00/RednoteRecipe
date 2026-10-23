import Foundation

struct ShoppingCartItem: Codable, Identifiable, Equatable {
    let id: UUID
    let ingredientName: String
    let amount: String?
    let unit: String?
    let sourceRecipeTitle: String
    var isChecked: Bool
    let createdAt: Date
}

@MainActor
final class ShoppingCartStore: ObservableObject {
    @Published private(set) var items: [ShoppingCartItem] = []

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        loadItems()
    }

    func addIngredients(from recipe: SavedRecipe) -> Int {
        let newItems = recipe.allIngredients.map { ingredient in
            ShoppingCartItem(
                id: UUID(),
                ingredientName: ingredient.name,
                amount: ingredient.amount,
                unit: ingredient.unit,
                sourceRecipeTitle: recipe.title,
                isChecked: false,
                createdAt: Date()
            )
        }

        items.append(contentsOf: newItems)
        persistItems()
        return newItems.count
    }

    func toggleItem(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isChecked.toggle()
        persistItems()
    }

    func clearAll() {
        items.removeAll()
        persistItems()
    }

    func replaceAllItems(_ items: [ShoppingCartItem]) {
        self.items = items.sorted { $0.createdAt < $1.createdAt }
        persistItems()
    }

    func exportedItems() -> [ShoppingCartItem] {
        items
    }

    private func loadItems() {
        do {
            let url = try storageURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                items = []
                return
            }

            let data = try Data(contentsOf: url)
            items = try decoder.decode([ShoppingCartItem].self, from: data)
        } catch {
            items = []
            print("Failed to load shopping cart: \(error.localizedDescription)")
        }
    }

    private func persistItems() {
        do {
            let url = try storageURL()
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(items)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to save shopping cart: \(error.localizedDescription)")
        }
    }

    private func storageURL() throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return applicationSupport
            .appendingPathComponent("RednoteOCR", isDirectory: true)
            .appendingPathComponent("shopping-cart.json")
    }
}
