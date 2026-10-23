import SwiftUI

private struct RecipeEditorDraft {
    var title: String
    var categoryName: String
    var ingredients: [EditableIngredient]
    var steps: [EditableTextLine]
    var tips: [EditableTextLine]
    var sections: [EditableRecipeSection]

    init(recipe: SavedRecipe) {
        title = recipe.title
        categoryName = recipe.category ?? ""
        ingredients = recipe.ingredients.map {
            EditableIngredient(
                id: $0.id,
                name: $0.name,
                amount: $0.amount ?? "",
                unit: $0.unit ?? ""
            )
        }
        steps = recipe.steps.map { EditableTextLine(text: $0) }
        tips = recipe.tips.map { EditableTextLine(text: $0) }
        sections = recipe.sections.map { section in
            EditableRecipeSection(
                id: section.id,
                title: section.title,
                ingredients: section.ingredients.map {
                    EditableIngredient(
                        id: $0.id,
                        name: $0.name,
                        amount: $0.amount ?? "",
                        unit: $0.unit ?? ""
                    )
                },
                steps: section.steps.map { EditableTextLine(text: $0) }
            )
        }
    }

    func makeRecipe(from original: SavedRecipe) -> SavedRecipe {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedCategory = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)

        let cleanedIngredients = ingredients.compactMap { ingredient -> SavedIngredient? in
            let name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let amount = ingredient.amount.trimmingCharacters(in: .whitespacesAndNewlines)
            let unit = ingredient.unit.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !name.isEmpty else { return nil }

            return SavedIngredient(
                id: ingredient.id,
                name: name,
                amount: amount.isEmpty ? nil : amount,
                unit: unit.isEmpty ? nil : unit
            )
        }

        let cleanedSteps = steps.compactMap(\.cleanedText)
        let cleanedTips = tips.compactMap(\.cleanedText)
        let cleanedSections = sections.compactMap { section -> SavedRecipeSection? in
            let cleanedTitle = section.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanedIngredients = section.ingredients.compactMap { ingredient -> SavedIngredient? in
                let name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let amount = ingredient.amount.trimmingCharacters(in: .whitespacesAndNewlines)
                let unit = ingredient.unit.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !name.isEmpty else { return nil }

                return SavedIngredient(
                    id: ingredient.id,
                    name: name,
                    amount: amount.isEmpty ? nil : amount,
                    unit: unit.isEmpty ? nil : unit
                )
            }
            let cleanedSectionSteps = section.steps.compactMap(\.cleanedText)

            guard !cleanedTitle.isEmpty || !cleanedIngredients.isEmpty || !cleanedSectionSteps.isEmpty else {
                return nil
            }

            return SavedRecipeSection(
                id: section.id,
                title: cleanedTitle.isEmpty ? "Part" : cleanedTitle,
                ingredients: cleanedIngredients,
                steps: cleanedSectionSteps
            )
        }

        return SavedRecipe(
            id: original.id,
            title: cleanedTitle.isEmpty ? original.title : cleanedTitle,
            category: cleanedCategory.isEmpty ? nil : cleanedCategory,
            rating: original.rating,
            ingredients: cleanedIngredients,
            steps: cleanedSteps,
            tips: cleanedTips,
            timeHints: original.timeHints,
            sections: cleanedSections,
            completedStepKeys: original.completedStepKeys,
            sourceURLString: original.sourceURLString,
            rawText: original.rawText,
            createdAt: original.createdAt
        )
    }
}

private struct EditableIngredient: Identifiable {
    let id: UUID
    var name: String
    var amount: String
    var unit: String
}

private struct EditableTextLine: Identifiable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String = "") {
        self.id = id
        self.text = text
    }

    var cleanedText: String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct EditableRecipeSection: Identifiable {
    let id: UUID
    var title: String
    var ingredients: [EditableIngredient]
    var steps: [EditableTextLine]
}

struct RecipeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var recipeLibraryStore: RecipeLibraryStore
    @EnvironmentObject private var categoryStore: CategoryStore

    let originalRecipe: SavedRecipe

    @State private var draft: RecipeEditorDraft
    @State private var isCategoryManagerPresented = false

    init(recipe: SavedRecipe) {
        originalRecipe = recipe
        _draft = State(initialValue: RecipeEditorDraft(recipe: recipe))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Recipe title", text: $draft.title)
                }

                Section("Category") {
                    Picker("Category", selection: $draft.categoryName) {
                        Text("Uncategorized").tag("")
                        ForEach(availableCategories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }

                    Button("Manage Categories") {
                        isCategoryManagerPresented = true
                    }
                }

                Section("Ingredients") {
                    ForEach($draft.ingredients) { $ingredient in
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("Ingredient", text: $ingredient.name)

                            HStack {
                                TextField("Amount", text: $ingredient.amount)
                                TextField("Unit", text: $ingredient.unit)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: deleteIngredients)

                    Button {
                        draft.ingredients.append(
                            EditableIngredient(id: UUID(), name: "", amount: "", unit: "")
                        )
                    } label: {
                        Label("Add Ingredient", systemImage: "plus.circle")
                    }
                }

                editableTextSection(
                    title: "Steps",
                    items: $draft.steps,
                    addLabel: "Add Step",
                    placeholder: "Step"
                )

                editableTextSection(
                    title: "Tips",
                    items: $draft.tips,
                    addLabel: "Add Tip",
                    placeholder: "Tip"
                )

                recipePartsSection
            }
            .navigationTitle("Edit Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let updatedRecipe = draft.makeRecipe(from: originalRecipe)
                        if let category = updatedRecipe.category {
                            _ = categoryStore.addCategory(category)
                        }
                        recipeLibraryStore.updateRecipe(updatedRecipe)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isCategoryManagerPresented) {
                CategoryManagerView()
            }
        }
        .keyboardDismissSupport()
    }

    private var availableCategories: [String] {
        let values = categoryStore.categories + [draft.categoryName]
        return Array(Set(values.filter { !$0.isEmpty })).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    @ViewBuilder
    private func editableTextSection(
        title: String,
        items: Binding<[EditableTextLine]>,
        addLabel: String,
        placeholder: String
    ) -> some View {
        Section(title) {
            ForEach(items) { $item in
                TextField(placeholder, text: $item.text, axis: .vertical)
                    .lineLimit(2...6)
                    .padding(.vertical, 4)
            }
            .onDelete { offsets in
                items.wrappedValue.remove(atOffsets: offsets)
            }

            Button {
                items.wrappedValue.append(EditableTextLine())
            } label: {
                Label(addLabel, systemImage: "plus.circle")
            }
        }
    }

    private func deleteIngredients(at offsets: IndexSet) {
        draft.ingredients.remove(atOffsets: offsets)
    }

    private var recipePartsSection: some View {
        Section("Recipe Parts") {
            if draft.sections.isEmpty {
                Text("No recipe parts yet. Add one if this recipe is split into sections like batter, sauce, or filling.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(draft.sections.indices, id: \.self) { sectionIndex in
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Part title", text: $draft.sections[sectionIndex].title)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ingredients")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(draft.sections[sectionIndex].ingredients.indices, id: \.self) { ingredientIndex in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 10) {
                                    TextField("Ingredient", text: $draft.sections[sectionIndex].ingredients[ingredientIndex].name)

                                    HStack {
                                        TextField("Amount", text: $draft.sections[sectionIndex].ingredients[ingredientIndex].amount)
                                        TextField("Unit", text: $draft.sections[sectionIndex].ingredients[ingredientIndex].unit)
                                    }
                                }

                                Button(role: .destructive) {
                                    draft.sections[sectionIndex].ingredients.remove(at: ingredientIndex)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.borderless)
                            }
                        }

                        Button {
                            draft.sections[sectionIndex].ingredients.append(
                                EditableIngredient(id: UUID(), name: "", amount: "", unit: "")
                            )
                        } label: {
                            Label("Add Part Ingredient", systemImage: "plus.circle")
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Steps")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(draft.sections[sectionIndex].steps.indices, id: \.self) { stepIndex in
                            HStack(alignment: .top, spacing: 10) {
                                TextField(
                                    "Part step",
                                    text: $draft.sections[sectionIndex].steps[stepIndex].text,
                                    axis: .vertical
                                )
                                .lineLimit(2...6)

                                Button(role: .destructive) {
                                    draft.sections[sectionIndex].steps.remove(at: stepIndex)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.borderless)
                            }
                        }

                        Button {
                            draft.sections[sectionIndex].steps.append(EditableTextLine())
                        } label: {
                            Label("Add Part Step", systemImage: "plus.circle")
                        }
                    }

                    Button("Remove Part", role: .destructive) {
                        draft.sections.remove(at: sectionIndex)
                    }
                }
                .padding(.vertical, 6)
            }

            Button {
                draft.sections.append(
                    EditableRecipeSection(
                        id: UUID(),
                        title: "",
                        ingredients: [],
                        steps: []
                    )
                )
            } label: {
                Label("Add Recipe Part", systemImage: "plus.circle")
            }
        }
    }
}

private struct ManualRecipeComposerDraft {
    var title = ""
    var ingredients: [EditableIngredient] = []
    var steps: [EditableTextLine] = []
    var tips: [EditableTextLine] = []
    var sections: [EditableRecipeSection] = []

    func makeRecipeDraft() -> RecipeDraft {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        let cleanedIngredients = ingredients.compactMap { ingredient -> RecipeIngredient? in
            let name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let amount = ingredient.amount.trimmingCharacters(in: .whitespacesAndNewlines)
            let unit = ingredient.unit.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !name.isEmpty else { return nil }

            let rawLine = [name, amount, unit]
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            return RecipeIngredient(
                name: name,
                amount: amount.isEmpty ? nil : amount,
                unit: unit.isEmpty ? nil : unit,
                rawLine: rawLine
            )
        }

        let cleanedSections = sections.compactMap { section -> RecipeSection? in
            let cleanedTitle = section.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanedIngredients = section.ingredients.compactMap { ingredient -> RecipeIngredient? in
                let name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let amount = ingredient.amount.trimmingCharacters(in: .whitespacesAndNewlines)
                let unit = ingredient.unit.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !name.isEmpty else { return nil }

                let rawLine = [name, amount, unit]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")

                return RecipeIngredient(
                    name: name,
                    amount: amount.isEmpty ? nil : amount,
                    unit: unit.isEmpty ? nil : unit,
                    rawLine: rawLine
                )
            }
            let cleanedSteps = section.steps.compactMap(\.cleanedText)

            guard !cleanedTitle.isEmpty || !cleanedIngredients.isEmpty || !cleanedSteps.isEmpty else {
                return nil
            }

            return RecipeSection(
                title: cleanedTitle.isEmpty ? "Part" : cleanedTitle,
                ingredients: cleanedIngredients,
                steps: cleanedSteps
            )
        }

        return RecipeDraft(
            title: cleanedTitle,
            ingredients: cleanedIngredients,
            steps: steps.compactMap(\.cleanedText),
            tips: tips.compactMap(\.cleanedText),
            timeHints: [],
            sections: cleanedSections
        )
    }
}

struct ManualRecipeComposerView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ManualRecipeComposerDraft()

    let onSave: (RecipeDraft) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Recipe title", text: $draft.title)
                }

                Section("Ingredients") {
                    ForEach($draft.ingredients) { $ingredient in
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("Ingredient", text: $ingredient.name)

                            HStack {
                                TextField("Amount", text: $ingredient.amount)
                                TextField("Unit", text: $ingredient.unit)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { offsets in
                        draft.ingredients.remove(atOffsets: offsets)
                    }

                    Button {
                        draft.ingredients.append(
                            EditableIngredient(id: UUID(), name: "", amount: "", unit: "")
                        )
                    } label: {
                        Label("Add Ingredient", systemImage: "plus.circle")
                    }
                }

                manualEditableTextSection(
                    title: "Steps",
                    items: $draft.steps,
                    addLabel: "Add Step",
                    placeholder: "Step"
                )

                manualEditableTextSection(
                    title: "Tips",
                    items: $draft.tips,
                    addLabel: "Add Tip",
                    placeholder: "Tip"
                )

                manualRecipePartsSection
            }
            .navigationTitle("Write Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Use Draft") {
                        onSave(draft.makeRecipeDraft())
                        dismiss()
                    }
                    .disabled(!hasAnyRecipeContent)
                }
            }
        }
        .keyboardDismissSupport()
    }

    private var hasAnyRecipeContent: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        draft.ingredients.contains { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ||
        draft.steps.contains { $0.cleanedText != nil } ||
        draft.tips.contains { $0.cleanedText != nil } ||
        draft.sections.contains {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            $0.ingredients.contains { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ||
            $0.steps.contains { $0.cleanedText != nil }
        }
    }

    @ViewBuilder
    private func manualEditableTextSection(
        title: String,
        items: Binding<[EditableTextLine]>,
        addLabel: String,
        placeholder: String
    ) -> some View {
        Section(title) {
            ForEach(items) { $item in
                TextField(placeholder, text: $item.text, axis: .vertical)
                    .lineLimit(2...6)
                    .padding(.vertical, 4)
            }
            .onDelete { offsets in
                items.wrappedValue.remove(atOffsets: offsets)
            }

            Button {
                items.wrappedValue.append(EditableTextLine())
            } label: {
                Label(addLabel, systemImage: "plus.circle")
            }
        }
    }

    private var manualRecipePartsSection: some View {
        Section("Recipe Parts") {
            if draft.sections.isEmpty {
                Text("Add a part if the recipe has sections like dough, sauce, or filling.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(draft.sections.indices, id: \.self) { sectionIndex in
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Part title", text: $draft.sections[sectionIndex].title)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ingredients")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(draft.sections[sectionIndex].ingredients.indices, id: \.self) { ingredientIndex in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 10) {
                                    TextField("Ingredient", text: $draft.sections[sectionIndex].ingredients[ingredientIndex].name)

                                    HStack {
                                        TextField("Amount", text: $draft.sections[sectionIndex].ingredients[ingredientIndex].amount)
                                        TextField("Unit", text: $draft.sections[sectionIndex].ingredients[ingredientIndex].unit)
                                    }
                                }

                                Button(role: .destructive) {
                                    draft.sections[sectionIndex].ingredients.remove(at: ingredientIndex)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.borderless)
                            }
                        }

                        Button {
                            draft.sections[sectionIndex].ingredients.append(
                                EditableIngredient(id: UUID(), name: "", amount: "", unit: "")
                            )
                        } label: {
                            Label("Add Part Ingredient", systemImage: "plus.circle")
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Steps")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(draft.sections[sectionIndex].steps.indices, id: \.self) { stepIndex in
                            HStack(alignment: .top, spacing: 10) {
                                TextField(
                                    "Part step",
                                    text: $draft.sections[sectionIndex].steps[stepIndex].text,
                                    axis: .vertical
                                )
                                .lineLimit(2...6)

                                Button(role: .destructive) {
                                    draft.sections[sectionIndex].steps.remove(at: stepIndex)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.borderless)
                            }
                        }

                        Button {
                            draft.sections[sectionIndex].steps.append(EditableTextLine())
                        } label: {
                            Label("Add Part Step", systemImage: "plus.circle")
                        }
                    }

                    Button("Remove Part", role: .destructive) {
                        draft.sections.remove(at: sectionIndex)
                    }
                }
                .padding(.vertical, 6)
            }

            Button {
                draft.sections.append(
                    EditableRecipeSection(
                        id: UUID(),
                        title: "",
                        ingredients: [],
                        steps: []
                    )
                )
            } label: {
                Label("Add Recipe Part", systemImage: "plus.circle")
            }
        }
    }
}
