import SwiftUI

struct CategoryManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var categoryStore: CategoryStore
    @EnvironmentObject private var recipeLibraryStore: RecipeLibraryStore

    @State private var newCategoryName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Create Category") {
                    TextField("Category name", text: $newCategoryName)

                    Button("Add Category") {
                        addCategory()
                    }
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Existing Categories") {
                    if categoryStore.categories.isEmpty {
                        Text("Create a few categories so you can organize your saved recipes.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(categoryStore.categories, id: \.self) { category in
                            HStack {
                                Text(category)
                                Spacer()
                                Button(role: .destructive) {
                                    categoryStore.deleteCategory(category)
                                    recipeLibraryStore.clearCategory(named: category)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func addCategory() {
        guard categoryStore.addCategory(newCategoryName) != nil else { return }
        newCategoryName = ""
    }
}
