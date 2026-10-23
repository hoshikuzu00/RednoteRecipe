import PhotosUI
import SwiftUI
import Vision

enum RecipeParsingSource {
    case none
    case local
    case ai

    var label: String {
        switch self {
        case .none:
            return ""
        case .local:
            return "Local Parse"
        case .ai:
            return "GPT-5.4 nano"
        }
    }
}

enum RecipeImportContentSource {
    case none
    case images
    case video
    case link
}

enum LinkRecipeParsingMode {
    case textFirst
    case imageFirst
    case mixed

    var inferenceMode: RecipeInferenceMode {
        switch self {
        case .textFirst:
            return .textFirst
        case .imageFirst:
            return .imageFirst
        case .mixed:
            return .mixed
        }
    }

    var loadingMessage: String {
        switch self {
        case .textFirst:
            return "Analyzing linked recipe text with GPT-5.4 nano..."
        case .imageFirst:
            return "Analyzing linked recipe images with GPT-5.4 nano..."
        case .mixed:
            return "Analyzing linked recipe with GPT-5.4 nano using both text and images..."
        }
    }
}

private enum AIParseRetryContext {
    case importedImages([UIImage])
    case importedVideoFrames([UIImage])
    case linkedImages(importedPage: RecipeLinkImportResult, images: [UIImage], mode: LinkRecipeParsingMode)
    case linkedVideo(importedPage: RecipeLinkImportResult, frames: [UIImage])
    case linkedText(importedPage: RecipeLinkImportResult)
}

@MainActor
final class OCRViewModel: ObservableObject {
    @Published var selectedImages: [UIImage] = []
    @Published var recognizedText = ""
    @Published var parsedRecipe = RecipeDraft(
        title: "",
        ingredients: [],
        steps: [],
        tips: [],
        timeHints: [],
        sections: []
    )
    @Published var statusMessage: String?
    @Published var isRecognizing = false
    @Published private(set) var parsingSource: RecipeParsingSource = .none
    @Published private(set) var importContentSource: RecipeImportContentSource = .none
    @Published private(set) var sourceLinkURLString: String?

    private let recipeEnhancer = OpenAIRecipeEnhancer()
    private let backendImporter = RecipeBackendImporter()
    private let linkImporter = RecipeLinkImporter()
    private let remoteMediaSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 180
        return URLSession(configuration: configuration)
    }()
    private var retryContext: AIParseRetryContext?

    var canRetryAI: Bool {
        parsingSource == .local && retryContext != nil
    }

    func loadImages(from items: [PhotosPickerItem], apiKey: String?) async {
        await processImages(apiKey: apiKey, contentSource: .images, loadingStatus: "Loading image set...") {
            var images: [UIImage] = []

            for item in items {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data) else {
                    continue
                }

                images.append(uiImage)
            }

            if images.isEmpty {
                throw OCRViewModelError.noImages
            }

            return images
        }
    }

    func loadImages(from result: Result<[URL], Error>, apiKey: String?) async {
        await processImages(apiKey: apiKey, contentSource: .images, loadingStatus: "Loading image set...") {
            let urls = try result.get()
            guard !urls.isEmpty else {
                throw OCRViewModelError.noImages
            }

            var images: [UIImage] = []

            for url in urls {
                let didAccessResource = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccessResource {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let data = try Data(contentsOf: url)
                guard let uiImage = UIImage(data: data) else {
                    continue
                }

                images.append(uiImage)
            }

            if images.isEmpty {
                throw OCRViewModelError.noImages
            }

            return images
        }
    }

    func loadVideo(from item: PhotosPickerItem, apiKey: String?) async {
        resetState(status: "Loading video...", contentSource: .video)

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw OCRViewModelError.invalidVideo
            }

            let extractedFrames = try await VideoFrameExtractor.extractFrames(fromVideoData: data)
            try validateExtractedVideoFrames(extractedFrames)

            await processPreparedImages(
                extractedFrames,
                apiKey: apiKey,
                contentSource: .video,
                aiStatusMessage: "Analyzing video key frames with GPT-5.4 nano...",
                imagesArePreFilteredForText: true
            )
        } catch is CancellationError {
            statusMessage = "The current video import was cancelled."
            isRecognizing = false
        } catch {
            statusMessage = "Video import failed: \(error.localizedDescription)"
            isRecognizing = false
        }
    }

    func loadVideo(from result: Result<[URL], Error>, apiKey: String?) async {
        resetState(status: "Loading video...", contentSource: .video)

        do {
            let urls = try result.get()
            guard let url = urls.first else {
                throw OCRViewModelError.invalidVideo
            }
            let extractedFrames = try await VideoFrameExtractor.extractFrames(from: url)
            try validateExtractedVideoFrames(extractedFrames)

            await processPreparedImages(
                extractedFrames,
                apiKey: apiKey,
                contentSource: .video,
                aiStatusMessage: "Analyzing video key frames with GPT-5.4 nano...",
                imagesArePreFilteredForText: true
            )
        } catch is CancellationError {
            statusMessage = "The current video import was cancelled."
            isRecognizing = false
        } catch {
            statusMessage = "Video import failed: \(error.localizedDescription)"
            isRecognizing = false
        }
    }

    func setManualRecipe(_ draft: RecipeDraft) {
        selectedImages = []
        recognizedText = ""
        parsedRecipe = draft
        statusMessage = "Manual recipe draft ready to save."
        isRecognizing = false
        parsingSource = .none
        importContentSource = .none
        sourceLinkURLString = nil
        retryContext = nil
    }

    func retryAIParsing(apiKey: String?) async {
        guard parsingSource == .local else {
            statusMessage = "The current recipe is not using a local parse, so there is nothing to retry."
            return
        }

        guard let retryContext else {
            statusMessage = "There is no saved image, video, or link context to retry with AI."
            return
        }

        guard let trimmedAPIKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedAPIKey.isEmpty else {
            statusMessage = "Add an OpenAI API key first, then the app can retry with AI."
            return
        }

        isRecognizing = true

        do {
            switch retryContext {
            case .importedImages(let images):
                guard !images.isEmpty else { throw OCRViewModelError.noImages }
                selectedImages = images
                statusMessage = "Retrying image parsing with GPT-5.4 nano..."
                let enhancedDraft = try await recipeEnhancer.enhanceRecipe(
                    from: images,
                    supplementalText: "",
                    localDraft: parsedRecipe,
                    apiKey: trimmedAPIKey,
                    mode: .imageFirst
                )
                recognizedText = ""
                parsedRecipe = enhancedDraft
                parsingSource = .ai
                statusMessage = "Parsed \(images.count) image(s) with GPT-5.4 nano."

            case .importedVideoFrames(let frames):
                guard !frames.isEmpty else { throw OCRViewModelError.noVideoFrames }
                selectedImages = frames
                statusMessage = "Retrying video key frame parsing with GPT-5.4 nano..."
                let enhancedDraft = try await recipeEnhancer.enhanceRecipe(
                    from: frames,
                    supplementalText: "",
                    localDraft: parsedRecipe,
                    apiKey: trimmedAPIKey,
                    mode: .imageFirst
                )
                recognizedText = ""
                parsedRecipe = enhancedDraft
                parsingSource = .ai
                statusMessage = "Parsed \(frames.count) key frame(s) from the video with GPT-5.4 nano."

            case .linkedImages(let importedPage, let images, let mode):
                selectedImages = images
                statusMessage = "Retrying linked recipe parsing with GPT-5.4 nano..."
                let enhancedDraft = try await enhanceLinkedRecipe(
                    importedPage: importedPage,
                    linkedImages: images,
                    localDraft: parsedRecipe,
                    mode: mode,
                    apiKey: trimmedAPIKey
                )
                parsedRecipe = enhancedDraft
                parsingSource = .ai
                statusMessage = "Imported recipe from link with GPT-5.4 nano."

            case .linkedVideo(let importedPage, let frames):
                guard !frames.isEmpty else { throw OCRViewModelError.noVideoFrames }
                selectedImages = frames
                statusMessage = "Retrying linked video frames with GPT-5.4 nano..."
                let enhancedDraft = try await recipeEnhancer.enhanceRecipe(
                    from: frames,
                    supplementalText: supplementalText(for: importedPage, imageCount: frames.count),
                    localDraft: parsedRecipe,
                    apiKey: trimmedAPIKey,
                    mode: .imageFirst,
                    pageTitle: importedPage.pageTitle
                )
                parsedRecipe = enhancedDraft
                parsingSource = .ai
                statusMessage = "Imported recipe from linked video with GPT-5.4 nano."

            case .linkedText(let importedPage):
                statusMessage = "Retrying linked text parsing with GPT-5.4 nano..."
                let enhancedDraft = try await recipeEnhancer.enhanceRecipe(
                    from: compactLinkedText(importedPage, maxLines: 28, maxCharacters: 2200),
                    localDraft: parsedRecipe,
                    apiKey: trimmedAPIKey,
                    mode: .textFirst,
                    pageTitle: importedPage.pageTitle
                )
                parsedRecipe = enhancedDraft
                parsingSource = .ai
                statusMessage = "Imported recipe from linked text with GPT-5.4 nano."
            }
        } catch is CancellationError {
            statusMessage = "AI retry was cancelled."
        } catch {
            parsingSource = .local
            statusMessage = "AI retry failed, so the app kept the local parse. \(error.localizedDescription)"
        }

        isRecognizing = false
    }

    private func processImages(
        apiKey: String?,
        contentSource: RecipeImportContentSource,
        loadingStatus: String,
        _ imageProvider: () async throws -> [UIImage]
    ) async {
        resetState(status: loadingStatus, contentSource: contentSource)

        do {
            let images = try await imageProvider()
            await processPreparedImages(
                images,
                apiKey: apiKey,
                contentSource: contentSource,
                aiStatusMessage: "Analyzing \(images.count) image(s) directly with GPT-5.4 nano..."
            )
        } catch is CancellationError {
            statusMessage = "The current import was cancelled."
        } catch {
            statusMessage = "OCR failed: \(error.localizedDescription)"
        }

        isRecognizing = false
    }

    private func processPreparedImages(
        _ images: [UIImage],
        apiKey: String?,
        contentSource: RecipeImportContentSource,
        aiStatusMessage: String,
        imagesArePreFilteredForText: Bool = false
    ) async {
        let textBearingImages = imagesArePreFilteredForText
            ? images
            : await filterImagesLikelyContainingText(images)
        selectedImages = textBearingImages

        let trimmedAPIKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        var aiFailureMessage: String?

        guard !textBearingImages.isEmpty else {
            recognizedText = ""
            parsingSource = .none
            statusMessage = contentSource == .video
                ? "No text-bearing video frames were found, so nothing useful was sent to GPT-5.4 nano."
                : "No text-bearing images were found, so nothing useful was sent to GPT-5.4 nano."
            isRecognizing = false
            return
        }

        switch contentSource {
        case .images:
            retryContext = .importedImages(textBearingImages)
        case .video:
            retryContext = .importedVideoFrames(textBearingImages)
        case .link, .none:
            break
        }

        if let trimmedAPIKey, !trimmedAPIKey.isEmpty {
            statusMessage = aiStatusMessage

            do {
                let enhancedDraft = try await recipeEnhancer.enhanceRecipe(
                    from: textBearingImages,
                    supplementalText: "",
                    localDraft: RecipeDraft(
                        title: "",
                        ingredients: [],
                        steps: [],
                        tips: [],
                        timeHints: [],
                        sections: []
                    ),
                    apiKey: trimmedAPIKey,
                    mode: .imageFirst
                )
                recognizedText = ""
                parsedRecipe = enhancedDraft
                parsingSource = .ai
                statusMessage = successStatusMessage(for: contentSource, imageCount: images.count)
                isRecognizing = false
                return
            } catch is CancellationError {
                statusMessage = contentSource == .video
                    ? "AI video parsing was cancelled, so the app stopped the current import."
                    : "AI image parsing was cancelled, so the app stopped the current import."
                isRecognizing = false
                return
            } catch {
                aiFailureMessage = error.localizedDescription
                statusMessage = fallbackPreparationMessage(for: contentSource, aiFailureMessage: error.localizedDescription)
            }
        }

        statusMessage = trimmedAPIKey?.isEmpty == false
            ? localFallbackStatusMessage(for: contentSource)
            : localPreparationStatusMessage(for: contentSource)

        var pageTexts: [String] = []

        for image in textBearingImages {
            let text = (try? await recognizeText(in: image)) ?? ""
            pageTexts.append(text)
        }

        let combinedText = pageTexts.joined(separator: "\n")
        recognizedText = pageTexts.enumerated().map { index, text in
            "\(contentSource == .video ? "Frame" : "Page") \(index + 1)\n\(text)"
        }
        .joined(separator: "\n\n")

        let localDraft = RecipeParser.parse(combinedText)
        parsedRecipe = localDraft
        parsingSource = .local

        guard !combinedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if let aiFailureMessage {
                statusMessage = "No text found in the selected \(contentSource == .video ? "video frames" : "images"), and AI parsing also failed. \(aiFailureMessage)"
            } else {
                statusMessage = "No text found in the selected \(contentSource == .video ? "video frames" : "images")."
            }
            isRecognizing = false
            return
        }

        if let aiFailureMessage {
            statusMessage = localCompletionStatusMessage(for: contentSource, imageCount: textBearingImages.count, aiFailureMessage: aiFailureMessage)
        } else {
            statusMessage = localCompletionStatusMessage(for: contentSource, imageCount: textBearingImages.count, aiFailureMessage: nil)
        }
    }

    func importRecipe(fromLink rawInput: String, apiKey: String?, backendBaseURL: URL?) async {
        let initialStatus = backendBaseURL == nil
            ? "Opening recipe link..."
            : "Contacting your Mac backend..."
        resetState(status: initialStatus, contentSource: .link)

        do {
            let importedPage: RecipeLinkImportResult

            if let backendBaseURL {
                do {
                    importedPage = try await backendImporter.importRecipe(
                        from: rawInput,
                        backendBaseURL: backendBaseURL
                    )
                    statusMessage = "Fetched recipe content from your Mac backend."
                } catch {
                    statusMessage = "Your Mac backend could not be reached, so the app is trying the shared link directly. \(error.localizedDescription)"
                    importedPage = try await linkImporter.importRecipe(from: rawInput)
                }
            } else {
                importedPage = try await linkImporter.importRecipe(from: rawInput)
            }

            let linkedTextImages = await filterImagesLikelyContainingText(importedPage.images)
            selectedImages = linkedTextImages
            recognizedText = importedPage.sourceText
            sourceLinkURLString = importedPage.originalURL.absoluteString

            let localDraft = localDraft(for: importedPage)
            let trimmedAPIKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)

            if importedPage.mediaKind == .video {
                try await handleLinkedVideoImport(
                    importedPage: importedPage,
                    localDraft: localDraft,
                    apiKey: trimmedAPIKey
                )
                isRecognizing = false
                return
            }

            let linkMode = preferredLinkParsingMode(imageCount: linkedTextImages.count)
            retryContext = linkedTextImages.isEmpty
                ? .linkedText(importedPage: importedPage)
                : .linkedImages(importedPage: importedPage, images: linkedTextImages, mode: linkMode)
            var aiFailureMessage: String?

            if let trimmedAPIKey, !trimmedAPIKey.isEmpty {
                do {
                    statusMessage = linkMode.loadingMessage

                    let enhancedDraft = try await enhanceLinkedRecipe(
                        importedPage: importedPage,
                        linkedImages: linkedTextImages,
                        localDraft: localDraft,
                        mode: linkMode,
                        apiKey: trimmedAPIKey
                    )

                    parsedRecipe = enhancedDraft
                    parsingSource = .ai
                    statusMessage = "Imported recipe from link with GPT-5.4 nano."
                    isRecognizing = false
                    return
                } catch is CancellationError {
                    statusMessage = "Link import was cancelled."
                    isRecognizing = false
                    return
                } catch {
                    aiFailureMessage = error.localizedDescription
                    statusMessage = "AI link parsing failed, so the app is falling back to the page text. \(error.localizedDescription)"
                }
            }

            if shouldRunImageOCRFallback(for: localDraft, imageCount: linkedTextImages.count) {
                statusMessage = "Running local OCR on linked images..."
                let pageTexts = try await recognizedPageTexts(from: linkedTextImages)
                let ocrText = pageTexts.enumerated().map { index, text in
                    "Linked Image \(index + 1)\n\(text)"
                }
                .joined(separator: "\n\n")
                let combinedSourceText = [importedPage.sourceText, ocrText]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: "\n\n")
                let combinedAnalysisText = [importedPage.analysisText, ocrText]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: "\n\n")

                recognizedText = combinedSourceText
                parsedRecipe = RecipeParser.parse(combinedAnalysisText)
                parsingSource = .local

                if let aiFailureMessage {
                    statusMessage = "Linked page imported with local parsing after GPT-5.4 nano failed. \(aiFailureMessage)"
                } else {
                    statusMessage = "Linked page imported with local parsing."
                }
            } else {
                parsedRecipe = localDraft
                parsingSource = .local

                if let aiFailureMessage {
                    statusMessage = "Linked page imported with local parsing after GPT-5.4 nano failed. \(aiFailureMessage)"
                } else {
                    statusMessage = "Linked page imported with local parsing."
                }
            }
        } catch is CancellationError {
            statusMessage = "Link import was cancelled."
        } catch {
            statusMessage = "Link import failed: \(error.localizedDescription)"
        }

        isRecognizing = false
    }

    private func recognizeText(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw OCRViewModelError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                let joined = lines
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")

                continuation.resume(returning: joined)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func recognizedPageTexts(from images: [UIImage]) async throws -> [String] {
        var pageTexts: [String] = []

        for image in images {
            let text = try await recognizeText(in: image)
            pageTexts.append(text)
        }

        return pageTexts
    }

    private func filterImagesLikelyContainingText(_ images: [UIImage]) async -> [UIImage] {
        var filtered: [UIImage] = []

        for image in images {
            if let containsMeaningfulText = try? await assessMeaningfulText(in: image), containsMeaningfulText {
                filtered.append(image)
            }
        }

        return filtered
    }

    private func assessMeaningfulText(in image: UIImage) async throws -> Bool {
        guard let cgImage = image.cgImage else {
            throw OCRViewModelError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                var lines: [String] = []
                var totalArea: CGFloat = 0
                var maxArea: CGFloat = 0
                var maxWidth: CGFloat = 0

                for observation in observations {
                    guard let candidate = observation.topCandidates(1).first else {
                        continue
                    }

                    let line = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !line.isEmpty else {
                        continue
                    }

                    lines.append(line)
                    let box = observation.boundingBox
                    let area = box.width * box.height
                    totalArea += area
                    maxArea = max(maxArea, area)
                    maxWidth = max(maxWidth, box.width)
                }

                let joined = lines.joined(separator: "\n")
                let signature = joined
                    .lowercased()
                    .unicodeScalars
                    .filter { CharacterSet.alphanumerics.contains($0) }
                let hanCount = joined.unicodeScalars.filter { scalar in
                    switch scalar.value {
                    case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                        return true
                    default:
                        return false
                    }
                }.count

                let hasEnoughCharacters = hanCount >= 2 || signature.count >= 4
                let hasEnoughVisualWeight = totalArea >= 0.004 || maxArea >= 0.0015 || maxWidth >= 0.16 || lines.count >= 2

                continuation.resume(returning: hasEnoughCharacters && hasEnoughVisualWeight)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            request.minimumTextHeight = 0.012

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func resetState(status: String, contentSource: RecipeImportContentSource) {
        isRecognizing = true
        statusMessage = status
        recognizedText = ""
        parsedRecipe = RecipeDraft(
            title: "",
            ingredients: [],
            steps: [],
            tips: [],
            timeHints: [],
            sections: []
        )
        selectedImages = []
        parsingSource = .none
        importContentSource = contentSource
        sourceLinkURLString = nil
        retryContext = nil
    }

    private func validateExtractedVideoFrames(_ frames: [UIImage]) throws {
        guard !frames.isEmpty else {
            throw OCRViewModelError.noVideoFrames
        }
    }

    private func successStatusMessage(for contentSource: RecipeImportContentSource, imageCount: Int) -> String {
        switch contentSource {
        case .video:
            return "Parsed \(imageCount) key frame(s) from the video with GPT-5.4 nano."
        case .images:
            return "Parsed \(imageCount) image(s) directly with GPT-5.4 nano."
        case .link:
            return "Imported recipe from link with GPT-5.4 nano."
        case .none:
            return "Imported recipe with GPT-5.4 nano."
        }
    }

    private func fallbackPreparationMessage(for contentSource: RecipeImportContentSource, aiFailureMessage: String) -> String {
        switch contentSource {
        case .video:
            return "Video frame parsing failed, so the app is falling back to local OCR. \(aiFailureMessage)"
        case .images:
            return "Direct image parsing failed, so the app is falling back to local OCR. \(aiFailureMessage)"
        case .link:
            return "AI link parsing failed, so the app is falling back to the page text. \(aiFailureMessage)"
        case .none:
            return aiFailureMessage
        }
    }

    private func localPreparationStatusMessage(for contentSource: RecipeImportContentSource) -> String {
        switch contentSource {
        case .video:
            return "Preparing local OCR for video frames..."
        case .images:
            return "Preparing local OCR..."
        case .link:
            return "Preparing local parsing..."
        case .none:
            return "Preparing local parsing..."
        }
    }

    private func localFallbackStatusMessage(for contentSource: RecipeImportContentSource) -> String {
        switch contentSource {
        case .video:
            return "Running local OCR on video frames..."
        case .images:
            return "Running local OCR fallback..."
        case .link:
            return "Running local parsing fallback..."
        case .none:
            return "Running local parsing fallback..."
        }
    }

    private func localCompletionStatusMessage(
        for contentSource: RecipeImportContentSource,
        imageCount: Int,
        aiFailureMessage: String?
    ) -> String {
        let base: String

        switch contentSource {
        case .video:
            base = "OCR finished across \(imageCount) key frame(s) from the video."
        case .images:
            base = "OCR finished across \(imageCount) image(s)."
        case .link:
            base = "Linked page imported with local parsing."
        case .none:
            base = "Local parsing finished."
        }

        if let aiFailureMessage, !aiFailureMessage.isEmpty {
            switch contentSource {
            case .video:
                return "\(base) GPT-5.4 nano failed, so the app kept the local parse. \(aiFailureMessage)"
            case .images:
                return "\(base) GPT-5.4 nano failed, so the app kept the local parse. \(aiFailureMessage)"
            case .link:
                return "\(base) \(aiFailureMessage)"
            case .none:
                return "\(base) \(aiFailureMessage)"
            }
        }

        switch contentSource {
        case .video, .images:
            return "\(base) The app kept the local parse."
        case .link, .none:
            return base
        }
    }

    private func enhanceLinkedRecipe(
        importedPage: RecipeLinkImportResult,
        linkedImages: [UIImage],
        localDraft: RecipeDraft,
        mode: LinkRecipeParsingMode,
        apiKey: String
    ) async throws -> RecipeDraft {
        switch mode {
        case .textFirst:
            let textInput = compactLinkedText(importedPage, maxLines: 28, maxCharacters: 2200)
            return try await recipeEnhancer.enhanceRecipe(
                from: textInput,
                localDraft: localDraft,
                apiKey: apiKey,
                mode: .textFirst,
                pageTitle: importedPage.pageTitle
            )
        case .imageFirst, .mixed:
            guard !linkedImages.isEmpty else {
                let textInput = compactLinkedText(importedPage, maxLines: 28, maxCharacters: 2200)
                return try await recipeEnhancer.enhanceRecipe(
                    from: textInput,
                    localDraft: localDraft,
                    apiKey: apiKey,
                    mode: .textFirst,
                    pageTitle: importedPage.pageTitle
                )
            }

            return try await recipeEnhancer.enhanceRecipe(
                from: linkedImages,
                supplementalText: supplementalText(for: importedPage, imageCount: linkedImages.count),
                localDraft: localDraft,
                apiKey: apiKey,
                mode: mode.inferenceMode,
                pageTitle: importedPage.pageTitle
            )
        }
    }

    private func handleLinkedVideoImport(
        importedPage: RecipeLinkImportResult,
        localDraft: RecipeDraft,
        apiKey: String?
    ) async throws {
        retryContext = .linkedText(importedPage: importedPage)

        guard let videoURL = importedPage.videoURL else {
            await parseLinkedTextOnly(
                importedPage: importedPage,
                localDraft: localDraft,
                apiKey: apiKey,
                fallbackMessage: "This looks like a video post, but no usable video stream was found."
            )
            return
        }

        statusMessage = "Extracting key frames from the linked video..."

        let extractedFrames = try await extractLinkedVideoFrames(from: videoURL)
        try validateExtractedVideoFrames(extractedFrames)
        selectedImages = extractedFrames
        retryContext = .linkedVideo(importedPage: importedPage, frames: extractedFrames)

        if let apiKey, !apiKey.isEmpty {
            do {
                statusMessage = "Analyzing linked video frames with GPT-5.4 nano..."
                let enhancedDraft = try await recipeEnhancer.enhanceRecipe(
                    from: extractedFrames,
                    supplementalText: supplementalText(for: importedPage, imageCount: extractedFrames.count),
                    localDraft: localDraft,
                    apiKey: apiKey,
                    mode: .imageFirst,
                    pageTitle: importedPage.pageTitle
                )

                parsedRecipe = enhancedDraft
                parsingSource = .ai
                statusMessage = "Imported recipe from linked video with GPT-5.4 nano."
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                statusMessage = "GPT-5.4 nano could not parse the linked video, so the app is running local OCR on the extracted frames. \(error.localizedDescription)"
            }
        } else {
            statusMessage = "No OpenAI API key is configured, so the app is running local OCR on the linked video frames."
        }

        let frameTexts = try await recognizedPageTexts(from: extractedFrames)
        let frameOCRText = frameTexts.enumerated().map { index, text in
            "Video Frame \(index + 1)\n\(text)"
        }
        .joined(separator: "\n\n")
        let combinedSourceText = [importedPage.sourceText, frameOCRText]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")

        recognizedText = combinedSourceText
        parsedRecipe = self.localDraft(for: importedPage, additionalAnalysisText: frameOCRText)
        parsingSource = .local
        statusMessage = "Linked video imported with local parsing."
    }

    private func localDraft(for importedPage: RecipeLinkImportResult) -> RecipeDraft {
        var draft = RecipeParser.parse(importedPage.analysisText)
        draft.title = RecipeParser.resolvedTitle(
            candidate: importedPage.pageTitle,
            fallback: draft.title,
            ingredientNames: draft.allIngredients.map(\.name)
        )
        return draft
    }

    private func localDraft(
        for importedPage: RecipeLinkImportResult,
        additionalAnalysisText: String
    ) -> RecipeDraft {
        let combinedText = [importedPage.analysisText, additionalAnalysisText]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
        var draft = RecipeParser.parse(combinedText)
        draft.title = RecipeParser.resolvedTitle(
            candidate: importedPage.pageTitle,
            fallback: draft.title,
            ingredientNames: draft.allIngredients.map(\.name)
        )
        return draft
    }

    private func preferredLinkParsingMode(imageCount: Int) -> LinkRecipeParsingMode {
        guard imageCount > 0 else {
            return .textFirst
        }

        if imageCount >= 8 {
            return .imageFirst
        }

        return .mixed
    }

    private func parseLinkedTextOnly(
        importedPage: RecipeLinkImportResult,
        localDraft: RecipeDraft,
        apiKey: String?,
        fallbackMessage: String
    ) async {
        retryContext = .linkedText(importedPage: importedPage)
        let textInput = compactLinkedText(importedPage, maxLines: 28, maxCharacters: 2200)
        let trimmedAPIKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let trimmedAPIKey, !trimmedAPIKey.isEmpty {
            do {
                statusMessage = fallbackMessage

                let enhancedDraft = try await recipeEnhancer.enhanceRecipe(
                    from: textInput,
                    localDraft: localDraft,
                    apiKey: trimmedAPIKey,
                    mode: .textFirst,
                    pageTitle: importedPage.pageTitle
                )
                parsedRecipe = enhancedDraft
                parsingSource = .ai
                statusMessage = "\(fallbackMessage) Imported recipe from linked text with GPT-5.4 nano."
                return
            } catch is CancellationError {
                statusMessage = "Link import was cancelled."
                return
            } catch {
                parsedRecipe = localDraft
                parsingSource = .local
                statusMessage = "\(fallbackMessage) \(error.localizedDescription)"
                return
            }
        }

        parsedRecipe = localDraft
        parsingSource = .local
        statusMessage = fallbackMessage
    }

    private func extractLinkedVideoFrames(from videoURL: URL) async throws -> [UIImage] {
        if videoURL.isFileURL {
            return try await VideoFrameExtractor.extractFrames(from: videoURL)
        }

        if videoURL.scheme?.hasPrefix("http") == true,
           let streamedFrames = try? await VideoFrameExtractor.extractFrames(from: videoURL),
           !streamedFrames.isEmpty {
            return streamedFrames
        }

        var request = URLRequest(url: videoURL)
        request.setValue("video/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await remoteMediaSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<400).contains(httpResponse.statusCode) else {
            throw OCRViewModelError.invalidVideo
        }

        return try await VideoFrameExtractor.extractFrames(fromVideoData: data)
    }

    private func supplementalText(
        for importedPage: RecipeLinkImportResult,
        imageCount: Int
    ) -> String {
        switch imageCount {
        case 12...:
            return compactLinkedText(importedPage, maxLines: 6, maxCharacters: 320)
        case 6...:
            return compactLinkedText(importedPage, maxLines: 10, maxCharacters: 700)
        case 1...:
            return compactLinkedText(importedPage, maxLines: 16, maxCharacters: 1400)
        default:
            return compactLinkedText(importedPage, maxLines: 20, maxCharacters: 1600)
        }
    }

    private func compactLinkedText(
        _ importedPage: RecipeLinkImportResult,
        maxLines: Int,
        maxCharacters: Int
    ) -> String {
        var lines: [String] = []

        if !importedPage.pageTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Page Title: \(importedPage.pageTitle)")
        }

        let bodyLines = importedPage.bodyText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !$0.hasPrefix("#") && !$0.contains("[话题]") && !$0.contains("[話題]") }

        for line in bodyLines {
            guard !lines.contains(line) else { continue }
            lines.append(line)
            if lines.count >= maxLines {
                break
            }
        }

        if lines.isEmpty {
            return importedPage.analysisText
        }

        let compacted = lines.joined(separator: "\n")
        if compacted.count <= maxCharacters {
            return compacted
        }

        let cutoffIndex = compacted.index(compacted.startIndex, offsetBy: maxCharacters)
        return String(compacted[..<cutoffIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parsedRecipeIsEmpty(_ draft: RecipeDraft) -> Bool {
        draft.title.isEmpty &&
        draft.ingredients.isEmpty &&
        draft.sections.isEmpty &&
        draft.steps.isEmpty &&
        draft.tips.isEmpty &&
        draft.timeHints.isEmpty
    }

    private func shouldRunImageOCRFallback(
        for draft: RecipeDraft,
        imageCount: Int
    ) -> Bool {
        guard imageCount > 0 else { return false }

        if parsedRecipeIsEmpty(draft) {
            return true
        }

        return draft.totalStepCount == 0 &&
        draft.allIngredients.count <= 2 &&
        draft.sections.isEmpty
    }
}

enum OCRViewModelError: LocalizedError {
    case invalidImage
    case noImages
    case invalidVideo
    case noVideoFrames

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The selected image format is not supported."
        case .noImages:
            return "No usable images were selected."
        case .invalidVideo:
            return "The selected video could not be loaded."
        case .noVideoFrames:
            return "The video did not produce any usable key frames."
        }
    }
}
