import SwiftUI
import UniformTypeIdentifiers

struct AppBackupPayload: Codable {
    let version: Int
    let exportedAt: Date
    let recipes: [SavedRecipe]
    let categories: [String]
    let shoppingCartItems: [ShoppingCartItem]

    static func make(
        recipes: [SavedRecipe],
        categories: [String],
        shoppingCartItems: [ShoppingCartItem]
    ) -> AppBackupPayload {
        AppBackupPayload(
            version: 1,
            exportedAt: Date(),
            recipes: recipes,
            categories: categories,
            shoppingCartItems: shoppingCartItems
        )
    }
}

struct AppBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var payload: AppBackupPayload

    init(payload: AppBackupPayload) {
        self.payload = payload
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        payload = try decoder.decode(AppBackupPayload.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        return .init(regularFileWithContents: data)
    }
}

private struct BackupRecipeSelection: Identifiable {
    let id = UUID()
    let recipe: SavedRecipe
    var isSelected: Bool
}

private struct PendingBackupImport {
    var recipeSelections: [BackupRecipeSelection]
    let automaticallyImportedCount: Int

    static func make(payload: AppBackupPayload, existingRecipes: [SavedRecipe]) -> PendingBackupImport {
        let existingTitles = Set(
            existingRecipes.map { normalizedRecipeTitle($0.title) }
        )
        var automaticallyImportedCount = 0

        let selections = payload.recipes.compactMap { recipe -> BackupRecipeSelection? in
            let hasConflict = existingTitles.contains(normalizedRecipeTitle(recipe.title))
            guard hasConflict else {
                automaticallyImportedCount += 1
                return nil
            }

            return BackupRecipeSelection(
                recipe: recipe,
                isSelected: false
            )
        }

        return PendingBackupImport(
            recipeSelections: selections,
            automaticallyImportedCount: automaticallyImportedCount
        )
    }

    var selectedRecipeCount: Int {
        recipeSelections.filter(\.isSelected).count
    }
}

private struct ShoppingCartMergeSignature: Hashable {
    let ingredientName: String
    let amount: String?
    let unit: String?
    let sourceRecipeTitle: String
    let isChecked: Bool
    let createdAt: Date
}

private func normalizedRecipeTitle(_ title: String) -> String {
    title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

private extension SavedRecipe {
    func clonedForImport() -> SavedRecipe {
        let sectionIDMap = Dictionary(uniqueKeysWithValues: sections.map { ($0.id, UUID()) })
        let clonedSections = sections.map { section in
            SavedRecipeSection(
                id: sectionIDMap[section.id] ?? UUID(),
                title: section.title,
                ingredients: section.ingredients.map {
                    SavedIngredient(
                        id: UUID(),
                        name: $0.name,
                        amount: $0.amount,
                        unit: $0.unit
                    )
                },
                steps: section.steps
            )
        }
        let clonedCompletedStepKeys = completedStepKeys.map { key in
            SavedRecipeStepKey(
                sectionID: key.sectionID.flatMap { sectionIDMap[$0] },
                stepIndex: key.stepIndex
            )
        }

        return SavedRecipe(
            id: UUID(),
            title: title,
            category: category,
            rating: rating,
            ingredients: ingredients.map {
                SavedIngredient(
                    id: UUID(),
                    name: $0.name,
                    amount: $0.amount,
                    unit: $0.unit
                )
            },
            steps: steps,
            tips: tips,
            timeHints: timeHints,
            sections: clonedSections,
            completedStepKeys: clonedCompletedStepKeys,
            sourceURLString: sourceURLString,
            rawText: rawText,
            createdAt: createdAt
        )
    }
}

private extension ShoppingCartItem {
    var mergeSignature: ShoppingCartMergeSignature {
        ShoppingCartMergeSignature(
            ingredientName: ingredientName,
            amount: amount,
            unit: unit,
            sourceRecipeTitle: sourceRecipeTitle,
            isChecked: isChecked,
            createdAt: createdAt
        )
    }

    func clonedForImport() -> ShoppingCartItem {
        ShoppingCartItem(
            id: UUID(),
            ingredientName: ingredientName,
            amount: amount,
            unit: unit,
            sourceRecipeTitle: sourceRecipeTitle,
            isChecked: isChecked,
            createdAt: createdAt
        )
    }
}

struct OpenAISettingsView: View {
    private enum FocusField {
        case apiKey
        case backendURL
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var openAISettingsStore: OpenAISettingsStore
    @EnvironmentObject private var localBackendSettingsStore: LocalBackendSettingsStore
    @EnvironmentObject private var recipeLibraryStore: RecipeLibraryStore
    @EnvironmentObject private var categoryStore: CategoryStore
    @EnvironmentObject private var shoppingCartStore: ShoppingCartStore

    @State private var apiKeyDraft = ""
    @State private var backendURLDraft = ""
    @State private var apiFeedbackMessage: String?
    @State private var backendFeedbackMessage: String?
    @State private var backupFeedbackMessage: String?
    @State private var isKeyVisible = false
    @State private var isTestingOpenAIConnection = false
    @State private var isBackupExporterPresented = false
    @State private var isBackupImporterPresented = false
    @State private var pendingBackupImport: PendingBackupImport?
    @FocusState private var focusedField: FocusField?

    var body: some View {
        NavigationStack {
            Form {
                Section("AI Parsing") {
                    Text(openAISettingsStore.isConfigured
                        ? "GPT-5.4 nano is active by default for recipe parsing."
                        : "Add your OpenAI API key here and the app will automatically use GPT-5.4 nano for recipe parsing.")
                        .foregroundStyle(.secondary)

                    Text("This uses your OpenAI Platform API key, not a ChatGPT subscription.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("Your key stays in this device's Keychain.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let suffix = openAISettingsStore.maskedKeySuffix {
                        Text("Saved key suffix: ...\(suffix)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Text("If the app is running on your iPhone, copy the key on the iPhone itself. Copying it on your Mac only works when Universal Clipboard is active.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Group {
                            if isKeyVisible {
                                TextField("sk-...", text: $apiKeyDraft)
                            } else {
                                SecureField("sk-...", text: $apiKeyDraft)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .apiKey)

                        Button(isKeyVisible ? "Hide" : "Show") {
                            isKeyVisible.toggle()
                        }
                        .buttonStyle(.borderless)
                    }

                    Button("Paste from Clipboard") {
                        pasteFromClipboard()
                    }
                    .buttonStyle(.bordered)

                    if let apiFeedbackMessage {
                        Text(apiFeedbackMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button("Save Key") {
                        saveAPIKey()
                    }
                    .buttonStyle(.borderedProminent)

                    Button(isTestingOpenAIConnection ? "Testing OpenAI..." : "Test OpenAI Connection") {
                        testOpenAIConnection()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTestingOpenAIConnection || !openAISettingsStore.isConfigured)

                    Button("Clear Stored Key", role: .destructive) {
                        clearAPIKey()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!openAISettingsStore.isConfigured)
                }

                Section("Link Import") {
                    Text(localBackendSettingsStore.isConfigured
                        ? "Link imports will try your Mac backend first."
                        : "Optional: add a local backend URL if you want link imports to go through your own Mac before the app falls back to shared-page scraping.")
                        .foregroundStyle(.secondary)

                    Text("Automatic local discovery is turned off. The app will use your saved backend URL directly. On your real iPhone, keep using your Mac's current local IP on the same network.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if !localBackendSettingsStore.discoveryStatusMessage.isEmpty {
                        Text(localBackendSettingsStore.discoveryStatusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            TextField("http://192.168.1.23:8080", text: $backendURLDraft)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .focused($focusedField, equals: .backendURL)
                                .submitLabel(.done)

                            if !backendURLDraft.isEmpty {
                                Button {
                                    backendURLDraft = ""
                                    backendFeedbackMessage = nil
                                    focusedField = .backendURL
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        HStack(spacing: 10) {
                            Button("Use Localhost") {
                                backendURLDraft = "http://localhost:8080"
                                backendFeedbackMessage = "Filled with the Simulator localhost URL."
                                focusedField = .backendURL
                            }
                            .buttonStyle(.bordered)

                            Button("Paste Backend URL") {
                                pasteBackendURLFromClipboard()
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if let backendFeedbackMessage {
                        Text(backendFeedbackMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button("Save Backend URL") {
                        saveBackendURL()
                    }

                    Button("Clear Backend URL", role: .destructive) {
                        clearBackendURL()
                    }
                    .disabled(!localBackendSettingsStore.isConfigured)
                }

                Section("Backup & Restore") {
                    Text("Export a backup file with your saved recipes, categories, and shopping cart. Non-conflicting recipes import automatically; only title conflicts need a quick replace-or-duplicate review.")
                        .foregroundStyle(.secondary)

                    Button("Export Backup File") {
                        backupFeedbackMessage = nil
                        isBackupExporterPresented = true
                    }

                    Button("Import Backup File") {
                        backupFeedbackMessage = nil
                        isBackupImporterPresented = true
                    }

                    if let backupFeedbackMessage {
                        Text(backupFeedbackMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                apiKeyDraft = openAISettingsStore.configuredAPIKey ?? ""
                backendURLDraft = localBackendSettingsStore.effectiveBaseURLString
            }
            .fileExporter(
                isPresented: $isBackupExporterPresented,
                document: backupDocument,
                contentType: .json,
                defaultFilename: backupFilename
            ) { result in
                switch result {
                case .success:
                    backupFeedbackMessage = "Backup exported successfully."
                case .failure(let error):
                    backupFeedbackMessage = "Backup export failed: \(error.localizedDescription)"
                }
            }
            .fileImporter(
                isPresented: $isBackupImporterPresented,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                importBackup(from: result)
            }
            .sheet(
                isPresented: Binding(
                    get: { pendingBackupImport != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingBackupImport = nil
                        }
                    }
                )
            ) {
                if pendingBackupImport != nil {
                    BackupImportReviewView(
                        draft: Binding(
                            get: { pendingBackupImport ?? PendingBackupImport(recipeSelections: [], automaticallyImportedCount: 0) },
                            set: { pendingBackupImport = $0 }
                        ),
                        onCancel: {
                            pendingBackupImport = nil
                        },
                        onConfirm: { draft in
                            applyBackupImport(draft)
                        }
                    )
                }
            }
        }
        .keyboardDismissSupport()
    }

    private var backupDocument: AppBackupDocument {
        AppBackupDocument(
            payload: .make(
                recipes: recipeLibraryStore.exportedRecipes(),
                categories: categoryStore.exportedCategories(),
                shoppingCartItems: shoppingCartStore.exportedItems()
            )
        )
    }

    private var backupFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "RednoteOCR-Backup-\(formatter.string(from: Date()))"
    }

    private func saveAPIKey() {
        do {
            focusedField = nil
            try openAISettingsStore.saveAPIKey(apiKeyDraft)
            apiKeyDraft = openAISettingsStore.configuredAPIKey ?? ""
            apiFeedbackMessage = openAISettingsStore.isConfigured
                ? "Key saved to this device. Future imports will automatically use GPT-5.4 nano."
                : "The stored key was cleared."
        } catch {
            apiFeedbackMessage = error.localizedDescription
        }
    }

    private func clearAPIKey() {
        do {
            focusedField = nil
            try openAISettingsStore.clearAPIKey()
            apiKeyDraft = ""
            apiFeedbackMessage = "Stored key removed. The app will fall back to local parsing."
        } catch {
            apiFeedbackMessage = error.localizedDescription
        }
    }

    private func testOpenAIConnection() {
        focusedField = nil
        apiFeedbackMessage = nil
        isTestingOpenAIConnection = true

        Task {
            do {
                let message = try await openAISettingsStore.testConnection()
                await MainActor.run {
                    apiFeedbackMessage = message
                    isTestingOpenAIConnection = false
                }
            } catch {
                await MainActor.run {
                    apiFeedbackMessage = error.localizedDescription
                    isTestingOpenAIConnection = false
                }
            }
        }
    }

    private func saveBackendURL() {
        do {
            try localBackendSettingsStore.saveBaseURL(backendURLDraft)
            backendURLDraft = localBackendSettingsStore.baseURLString
            backendFeedbackMessage = localBackendSettingsStore.isConfigured
                ? "Saved. Future link imports will try your Mac backend first."
                : "The stored backend URL was cleared."
        } catch {
            backendFeedbackMessage = error.localizedDescription
        }
    }

    private func clearBackendURL() {
        localBackendSettingsStore.clearBaseURL()
        backendURLDraft = localBackendSettingsStore.effectiveBaseURLString
        backendFeedbackMessage = "Backend URL reset to the default local address."
    }

    private func pasteFromClipboard() {
        let clipboardCandidate =
            UIPasteboard.general.string ??
            UIPasteboard.general.strings?.first

        guard let clipboardValue = clipboardCandidate?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !clipboardValue.isEmpty else {
            apiFeedbackMessage = "Clipboard is empty on this device. If you're using a real iPhone, copy the key on the phone first or paste manually after tapping Show."
            return
        }

        apiKeyDraft = clipboardValue
        if clipboardValue.hasPrefix("sk-") {
            apiFeedbackMessage = "Pasted from clipboard."
        } else {
            apiFeedbackMessage = "Pasted from clipboard. Double-check that this looks like an OpenAI API key."
        }
    }

    private func pasteBackendURLFromClipboard() {
        let clipboardCandidate =
            UIPasteboard.general.string ??
            UIPasteboard.general.strings?.first

        guard let clipboardValue = clipboardCandidate?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !clipboardValue.isEmpty else {
            backendFeedbackMessage = "Clipboard is empty on this device. Paste your Mac URL manually or copy it on this device first."
            return
        }

        backendURLDraft = clipboardValue
        backendFeedbackMessage = "Pasted backend URL from clipboard."
        focusedField = .backendURL
    }

    private func importBackup(from result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else {
                backupFeedbackMessage = "No backup file was selected."
                return
            }

            let didAccessResource = url.startAccessingSecurityScopedResource()
            defer {
                if didAccessResource {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(AppBackupPayload.self, from: data)
            let importDraft = PendingBackupImport.make(
                payload: payload,
                existingRecipes: recipeLibraryStore.exportedRecipes()
            )

            let existingRecipes = recipeLibraryStore.exportedRecipes()
            let existingTitles = Set(existingRecipes.map { normalizedRecipeTitle($0.title) })
            let nonConflictingRecipes = payload.recipes.filter {
                !existingTitles.contains(normalizedRecipeTitle($0.title))
            }

            if !nonConflictingRecipes.isEmpty {
                var mergedRecipes = existingRecipes
                for recipe in nonConflictingRecipes {
                    mergedRecipes.insert(recipe.clonedForImport(), at: 0)
                }
                recipeLibraryStore.replaceAllRecipes(mergedRecipes.sorted { $0.createdAt > $1.createdAt })
            }

            mergeBackupCategories(payload.categories)
            mergeBackupShoppingCartItems(payload.shoppingCartItems)

            if importDraft.recipeSelections.isEmpty {
                backupFeedbackMessage = "Imported \(importDraft.automaticallyImportedCount) non-conflicting recipe(s). Categories and shopping cart were merged automatically."
                pendingBackupImport = nil
            } else {
                pendingBackupImport = importDraft
                if importDraft.automaticallyImportedCount == 0 {
                    backupFeedbackMessage = "Review \(importDraft.recipeSelections.count) conflicting recipe(s). Checked items will replace existing recipes; unchecked items will keep duplicates."
                } else {
                    backupFeedbackMessage = "Imported \(importDraft.automaticallyImportedCount) non-conflicting recipe(s). Review \(importDraft.recipeSelections.count) conflicts: checked means replace, unchecked keeps duplicates."
                }
            }
        } catch {
            backupFeedbackMessage = "Backup import failed: \(error.localizedDescription)"
        }
    }

    private func applyBackupImport(_ draft: PendingBackupImport) {
        var mergedRecipes = recipeLibraryStore.exportedRecipes()
        let importedCount = draft.recipeSelections.count
        var replacedCount = 0

        for selection in draft.recipeSelections {
            if selection.isSelected {
                let normalizedTitle = normalizedRecipeTitle(selection.recipe.title)
                let beforeCount = mergedRecipes.count
                mergedRecipes.removeAll { normalizedRecipeTitle($0.title) == normalizedTitle }
                if mergedRecipes.count != beforeCount {
                    replacedCount += 1
                }
            }

            mergedRecipes.insert(selection.recipe.clonedForImport(), at: 0)
        }

        recipeLibraryStore.replaceAllRecipes(mergedRecipes.sorted { $0.createdAt > $1.createdAt })

        pendingBackupImport = nil
        backupFeedbackMessage = "Imported \(draft.automaticallyImportedCount + importedCount) recipe(s) in total. Replaced \(replacedCount) existing title match(es)."
    }

    private func mergeBackupCategories(_ categories: [String]) {
        let mergedCategories = Array(
            Set(categoryStore.exportedCategories() + categories)
        ).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        categoryStore.replaceAllCategories(mergedCategories)
    }

    private func mergeBackupShoppingCartItems(_ items: [ShoppingCartItem]) {
        let existingCartItems = shoppingCartStore.exportedItems()
        var seenCartSignatures = Set(existingCartItems.map(\.mergeSignature))
        var mergedCartItems = existingCartItems

        for item in items {
            let clone = item.clonedForImport()
            if seenCartSignatures.insert(clone.mergeSignature).inserted {
                mergedCartItems.append(clone)
            }
        }

        shoppingCartStore.replaceAllItems(mergedCartItems)
    }
}

private struct BackupImportReviewView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var draft: PendingBackupImport

    let onCancel: () -> Void
    let onConfirm: (PendingBackupImport) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Import Summary") {
                    Text("Non-conflicting recipes were already imported automatically. Only the title conflicts are listed here. Turn a recipe on if the imported copy should replace the existing one. Leave it off to keep both copies.")
                        .foregroundStyle(.secondary)

                    Text("\(draft.automaticallyImportedCount) recipe(s) already auto-imported • \(draft.recipeSelections.count) conflict(s) found • \(draft.selectedRecipeCount) marked to replace")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button("Replace All") {
                            for index in draft.recipeSelections.indices {
                                draft.recipeSelections[index].isSelected = true
                            }
                        }
                        .buttonStyle(.bordered)

                        Button("Keep All Duplicates") {
                            for index in draft.recipeSelections.indices {
                                draft.recipeSelections[index].isSelected = false
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Section("Conflicting Recipes") {
                    ForEach(draft.recipeSelections.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(isOn: $draft.recipeSelections[index].isSelected) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(draft.recipeSelections[index].recipe.title)
                                        .font(.headline)

                                    Text(recipeMetadata(draft.recipeSelections[index].recipe))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.switch)

                            Text(draft.recipeSelections[index].isSelected
                                ? "Will replace the existing recipe with the same title."
                                : "Will keep the existing recipe and also import this one as a duplicate.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Other Backup Data") {
                    Text("Categories and shopping cart items were already merged automatically when the backup was loaded. Exact duplicate shopping items from the same backup were skipped.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Merge Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import") {
                        onConfirm(draft)
                        dismiss()
                    }
                }
            }
        }
    }

    private func recipeMetadata(_ recipe: SavedRecipe) -> String {
        var parts = [
            "\(recipe.allIngredients.count) ingredients",
            "\(recipe.totalStepCount) steps"
        ]

        if !recipe.sections.isEmpty {
            parts.append("\(recipe.sections.count) parts")
        }

        if let category = recipe.category, !category.isEmpty {
            parts.append(category)
        }

        return parts.joined(separator: " • ")
    }
}
