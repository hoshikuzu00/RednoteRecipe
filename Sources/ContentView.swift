import SwiftUI
import UIKit

extension UIApplication {
    func dismissCurrentKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private struct KeyboardDismissModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                TapGesture().onEnded {
                    UIApplication.shared.dismissCurrentKeyboard()
                }
            )
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.dismissCurrentKeyboard()
                    }
                }
            }
    }
}

extension View {
    func keyboardDismissSupport() -> some View {
        modifier(KeyboardDismissModifier())
    }
}

struct ContentView: View {
    @EnvironmentObject private var recipeLibraryStore: RecipeLibraryStore
    @EnvironmentObject private var shoppingCartStore: ShoppingCartStore
    @EnvironmentObject private var openAISettingsStore: OpenAISettingsStore
    @EnvironmentObject private var localBackendSettingsStore: LocalBackendSettingsStore
    @EnvironmentObject private var categoryStore: CategoryStore

    @State private var selectedSavedRecipe: SavedRecipe?
    @State private var recipeSearchText = ""
    @State private var recipeSortOption: RecipeSortOption = .newest
    @State private var selectedCategoryFilter: String?
    @State private var selectedHomePage: HomePage = .recipes
    @State private var isAISettingsPresented = false
    @State private var isAddRecipePresented = false
    @State private var isCategoryManagerPresented = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                homePageSwitcher

                TabView(selection: $selectedHomePage) {
                    recipeHomePage
                        .tag(HomePage.recipes)

                    shoppingHomePage
                        .tag(HomePage.shopping)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle(selectedHomePage.title)
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAISettingsPresented = true
                    } label: {
                        Image(systemName: isAnyAdvancedImportConfigured ? "gearshape.fill" : "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
        .sheet(item: $selectedSavedRecipe) { recipe in
            SavedRecipeDetailView(recipeID: recipe.id)
        }
        .sheet(isPresented: $isAISettingsPresented) {
            OpenAISettingsView()
        }
        .sheet(isPresented: $isAddRecipePresented) {
            AddRecipeView { recipe in
                selectedSavedRecipe = recipe
            }
        }
        .sheet(isPresented: $isCategoryManagerPresented) {
            CategoryManagerView()
        }
        .onChange(of: availableCategories) { _, newCategories in
            guard let selectedCategoryFilter else { return }
            if !newCategories.contains(selectedCategoryFilter) {
                self.selectedCategoryFilter = nil
            }
        }
        .keyboardDismissSupport()
    }

    private var recipeHomePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                savedRecipesSection
            }
            .padding(.bottom, 24)
        }
    }

    private var shoppingHomePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                shoppingHeaderCard
                shoppingCartSection
            }
            .padding(.bottom, 24)
        }
    }

    private var homePageSwitcher: some View {
        HStack(spacing: 10) {
            ForEach(HomePage.allCases) { page in
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        selectedHomePage = page
                    }
                } label: {
                    Text(page.label)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            selectedHomePage == page
                            ? Color.accentColor
                            : Color(.secondarySystemGroupedBackground)
                        )
                        .foregroundStyle(selectedHomePage == page ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recipe Library")
                        .font(.title2.weight(.bold))
                    Text(headerDescription)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(statusBadgeText)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.82))
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
                Button {
                    isAddRecipePresented = true
                } label: {
                    Label("Add Recipe", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Button {
                    isCategoryManagerPresented = true
                } label: {
                    Label("Manage Categories", systemImage: "square.grid.2x2")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.18), Color.yellow.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var shoppingHeaderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("购物页")
                .font(.title2.weight(.bold))
            Text("这里集中放你从不同菜谱加入的购物项。左右滑动就能在菜谱库和购物车之间切换。")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.green.opacity(0.16), Color.mint.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var savedRecipesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Saved Recipes")
                    .font(.headline)
                Spacer()
                Text("\(filteredRecipes.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search by title, ingredient, tip, or category", text: $recipeSearchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Picker("Sort", selection: $recipeSortOption) {
                    ForEach(RecipeSortOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }

            if !availableCategories.isEmpty {
                categoryFilterSection
            }

            if recipeLibraryStore.recipes.isEmpty {
                Text("保存后的菜谱会出现在这里。点上面的 `Add Recipe`，就能在独立弹窗里导入并保存。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else if filteredRecipes.isEmpty {
                Text("没有找到匹配的菜谱。试试标题关键词、食材名，或者换个分类筛选。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 12) {
                    ForEach(filteredRecipes) { recipe in
                        savedRecipeCard(recipe)
                    }
                }
            }
        }
    }

    private var categoryFilterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Category Filter")
                .font(.subheadline.weight(.semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    filterChip(title: "All", isSelected: selectedCategoryFilter == nil) {
                        selectedCategoryFilter = nil
                    }

                    ForEach(availableCategories, id: \.self) { category in
                        filterChip(title: category, isSelected: selectedCategoryFilter == category) {
                            selectedCategoryFilter = category
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var shoppingCartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Shopping Cart")
                    .font(.headline)
                Spacer()
                Text("\(shoppingCartStore.items.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if shoppingCartStore.items.isEmpty {
                Text("点开任意菜谱后使用 `Add to Shopping List`，食材就会累积到这里。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("\(shoppingCartStore.items.filter(\.isChecked).count) / \(shoppingCartStore.items.count) checked")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear All") {
                            shoppingCartStore.clearAll()
                        }
                        .buttonStyle(.bordered)
                    }

                    VStack(spacing: 10) {
                        ForEach(shoppingCartStore.items) { item in
                            Button {
                                shoppingCartStore.toggleItem(id: item.id)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: item.isChecked ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(item.isChecked ? Color.accentColor : Color.secondary)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(shoppingCartLine(item))
                                            .foregroundStyle(.primary)
                                            .multilineTextAlignment(.leading)
                                            .strikethrough(item.isChecked, color: .secondary)
                                            .opacity(item.isChecked ? 0.55 : 1)

                                        Text(item.sourceRecipeTitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer(minLength: 0)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var headerDescription: String {
        if openAISettingsStore.isConfigured && localBackendSettingsStore.isConfigured {
            return "菜谱库专门负责浏览、搜索、分类和保存结果。导入新菜谱时，图片会默认先让 GPT-5.4 nano 直接读图；链接会先请求你自己的 Mac 后端，再退回公开网页抓取。"
        }

        if openAISettingsStore.isConfigured {
            return "菜谱库专门负责浏览、搜索、分类和保存结果。导入新菜谱时，系统会在独立弹窗里默认先让 GPT-5.4 nano 直接读图并跳过 OCR；如果 AI 不可用，再退回本地 OCR。"
        }

        if localBackendSettingsStore.isConfigured {
            return "菜谱库专门负责浏览、搜索、分类和保存结果。导入新菜谱时，链接会先请求你自己的 Mac 后端；图片识别仍然优先走本地解析。"
        }

        return "菜谱库专门负责浏览、搜索、分类和保存结果。导入新菜谱时，会先做本地 OCR 和本地解析；配置 API key 后会默认切换成 GPT-5.4 nano 直接读图。"
    }

    private var isAnyAdvancedImportConfigured: Bool {
        openAISettingsStore.isConfigured || localBackendSettingsStore.isConfigured
    }

    private var statusBadgeText: String {
        switch (openAISettingsStore.isConfigured, localBackendSettingsStore.isConfigured) {
        case (true, true):
            return "AI + Mac Ready"
        case (true, false):
            return "AI Ready"
        case (false, true):
            return "Mac Link Ready"
        case (false, false):
            return "Local Fallback"
        }
    }

    private var availableCategories: [String] {
        let recipeCategories = recipeLibraryStore.recipes.compactMap(\.category)
        return Array(Set(categoryStore.categories + recipeCategories)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private var filteredRecipes: [SavedRecipe] {
        let query = recipeSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let filtered = recipeLibraryStore.recipes.filter { recipe in
            if let selectedCategoryFilter,
               recipe.category != selectedCategoryFilter {
                return false
            }

            guard !query.isEmpty else { return true }

            let titleMatch = recipe.title.lowercased().contains(query)
            let categoryMatch = recipe.category?.lowercased().contains(query) == true
            let ingredientMatch = recipe.allIngredients.contains { $0.name.lowercased().contains(query) }
            let tipMatch = recipe.tips.contains { $0.lowercased().contains(query) }
            let sectionMatch = recipe.sections.contains {
                $0.title.lowercased().contains(query) ||
                $0.steps.contains(where: { $0.lowercased().contains(query) })
            }

            return titleMatch || categoryMatch || ingredientMatch || tipMatch || sectionMatch
        }

        switch recipeSortOption {
        case .newest:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return filtered.sorted { $0.createdAt < $1.createdAt }
        case .title:
            return filtered.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
    }

    private func savedRecipeCard(_ recipe: SavedRecipe) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    if let category = recipe.category {
                        Text(category)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    Text(recipe.title)
                        .font(.headline)
                    Text(savedRecipeMetadata(recipe))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Button(role: .destructive) {
                    recipeLibraryStore.deleteRecipe(id: recipe.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            if !recipe.allIngredients.isEmpty {
                Text(recipe.allIngredients.prefix(3).map(\.name).joined(separator: " • "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Rating")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(RecipeRating.allCases) { rating in
                        let isSelected = recipe.rating == rating

                        Button {
                            recipeLibraryStore.updateRating(
                                isSelected ? nil : rating,
                                for: recipe.id
                            )
                        } label: {
                            Text(rating.label)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    isSelected
                                    ? Color.accentColor
                                    : Color(.tertiarySystemGroupedBackground)
                                )
                                .foregroundStyle(isSelected ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()
            selectedSavedRecipe = recipe
        }
    }

    private func savedRecipeMetadata(_ recipe: SavedRecipe) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        var parts = [
            "\(recipe.allIngredients.count) ingredients",
            "\(recipe.totalStepCount) steps"
        ]

        if !recipe.sections.isEmpty {
            parts.append("\(recipe.sections.count) parts")
        }

        if let rating = recipe.rating {
            parts.append("评分: \(rating.label)")
        }

        parts.append(formatter.string(from: recipe.createdAt))
        return parts.joined(separator: " • ")
    }

    private func shoppingCartLine(_ item: ShoppingCartItem) -> String {
        let amountUnit = [item.amount, item.unit]
            .compactMap { $0 }
            .joined()

        if amountUnit.isEmpty {
            return item.ingredientName
        }

        return "\(item.ingredientName) \(amountUnit)"
    }
}

private enum RecipeSortOption: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case title

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newest:
            return "Latest"
        case .oldest:
            return "Oldest"
        case .title:
            return "A-Z"
        }
    }
}

private enum HomePage: String, CaseIterable, Identifiable {
    case recipes
    case shopping

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recipes:
            return "Recipes"
        case .shopping:
            return "Shopping Cart"
        }
    }

    var title: String {
        switch self {
        case .recipes:
            return "Recipes"
        case .shopping:
            return "Shopping Cart"
        }
    }
}

private extension SavedRecipeStepKey {
    static func main(_ stepIndex: Int) -> SavedRecipeStepKey {
        SavedRecipeStepKey(sectionID: nil, stepIndex: stepIndex)
    }

    static func section(_ sectionID: UUID, _ stepIndex: Int) -> SavedRecipeStepKey {
        SavedRecipeStepKey(sectionID: sectionID, stepIndex: stepIndex)
    }
}

private struct SavedRecipeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var recipeLibraryStore: RecipeLibraryStore
    @EnvironmentObject private var shoppingCartStore: ShoppingCartStore

    let recipeID: UUID

    @State private var completedStepKeys: Set<SavedRecipeStepKey> = []
    @State private var isEditorPresented = false
    @State private var shoppingListFeedback: String?

    private var recipe: SavedRecipe? {
        recipeLibraryStore.recipe(id: recipeID)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let recipe {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            headerCard(recipe)
                            actionBar(recipe)

                            if let shoppingListFeedback {
                                Text(shoppingListFeedback)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            if let sourceURLString = recipe.sourceURLString {
                                sectionCard(title: "Source Link") {
                                    if let sourceURL = URL(string: sourceURLString) {
                                        Link(destination: sourceURL) {
                                            HStack(alignment: .top, spacing: 10) {
                                                Image(systemName: "link")
                                                    .foregroundStyle(Color.accentColor)

                                                Text(sourceURLString)
                                                    .font(.footnote.monospaced())
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .multilineTextAlignment(.leading)
                                            }
                                            .padding(.vertical, 10)
                                            .padding(.horizontal, 14)
                                            .background(Color(.tertiarySystemGroupedBackground))
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        Text(sourceURLString)
                                            .font(.footnote.monospaced())
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .textSelection(.enabled)
                                    }
                                }
                            }

                            if !recipe.ingredients.isEmpty {
                                sectionCard(title: "Ingredients") {
                                    VStack(alignment: .leading, spacing: 10) {
                                        ForEach(recipe.ingredients) { ingredient in
                                            Text(savedIngredientLine(ingredient))
                                                .font(.system(size: 18))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.vertical, 10)
                                                .padding(.horizontal, 14)
                                                .background(Color(.tertiarySystemGroupedBackground))
                                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        }
                                    }
                                }
                            }

                            if !recipe.sections.isEmpty {
                                sectionCard(title: "Recipe Parts") {
                                    VStack(alignment: .leading, spacing: 14) {
                                        ForEach(recipe.sections) { section in
                                            savedRecipeSectionCard(section)
                                        }
                                    }
                                }
                            }

                            if !recipe.steps.isEmpty {
                                sectionCard(title: "Steps") {
                                    VStack(alignment: .leading, spacing: 12) {
                                        ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                                            Button {
                                                toggleStep(.main(index))
                                            } label: {
                                                HStack(alignment: .top, spacing: 12) {
                                                    Image(systemName: completedStepKeys.contains(.main(index)) ? "checkmark.circle.fill" : "circle")
                                                        .font(.system(size: 18, weight: .semibold))
                                                        .foregroundStyle(completedStepKeys.contains(.main(index)) ? Color.accentColor : Color.secondary)

                                                    VStack(alignment: .leading, spacing: 8) {
                                                        Text("Step \(index + 1)")
                                                            .font(.caption.weight(.semibold))
                                                            .foregroundStyle(.secondary)

                                                        Text(step)
                                                            .font(.system(size: 19))
                                                            .foregroundStyle(.primary)
                                                            .multilineTextAlignment(.leading)
                                                            .strikethrough(completedStepKeys.contains(.main(index)), color: .secondary)
                                                            .opacity(completedStepKeys.contains(.main(index)) ? 0.55 : 1)
                                                    }

                                                    Spacer(minLength: 0)
                                                }
                                                .padding(14)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .background(
                                                    completedStepKeys.contains(.main(index))
                                                    ? Color.accentColor.opacity(0.08)
                                                    : Color(.tertiarySystemGroupedBackground)
                                                )
                                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }

                            if !recipe.tips.isEmpty {
                                sectionCard(title: "Tips") {
                                    VStack(alignment: .leading, spacing: 10) {
                                        ForEach(recipe.tips, id: \.self) { tip in
                                            Text(tip)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.vertical, 10)
                                                .padding(.horizontal, 14)
                                                .background(Color(.tertiarySystemGroupedBackground))
                                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        }
                                    }
                                }
                            }

                        }
                        .padding(20)
                    }
                    .sheet(isPresented: $isEditorPresented) {
                        RecipeEditorView(recipe: recipe)
                    }
                    .onChange(of: recipe.steps.count) {
                        pruneCompletedStepKeys(for: recipe)
                    }
                    .onChange(of: recipe.sections) {
                        pruneCompletedStepKeys(for: recipe)
                    }
                    .onAppear {
                        completedStepKeys = Set(recipe.completedStepKeys)
                    }
                    .onChange(of: recipe.completedStepKeys) { _, newValue in
                        completedStepKeys = Set(newValue)
                    }
                } else {
                    ContentUnavailableView("Recipe Not Found", systemImage: "fork.knife.circle", description: Text("This recipe was deleted or is no longer available."))
                }
            }
            .navigationTitle(recipe?.title ?? "Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Edit") {
                        isEditorPresented = true
                    }
                    .disabled(recipe == nil)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func headerCard(_ recipe: SavedRecipe) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let category = recipe.category {
                Text(category)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.82))
                    .clipShape(Capsule())
            }

            Text(recipe.title)
                .font(.title.bold())

            Text(recipeSummary(for: recipe))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.18), Color.yellow.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func recipeSummary(for recipe: SavedRecipe) -> String {
        var parts = [
            "\(recipe.allIngredients.count) ingredients",
            "\(recipe.totalStepCount) steps"
        ]

        if !recipe.tips.isEmpty {
            parts.append("\(recipe.tips.count) tips")
        }

        if !recipe.sections.isEmpty {
            parts.append("\(recipe.sections.count) parts")
        }

        return parts.joined(separator: " • ")
    }

    private func actionBar(_ recipe: SavedRecipe) -> some View {
        HStack(spacing: 10) {
            Button("Add to Shopping List") {
                let addedCount = shoppingCartStore.addIngredients(from: recipe)
                shoppingListFeedback = "Added \(addedCount) item(s) to your shopping cart."
            }
            .buttonStyle(.borderedProminent)
            .disabled(recipe.allIngredients.isEmpty)

            Button("Reset Checks") {
                completedStepKeys.removeAll()
                persistCompletedStepKeys()
            }
            .buttonStyle(.bordered)
            .disabled(completedStepKeys.isEmpty)
        }
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func toggleStep(_ key: SavedRecipeStepKey) {
        if completedStepKeys.contains(key) {
            completedStepKeys.remove(key)
        } else {
            completedStepKeys.insert(key)
        }

        persistCompletedStepKeys()
    }

    private func pruneCompletedStepKeys(for recipe: SavedRecipe) {
        let validSectionSteps = Dictionary(uniqueKeysWithValues: recipe.sections.map { ($0.id, $0.steps.count) })

        let prunedKeys = completedStepKeys.filter { key in
            if let sectionID = key.sectionID {
                guard let stepCount = validSectionSteps[sectionID] else { return false }
                return key.stepIndex < stepCount
            }

            return key.stepIndex < recipe.steps.count
        }

        if prunedKeys != completedStepKeys {
            completedStepKeys = prunedKeys
            persistCompletedStepKeys()
        }
    }

    private func persistCompletedStepKeys() {
        recipeLibraryStore.updateCompletedStepKeys(completedStepKeys, for: recipeID)
    }

    private func savedIngredientLine(_ ingredient: SavedIngredient) -> String {
        let amountUnit = [ingredient.amount, ingredient.unit]
            .compactMap { $0 }
            .joined()

        if amountUnit.isEmpty {
            return ingredient.name
        }

        return "\(ingredient.name) \(amountUnit)"
    }

    private func savedRecipeSectionCard(_ section: SavedRecipeSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.headline)

            if !section.ingredients.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ingredients")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(section.ingredients) { ingredient in
                        Text(savedIngredientLine(ingredient))
                            .font(.system(size: 18))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }

            if !section.steps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Steps")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(Array(section.steps.enumerated()), id: \.offset) { index, step in
                        Button {
                            toggleStep(.section(section.id, index))
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: completedStepKeys.contains(.section(section.id, index)) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(completedStepKeys.contains(.section(section.id, index)) ? Color.accentColor : Color.secondary)

                                Text("\(index + 1). \(step)")
                                    .font(.system(size: 18))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .multilineTextAlignment(.leading)
                                    .strikethrough(completedStepKeys.contains(.section(section.id, index)), color: .secondary)
                                    .opacity(completedStepKeys.contains(.section(section.id, index)) ? 0.55 : 1)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(
                                completedStepKeys.contains(.section(section.id, index))
                                ? Color.accentColor.opacity(0.08)
                                : Color(.tertiarySystemGroupedBackground)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
