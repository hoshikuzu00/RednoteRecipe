import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct AddRecipeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var recipeLibraryStore: RecipeLibraryStore
    @EnvironmentObject private var openAISettingsStore: OpenAISettingsStore
    @EnvironmentObject private var localBackendSettingsStore: LocalBackendSettingsStore
    @EnvironmentObject private var categoryStore: CategoryStore

    @StateObject private var viewModel = OCRViewModel()
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var isFileImporterPresented = false
    @State private var isVideoFileImporterPresented = false
    @State private var linkInput = ""
    @State private var selectedCategory = ""
    @State private var isCategoryManagerPresented = false
    @State private var isManualComposerPresented = false

    let onSaved: (SavedRecipe) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    introCard
                    categorySection
                    manualRecipeSection
                    pickerSection
                    videoPickerSection
                    linkImportSection
                    statusSection
                    previewSection
                    parsedRecipeSection
                    resultSection
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Add Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveRecipe()
                    }
                    .disabled(!hasParsedRecipe)
                }
            }
        }
        .sheet(isPresented: $isCategoryManagerPresented) {
            CategoryManagerView()
        }
        .sheet(isPresented: $isManualComposerPresented) {
            ManualRecipeComposerView { draft in
                viewModel.setManualRecipe(draft)
            }
        }
        .onChange(of: selectedItems) { _, newItems in
            guard !newItems.isEmpty else { return }

            let items = newItems
            selectedItems = []

            Task {
                await viewModel.loadImages(
                    from: items,
                    apiKey: openAISettingsStore.configuredAPIKey
                )
            }
        }
        .onChange(of: selectedVideoItem) { _, newItem in
            guard let item = newItem else { return }

            selectedVideoItem = nil

            Task {
                await viewModel.loadVideo(
                    from: item,
                    apiKey: openAISettingsStore.configuredAPIKey
                )
            }
        }
        .keyboardDismissSupport()
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add a Recipe")
                .font(.title2.weight(.bold))
            Text(introDescription)
                .foregroundStyle(.secondary)
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

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Category")
                .font(.headline)

            Picker("Category", selection: $selectedCategory) {
                Text("Uncategorized").tag("")
                ForEach(categoryStore.categories, id: \.self) { category in
                    Text(category).tag(category)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button("Manage Categories") {
                isCategoryManagerPresented = true
            }
            .buttonStyle(.bordered)
        }
    }

    private var pickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import from Images")
                .font(.headline)

            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 12,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label("Select Multiple Photos", systemImage: "photo.on.rectangle.angled")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Button {
                isFileImporterPresented = true
            } label: {
                Label("Import From Files", systemImage: "folder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.secondarySystemGroupedBackground))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.image],
                allowsMultipleSelection: true
            ) { result in
                Task {
                    await viewModel.loadImages(
                        from: result,
                        apiKey: openAISettingsStore.configuredAPIKey
                    )
                }
            }
        }
    }

    private var manualRecipeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Write It Yourself")
                .font(.headline)

            Button {
                isManualComposerPresented = true
            } label: {
                Label("Write Recipe Manually", systemImage: "square.and.pencil")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.brown.opacity(0.12))
                    .foregroundStyle(Color.brown)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Text("如果这次不想导图、不想贴链接，也可以直接手写一份菜谱，然后照常保存进菜谱库。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var videoPickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import from Video")
                .font(.headline)

            PhotosPicker(
                selection: $selectedVideoItem,
                matching: .videos,
                photoLibrary: .shared()
            ) {
                Label("Select Video", systemImage: "video")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.pink.opacity(0.14))
                    .foregroundStyle(Color.pink)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Button {
                isVideoFileImporterPresented = true
            } label: {
                Label("Import Video From Files", systemImage: "film")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.secondarySystemGroupedBackground))
                    .foregroundStyle(Color.pink)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .fileImporter(
                isPresented: $isVideoFileImporterPresented,
                allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
                allowsMultipleSelection: false
            ) { result in
                Task {
                    await viewModel.loadVideo(
                        from: result,
                        apiKey: openAISettingsStore.configuredAPIKey
                    )
                }
            }

            Text("视频导入会先在本地抽取关键帧，再把关键帧交给 GPT-5.4 nano 做结构化识别。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var statusSection: some View {
        Group {
            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var linkImportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import from Link")
                .font(.headline)

            TextField("Paste a recipe link here", text: $linkInput, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 10) {
                Button("Paste Link") {
                    pasteLinkFromClipboard()
                }
                .buttonStyle(.bordered)

                Button("Read Clipboard") {
                    importClipboardLink()
                }
                .buttonStyle(.bordered)
            }

            Button {
                importCurrentLink()
            } label: {
                Label("Import Link", systemImage: "link")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue.opacity(0.12))
                    .foregroundStyle(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(linkInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isRecognizing)

            Text(linkImportDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var previewSection: some View {
        Group {
            if !viewModel.selectedImages.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(previewTitle)
                        .font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(Array(viewModel.selectedImages.enumerated()), id: \.offset) { index, image in
                                VStack(alignment: .leading, spacing: 8) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 180, height: 220)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)

                                    Text("\(previewItemLabel) \(index + 1)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var parsedRecipeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Parsed Recipe")
                    .font(.headline)
                if viewModel.parsingSource != .none {
                    Text(viewModel.parsingSource.label)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            viewModel.parsingSource == .ai
                            ? Color.accentColor.opacity(0.12)
                            : Color(.tertiarySystemGroupedBackground)
                        )
                        .foregroundStyle(viewModel.parsingSource == .ai ? Color.accentColor : Color.secondary)
                        .clipShape(Capsule())
                }
                Spacer()

                if hasParsedRecipe {
                    if viewModel.canRetryAI && openAISettingsStore.isConfigured && !viewModel.isRecognizing {
                        Button("Retry with AI") {
                            Task {
                                await viewModel.retryAIParsing(
                                    apiKey: openAISettingsStore.configuredAPIKey
                                )
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    Button("Copy Summary") {
                        UIPasteboard.general.string = parsedRecipeSummary
                    }
                    .buttonStyle(.bordered)
                }
            }

            if !hasParsedRecipe {
                Text("识别完成后，这里会展示标题、食材、步骤和 tips。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    if !viewModel.parsedRecipe.title.isEmpty {
                        block(title: "Title", content: viewModel.parsedRecipe.title)
                    }

                    if !viewModel.parsedRecipe.ingredients.isEmpty {
                        listBlock(title: "Ingredients", lines: viewModel.parsedRecipe.ingredients.map(ingredientLine(_:)))
                    }

                    if !viewModel.parsedRecipe.sections.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Recipe Parts")
                                .font(.subheadline.weight(.semibold))

                            ForEach(viewModel.parsedRecipe.sections) { section in
                                recipeSectionBlock(section)
                            }
                        }
                    }

                    if !viewModel.parsedRecipe.steps.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Steps")
                                .font(.subheadline.weight(.semibold))

                            ForEach(Array(viewModel.parsedRecipe.steps.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(index + 1)")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 22, height: 22)
                                        .background(Color.accentColor)
                                        .clipShape(Circle())

                                    Text(step)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(12)
                                .background(Color(.tertiarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }

                    if !viewModel.parsedRecipe.tips.isEmpty {
                        listBlock(title: "Tips", lines: viewModel.parsedRecipe.tips)
                    }
                }
                .padding(18)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(sourceTextTitle)
                    .font(.headline)
                Spacer()
                if viewModel.isRecognizing {
                    ProgressView()
                } else if !viewModel.recognizedText.isEmpty {
                    Button("Copy") {
                        UIPasteboard.general.string = viewModel.recognizedText
                    }
                    .buttonStyle(.bordered)
                }
            }

            if viewModel.recognizedText.isEmpty {
                Text(emptySourceTextMessage)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                Text(viewModel.recognizedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .textSelection(.enabled)
            }
        }
    }

    private var sourceTextTitle: String {
        switch viewModel.importContentSource {
        case .link:
            return "Source Text"
        case .video:
            return "Recognized Frame Text"
        case .images, .none:
            return "Recognized Text"
        }
    }

    private var emptySourceTextMessage: String {
        switch viewModel.importContentSource {
        case .link:
            return "链接导入成功后，这里会显示抓到的页面标题、摘要、链接或 fallback 文本。"
        case .video:
            return viewModel.parsingSource == .ai
                ? "这次导入使用了 AI 直接看视频关键帧，所以没有生成 OCR 文本。"
                : "如果回退到本地 OCR，关键帧识别文本会显示在这里。"
        case .images:
            return viewModel.parsingSource == .ai
                ? "这次导入使用了 AI 直接读图，所以没有生成 OCR 文本。"
                : "识别完成后，原始 OCR 文本会显示在这里。"
        case .none:
            return "识别完成后，原始来源文本会显示在这里。"
        }
    }

    private var hasParsedRecipe: Bool {
        !viewModel.parsedRecipe.title.isEmpty ||
        !viewModel.parsedRecipe.ingredients.isEmpty ||
        !viewModel.parsedRecipe.steps.isEmpty ||
        !viewModel.parsedRecipe.tips.isEmpty ||
        !viewModel.parsedRecipe.sections.isEmpty
    }

    private var parsedRecipeSummary: String {
        var lines: [String] = []

        if !viewModel.parsedRecipe.title.isEmpty {
            lines.append("标题: \(viewModel.parsedRecipe.title)")
        }

        if !viewModel.parsedRecipe.ingredients.isEmpty {
            lines.append("食材:")
            lines.append(contentsOf: viewModel.parsedRecipe.ingredients.map { "- " + ingredientLine($0) })
        }

        if !viewModel.parsedRecipe.sections.isEmpty {
            lines.append("分组:")
            for section in viewModel.parsedRecipe.sections {
                lines.append("- \(section.title)")
                if !section.ingredients.isEmpty {
                    lines.append(contentsOf: section.ingredients.map { "  • " + ingredientLine($0) })
                }
                if !section.steps.isEmpty {
                    lines.append(contentsOf: section.steps.enumerated().map { "  \($0.offset + 1). \($0.element)" })
                }
            }
        }

        if !viewModel.parsedRecipe.steps.isEmpty {
            lines.append("步骤:")
            lines.append(contentsOf: viewModel.parsedRecipe.steps.enumerated().map { "\($0.offset + 1). \($0.element)" })
        }

        if !viewModel.parsedRecipe.tips.isEmpty {
            lines.append("Tips:")
            lines.append(contentsOf: viewModel.parsedRecipe.tips.map { "- \($0)" })
        }

        return lines.joined(separator: "\n")
    }

    private func block(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func listBlock(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            ForEach(lines, id: \.self) { line in
                Text(line)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func recipeSectionBlock(_ section: RecipeSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(.subheadline.weight(.semibold))

            if !section.ingredients.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ingredients")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(section.ingredients) { ingredient in
                        Text(ingredientLine(ingredient))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
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
                        Text("\(index + 1). \(step)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func ingredientLine(_ ingredient: RecipeIngredient) -> String {
        let amountUnit = [ingredient.amount, ingredient.unit]
            .compactMap { $0 }
            .joined()

        return amountUnit.isEmpty ? ingredient.name : "\(ingredient.name) \(amountUnit)"
    }

    private var introDescription: String {
        if localBackendSettingsStore.isConfigured && openAISettingsStore.isConfigured {
            return "Import screenshots, a short cooking video, or a recipe link. Screenshot and video imports go straight to GPT-5.4 nano. Link imports try your own Mac backend first, then fall back to public page fetching only if the backend is unavailable."
        }

        if localBackendSettingsStore.isConfigured {
            return "Import screenshots, a short cooking video, or a recipe link. Link imports will try your own Mac backend first, which is usually more reliable than public page scraping."
        }

        return "Import screenshots, a short cooking video, or a recipe link. If your API key is configured, GPT-5.4 nano reads fetched images and key frames directly and only falls back when AI or the page content is unavailable."
    }

    private var previewTitle: String {
        switch viewModel.importContentSource {
        case .video:
            return "Key Frame Preview"
        case .images:
            return "Image Preview"
        case .link:
            return "Imported Image Preview"
        case .none:
            return "Preview"
        }
    }

    private var previewItemLabel: String {
        switch viewModel.importContentSource {
        case .video:
            return "Frame"
        case .images, .link, .none:
            return "Image"
        }
    }

    private var linkImportDescription: String {
        if let backendBaseURL = localBackendSettingsStore.configuredBaseURL {
            return "当前会先请求你的 Mac 后端：\(backendBaseURL.absoluteString)。如果是视频帖，app 会提取视频关键帧并结合帖子文字分析；无法取得视频地址时会使用帖子文字。"
        }

        return "第一版会先尝试读取公开网页里的标题、描述和图片，再把能拿到的内容送进现有的识别流程。配置好你自己的 Mac 后端后，这里会自动优先走后端。"
    }

    private func saveRecipe() {
        if !selectedCategory.isEmpty {
            _ = categoryStore.addCategory(selectedCategory)
        }

        let savedRecipe = recipeLibraryStore.saveRecipe(
            from: viewModel.parsedRecipe,
            rawText: viewModel.recognizedText,
            category: selectedCategory.isEmpty ? nil : selectedCategory,
            sourceURLString: viewModel.sourceLinkURLString
        )

        onSaved(savedRecipe)
        dismiss()
    }

    private func pasteLinkFromClipboard() {
        guard let clipboardValue = clipboardText,
              let extractedURLString = RecipeLinkImporter.firstURLString(in: clipboardValue) else {
            viewModel.statusMessage = "The clipboard does not contain a usable link yet."
            return
        }

        linkInput = extractedURLString
        viewModel.statusMessage = "Filled the link field from your clipboard."
    }

    private func importClipboardLink() {
        guard let clipboardValue = clipboardText,
              let extractedURLString = RecipeLinkImporter.firstURLString(in: clipboardValue) else {
            viewModel.statusMessage = "The clipboard does not contain a usable link yet."
            return
        }

        linkInput = extractedURLString
        importCurrentLink()
    }

    private func importCurrentLink() {
        let candidate = linkInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else {
            viewModel.statusMessage = "Paste a recipe link first."
            return
        }

        Task {
            await viewModel.importRecipe(
                fromLink: candidate,
                apiKey: openAISettingsStore.configuredAPIKey,
                backendBaseURL: localBackendSettingsStore.configuredBaseURL
            )
        }
    }

    private var clipboardText: String? {
        if let value = UIPasteboard.general.string,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }

        if let url = UIPasteboard.general.url {
            return url.absoluteString
        }

        return nil
    }
}
