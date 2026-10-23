import Foundation

enum RecipeRating: String, Codable, CaseIterable, Identifiable {
    case okay
    case good
    case love

    var id: String { rawValue }

    var label: String {
        switch self {
        case .okay:
            return "一般"
        case .good:
            return "喜欢"
        case .love:
            return "超爱"
        }
    }
}

struct SavedRecipeStepKey: Codable, Hashable {
    let sectionID: UUID?
    let stepIndex: Int

    init(sectionID: UUID?, stepIndex: Int) {
        self.sectionID = sectionID
        self.stepIndex = stepIndex
    }
}

struct SavedRecipe: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let category: String?
    let rating: RecipeRating?
    let ingredients: [SavedIngredient]
    let steps: [String]
    let tips: [String]
    let timeHints: [String]
    let sections: [SavedRecipeSection]
    let completedStepKeys: [SavedRecipeStepKey]
    let sourceURLString: String?
    let rawText: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case category
        case rating
        case ingredients
        case steps
        case tips
        case timeHints
        case sections
        case completedStepKeys
        case sourceURLString
        case rawText
        case createdAt
    }

    init(
        id: UUID,
        title: String,
        category: String?,
        rating: RecipeRating?,
        ingredients: [SavedIngredient],
        steps: [String],
        tips: [String],
        timeHints: [String],
        sections: [SavedRecipeSection],
        completedStepKeys: [SavedRecipeStepKey],
        sourceURLString: String?,
        rawText: String,
        createdAt: Date
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.rating = rating
        self.ingredients = ingredients
        self.steps = steps
        self.tips = tips
        self.timeHints = timeHints
        self.sections = sections
        self.completedStepKeys = completedStepKeys
        self.sourceURLString = sourceURLString
        self.rawText = rawText
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        rating = try container.decodeIfPresent(RecipeRating.self, forKey: .rating)
        ingredients = try container.decodeIfPresent([SavedIngredient].self, forKey: .ingredients) ?? []
        steps = try container.decodeIfPresent([String].self, forKey: .steps) ?? []
        tips = try container.decodeIfPresent([String].self, forKey: .tips) ?? []
        timeHints = try container.decodeIfPresent([String].self, forKey: .timeHints) ?? []
        sections = try container.decodeIfPresent([SavedRecipeSection].self, forKey: .sections) ?? []
        completedStepKeys = try container.decodeIfPresent([SavedRecipeStepKey].self, forKey: .completedStepKeys) ?? []
        sourceURLString = try container.decodeIfPresent(String.self, forKey: .sourceURLString)
        rawText = try container.decodeIfPresent(String.self, forKey: .rawText) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    var allIngredients: [SavedIngredient] {
        ingredients + sections.flatMap(\.ingredients)
    }

    var totalStepCount: Int {
        steps.count + sections.reduce(0) { $0 + $1.steps.count }
    }
}

struct SavedIngredient: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let amount: String?
    let unit: String?
}

struct SavedRecipeSection: Codable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let ingredients: [SavedIngredient]
    let steps: [String]
}

@MainActor
final class RecipeLibraryStore: ObservableObject {
    @Published private(set) var recipes: [SavedRecipe] = []

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        loadRecipes()
    }

    @discardableResult
    func saveRecipe(
        from draft: RecipeDraft,
        rawText: String,
        category: String?,
        sourceURLString: String? = nil
    ) -> SavedRecipe {
        let normalizedCategory = normalizedCategoryName(category)
        let recipe = SavedRecipe(
            id: UUID(),
            title: draft.title.isEmpty ? defaultTitle() : draft.title,
            category: normalizedCategory,
            rating: nil,
            ingredients: draft.ingredients.map {
                SavedIngredient(id: UUID(), name: $0.name, amount: $0.amount, unit: $0.unit)
            },
            steps: draft.steps,
            tips: draft.tips,
            timeHints: draft.timeHints,
            sections: draft.sections.map { section in
                SavedRecipeSection(
                    id: UUID(),
                    title: section.title,
                    ingredients: section.ingredients.map {
                        SavedIngredient(id: UUID(), name: $0.name, amount: $0.amount, unit: $0.unit)
                    },
                    steps: section.steps
                )
            },
            completedStepKeys: [],
            sourceURLString: normalizedSourceURLString(sourceURLString),
            rawText: rawText,
            createdAt: Date()
        )

        recipes.insert(recipe, at: 0)
        persistRecipes()
        return recipe
    }

    func deleteRecipe(id: UUID) {
        recipes.removeAll { $0.id == id }
        persistRecipes()
    }

    func recipe(id: UUID) -> SavedRecipe? {
        recipes.first { $0.id == id }
    }

    func updateRecipe(_ recipe: SavedRecipe) {
        guard let index = recipes.firstIndex(where: { $0.id == recipe.id }) else {
            return
        }

        recipes[index] = recipe
        persistRecipes()
    }

    func updateRating(_ rating: RecipeRating?, for recipeID: UUID) {
        guard let recipe = recipe(id: recipeID) else {
            return
        }

        let updatedRecipe = SavedRecipe(
            id: recipe.id,
            title: recipe.title,
            category: recipe.category,
            rating: rating,
            ingredients: recipe.ingredients,
            steps: recipe.steps,
            tips: recipe.tips,
            timeHints: recipe.timeHints,
            sections: recipe.sections,
            completedStepKeys: recipe.completedStepKeys,
            sourceURLString: recipe.sourceURLString,
            rawText: recipe.rawText,
            createdAt: recipe.createdAt
        )

        updateRecipe(updatedRecipe)
    }

    func clearCategory(named name: String) {
        let normalizedTarget = normalizedCategoryName(name)
        guard let normalizedTarget else { return }

        recipes = recipes.map { recipe in
            guard normalizedCategoryName(recipe.category) == normalizedTarget else {
                return recipe
            }

            return SavedRecipe(
                id: recipe.id,
                title: recipe.title,
                category: nil,
                rating: recipe.rating,
                ingredients: recipe.ingredients,
                steps: recipe.steps,
                tips: recipe.tips,
                timeHints: recipe.timeHints,
                sections: recipe.sections,
                completedStepKeys: recipe.completedStepKeys,
                sourceURLString: recipe.sourceURLString,
                rawText: recipe.rawText,
                createdAt: recipe.createdAt
            )
        }

        persistRecipes()
    }

    func updateCompletedStepKeys(_ completedStepKeys: Set<SavedRecipeStepKey>, for recipeID: UUID) {
        guard let recipe = recipe(id: recipeID) else {
            return
        }

        let updatedRecipe = SavedRecipe(
            id: recipe.id,
            title: recipe.title,
            category: recipe.category,
            rating: recipe.rating,
            ingredients: recipe.ingredients,
            steps: recipe.steps,
            tips: recipe.tips,
            timeHints: recipe.timeHints,
            sections: recipe.sections,
            completedStepKeys: normalizedCompletedStepKeys(completedStepKeys),
            sourceURLString: recipe.sourceURLString,
            rawText: recipe.rawText,
            createdAt: recipe.createdAt
        )

        updateRecipe(updatedRecipe)
    }

    func replaceAllRecipes(_ recipes: [SavedRecipe]) {
        self.recipes = recipes.sorted { $0.createdAt > $1.createdAt }
        persistRecipes()
    }

    func exportedRecipes() -> [SavedRecipe] {
        recipes
    }

    private func loadRecipes() {
        do {
            let url = try storageURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                recipes = []
                return
            }

            let data = try Data(contentsOf: url)
            recipes = try decoder.decode([SavedRecipe].self, from: data)
        } catch {
            recipes = []
            print("Failed to load saved recipes: \(error.localizedDescription)")
        }
    }

    private func persistRecipes() {
        do {
            let url = try storageURL()
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(recipes)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to save recipes: \(error.localizedDescription)")
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
            .appendingPathComponent("recipes.json")
    }

    private func defaultTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Saved Recipe \(formatter.string(from: Date()))"
    }

    private func normalizedCategoryName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedSourceURLString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else {
            return nil
        }
        return trimmed
    }

    private func normalizedCompletedStepKeys(_ keys: Set<SavedRecipeStepKey>) -> [SavedRecipeStepKey] {
        keys.sorted { lhs, rhs in
            let lhsSection = lhs.sectionID?.uuidString ?? ""
            let rhsSection = rhs.sectionID?.uuidString ?? ""

            if lhsSection == rhsSection {
                return lhs.stepIndex < rhs.stepIndex
            }

            return lhsSection < rhsSection
        }
    }
}
