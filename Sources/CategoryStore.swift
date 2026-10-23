import Foundation

@MainActor
final class CategoryStore: ObservableObject {
    @Published private(set) var categories: [String] = []

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        loadCategories()
    }

    @discardableResult
    func addCategory(_ name: String) -> String? {
        let normalized = normalize(name)
        guard let normalized else { return nil }

        if categories.contains(where: { $0.localizedCaseInsensitiveCompare(normalized) == .orderedSame }) {
            return categories.first(where: { $0.localizedCaseInsensitiveCompare(normalized) == .orderedSame })
        }

        categories.append(normalized)
        categories.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        persistCategories()
        return normalized
    }

    func deleteCategory(_ name: String) {
        categories.removeAll { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }
        persistCategories()
    }

    func replaceAllCategories(_ values: [String]) {
        categories = Array(
            Set(
                values.compactMap { normalize($0) }
            )
        ).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        persistCategories()
    }

    func exportedCategories() -> [String] {
        categories
    }

    private func loadCategories() {
        do {
            let url = try storageURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                categories = []
                return
            }

            let data = try Data(contentsOf: url)
            categories = try decoder.decode([String].self, from: data)
        } catch {
            categories = []
            print("Failed to load categories: \(error.localizedDescription)")
        }
    }

    private func persistCategories() {
        do {
            let url = try storageURL()
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(categories)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to save categories: \(error.localizedDescription)")
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
            .appendingPathComponent("categories.json")
    }

    private func normalize(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
