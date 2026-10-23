import Foundation
import UIKit

enum RecipeInferenceMode {
    case textFirst
    case imageFirst
    case mixed
}

struct RecipeTitleAssessment {
    let openingTitleCandidate: String
    let inferredDishName: String
    let finalTitle: String
    let titleMakesSense: Bool
    let reason: String
}

struct OpenAIRecipeEnhancer {
    private let maxImageDimension: CGFloat = 1400
    private let jpegCompressionQuality: CGFloat = 0.82

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 90
        return URLSession(configuration: configuration)
    }()

    private let decoder = JSONDecoder()
    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    private let model = "gpt-5.4-nano"

    func enhanceRecipe(
        from images: [UIImage],
        supplementalText: String,
        localDraft: RecipeDraft,
        apiKey: String,
        mode: RecipeInferenceMode = .imageFirst,
        pageTitle: String? = nil
    ) async throws -> RecipeDraft {
        guard !images.isEmpty else {
            throw OpenAIRecipeEnhancerError.missingOutput
        }

        let body = try makeImageRequestBody(
            images: images,
            supplementalText: supplementalText,
            mode: mode,
            pageTitle: pageTitle
        )
        var draft = try await performRequest(body: body, fallback: localDraft, apiKey: apiKey)
        do {
            draft = try await finalizeTitle(
                for: draft,
                sourceText: supplementalText,
                fallback: localDraft,
                apiKey: apiKey,
                pageTitle: pageTitle
            )
        } catch let promptError as RecipeParserSkillPromptError {
            throw promptError
        } catch {
            // Keep the main recipe parse if the title-only pass fails.
        }
        return draft
    }

    func enhanceRecipe(
        from recognizedText: String,
        localDraft: RecipeDraft,
        apiKey: String,
        mode: RecipeInferenceMode = .textFirst,
        pageTitle: String? = nil
    ) async throws -> RecipeDraft {
        guard !recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return localDraft
        }

        let body = try makeRequestBody(
            recognizedText: recognizedText,
            mode: mode,
            pageTitle: pageTitle
        )
        var draft = try await performRequest(body: body, fallback: localDraft, apiKey: apiKey)
        do {
            draft = try await finalizeTitle(
                for: draft,
                sourceText: recognizedText,
                fallback: localDraft,
                apiKey: apiKey,
                pageTitle: pageTitle
            )
        } catch let promptError as RecipeParserSkillPromptError {
            throw promptError
        } catch {
            // Keep the main recipe parse if the title-only pass fails.
        }
        return draft
    }

    private func performRequest(
        body: [String: Any],
        fallback: RecipeDraft,
        apiKey: String
    ) async throws -> RecipeDraft {
        let aiDraft: OpenAIRecipeDraft = try await performStructuredRequest(body: body, apiKey: apiKey)
        return aiDraft.makeRecipeDraft(fallback: fallback)
    }

    private func performTitleRequest(
        body: [String: Any],
        apiKey: String
    ) async throws -> RecipeTitleAssessment {
        let assessment: OpenAIRecipeTitleResponse = try await performStructuredRequest(body: body, apiKey: apiKey)
        return RecipeTitleAssessment(
            openingTitleCandidate: assessment.openingTitleCandidate.trimmingCharacters(in: .whitespacesAndNewlines),
            inferredDishName: assessment.inferredDishName.trimmingCharacters(in: .whitespacesAndNewlines),
            finalTitle: assessment.finalTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            titleMakesSense: assessment.titleMakesSense,
            reason: assessment.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func performStructuredRequest<Response: Decodable>(
        body: [String: Any],
        apiKey: String
    ) async throws -> Response {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIRecipeEnhancerError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let apiError = try? decoder.decode(OpenAIAPIErrorEnvelope.self, from: data),
               let message = apiError.error.message,
               !message.isEmpty {
                throw OpenAIRecipeEnhancerError.apiError(message)
            }

            throw OpenAIRecipeEnhancerError.apiError("HTTP \(httpResponse.statusCode)")
        }

        let parsedResponse = try decoder.decode(OpenAIResponseEnvelope.self, from: data)

        if let refusal = parsedResponse.refusalText, !refusal.isEmpty {
            throw OpenAIRecipeEnhancerError.apiError(refusal)
        }

        guard let outputJSON = parsedResponse.outputJSONString,
              let outputData = outputJSON.data(using: .utf8) else {
            throw OpenAIRecipeEnhancerError.missingOutput
        }

        return try decoder.decode(Response.self, from: outputData)
    }

    private func finalizeTitle(
        for draft: RecipeDraft,
        sourceText: String,
        fallback: RecipeDraft,
        apiKey: String,
        pageTitle: String?
    ) async throws -> RecipeDraft {
        let body = try makeTitleRequestBody(
            extractedDraft: draft,
            sourceText: sourceText,
            pageTitle: pageTitle
        )
        let titleAssessment = try await performTitleRequest(body: body, apiKey: apiKey)

        let candidateTitle = titleAssessment.titleMakesSense
            ? titleAssessment.finalTitle
            : titleAssessment.inferredDishName

        let resolvedTitle = RecipeParser.resolvedTitle(
            candidate: candidateTitle,
            fallback: draft.title.isEmpty ? fallback.title : draft.title,
            ingredientNames: draft.allIngredients.map(\.name)
        )

        if resolvedTitle.isEmpty {
            return draft
        }

        var updatedDraft = draft
        updatedDraft.title = resolvedTitle
        return updatedDraft
    }

    private func makeRequestBody(
        recognizedText: String,
        mode: RecipeInferenceMode,
        pageTitle: String?
    ) throws -> [String: Any] {
        let userPrompt = makeTextUserPrompt(
            recognizedText: recognizedText,
            mode: mode,
            pageTitle: pageTitle
        )

        return [
            "model": model,
            "input": [
                [
                    "role": "developer",
                    "content": try RecipeParserSkillPrompts.extractionDeveloperPrompt()
                ],
                [
                    "role": "user",
                    "content": userPrompt
                ]
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "recipe_draft",
                    "strict": true,
                    "schema": Self.recipeSchema
                ]
            ],
            "max_output_tokens": 2000
        ]
    }

    private func makeTitleRequestBody(
        extractedDraft: RecipeDraft,
        sourceText: String,
        pageTitle: String?
    ) throws -> [String: Any] {
        [
            "model": model,
            "input": [
                [
                    "role": "developer",
                    "content": try RecipeParserSkillPrompts.titleDeveloperPrompt()
                ],
                [
                    "role": "user",
                    "content": makeTitleUserPrompt(
                        extractedDraft: extractedDraft,
                        sourceText: sourceText,
                        pageTitle: pageTitle
                    )
                ]
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "recipe_title_resolution",
                    "strict": true,
                    "schema": Self.titleSchema
                ]
            ],
            "max_output_tokens": 220
        ]
    }

    private func makeImageRequestBody(
        images: [UIImage],
        supplementalText: String,
        mode: RecipeInferenceMode,
        pageTitle: String?
    ) throws -> [String: Any] {
        var userContent: [[String: Any]] = [
            [
                "type": "input_text",
                "text": makeImageUserPrompt(
                    supplementalText: supplementalText,
                    mode: mode,
                    pageTitle: pageTitle
                )
            ]
        ]

        for image in images {
            userContent.append([
                "type": "input_image",
                "image_url": try makeImageDataURL(for: image),
                "detail": "high"
            ])
        }

        return [
            "model": model,
            "input": [
                [
                    "role": "developer",
                    "content": try RecipeParserSkillPrompts.extractionDeveloperPrompt()
                ],
                [
                    "role": "user",
                    "content": userContent
                ]
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "recipe_draft",
                    "strict": true,
                    "schema": Self.recipeSchema
                ]
            ],
            "max_output_tokens": 2000
        ]
    }

    private func makeImageDataURL(for image: UIImage) throws -> String {
        let preparedImage = resizedImageIfNeeded(image)

        if let jpegData = preparedImage.jpegData(compressionQuality: jpegCompressionQuality) {
            return "data:image/jpeg;base64," + jpegData.base64EncodedString()
        }

        if let pngData = preparedImage.pngData() {
            return "data:image/png;base64," + pngData.base64EncodedString()
        }

        throw OpenAIRecipeEnhancerError.invalidImage
    }

    private func resizedImageIfNeeded(_ image: UIImage) -> UIImage {
        let size = image.size
        let longestSide = max(size.width, size.height)

        guard longestSide > maxImageDimension, longestSide > 0 else {
            return image
        }

        let scale = maxImageDimension / longestSide
        let targetSize = CGSize(
            width: max(size.width * scale, 1),
            height: max(size.height * scale, 1)
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func makeTextUserPrompt(
        recognizedText: String,
        mode: RecipeInferenceMode,
        pageTitle: String?
    ) -> String {
        var sections: [String] = []

        switch mode {
        case .textFirst:
            sections.append("This recipe post is primarily text-based. Use the text as the main source of truth.")
        case .imageFirst:
            sections.append("This recipe post is image-heavy, but the text can still help with the title or short notes.")
        case .mixed:
            sections.append("This recipe post mixes meaningful text with screenshots. Use the text for the title and clearly written notes, and infer the final structure carefully.")
        }

        sections.append("The dish name is usually near the beginning of the post, and the page title is often a strong title candidate.")

        if let pageTitle,
           !pageTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("Page title: \(pageTitle)")
        }

        sections.append("Post text:\n\(recognizedText)")
        return sections.joined(separator: "\n\n")
    }

    private func makeImageUserPrompt(
        supplementalText: String,
        mode: RecipeInferenceMode,
        pageTitle: String?
    ) -> String {
        let trimmedSupplementalText = supplementalText.trimmingCharacters(in: .whitespacesAndNewlines)
        var sections: [String] = []

        switch mode {
        case .imageFirst:
            sections.append("These screenshots belong to one recipe post. This post appears image-heavy. Use the screenshots as the main source of truth.")
            sections.append("Prefer the page title and opening title-like text for the dish name. Use image text and step diagrams for ingredients and steps.")
        case .mixed:
            sections.append("These screenshots belong to one recipe post. This post mixes meaningful text with recipe screenshots.")
            sections.append("Prefer the page title and opening text for the dish name. Use screenshots for ingredient tables and step-by-step instructions, and use supplemental text only to fill gaps that are clearly supported.")
        case .textFirst:
            sections.append("These screenshots belong to one recipe post. The screenshots are supplemental to a text-led recipe.")
        }

        sections.append("Combine information across all screenshots.")

        if let pageTitle,
           !pageTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("Page title: \(pageTitle)")
        }

        if !trimmedSupplementalText.isEmpty {
            sections.append("Helpful supplemental text:\n\(trimmedSupplementalText)")
        }

        return sections.joined(separator: "\n\n")
    }

    private static let recipeSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "title": [
                "type": "string"
            ],
            "sections": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "title": [
                            "type": "string"
                        ],
                        "ingredients": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "name": [
                                        "type": "string"
                                    ],
                                    "amount": [
                                        "type": "string"
                                    ],
                                    "unit": [
                                        "type": "string"
                                    ]
                                ],
                                "required": ["name", "amount", "unit"],
                                "additionalProperties": false
                            ]
                        ],
                        "steps": [
                            "type": "array",
                            "items": [
                                "type": "string"
                            ]
                        ]
                    ],
                    "required": ["title", "ingredients", "steps"],
                    "additionalProperties": false
                ]
            ],
            "ingredients": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "name": [
                            "type": "string"
                        ],
                        "amount": [
                            "type": "string"
                        ],
                        "unit": [
                            "type": "string"
                        ]
                    ],
                    "required": ["name", "amount", "unit"],
                    "additionalProperties": false
                ]
            ],
            "steps": [
                "type": "array",
                "items": [
                    "type": "string"
                ]
            ],
            "tips": [
                "type": "array",
                "items": [
                    "type": "string"
                ]
            ],
            "timeHints": [
                "type": "array",
                "items": [
                    "type": "string"
                ]
            ]
        ],
        "required": ["title", "sections", "ingredients", "steps", "tips", "timeHints"],
        "additionalProperties": false
    ]

    private static let titleSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "openingTitleCandidate": [
                "type": "string"
            ],
            "inferredDishName": [
                "type": "string"
            ],
            "finalTitle": [
                "type": "string"
            ],
            "titleMakesSense": [
                "type": "boolean"
            ],
            "reason": [
                "type": "string"
            ]
        ],
        "required": ["openingTitleCandidate", "inferredDishName", "finalTitle", "titleMakesSense", "reason"],
        "additionalProperties": false
    ]

    private func makeTitleUserPrompt(
        extractedDraft: RecipeDraft,
        sourceText: String,
        pageTitle: String?
    ) -> String {
        var sections: [String] = [
            "Decide the final recipe title."
        ]

        if let pageTitle,
           !pageTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("Page title:\n\(pageTitle)")
        }

        let openingExcerpt = Self.openingExcerpt(from: sourceText)
        if !openingExcerpt.isEmpty {
            sections.append("Opening text from the post:\n\(openingExcerpt)")
        }

        sections.append("Extracted recipe structure:\n\(summarizedRecipeDraft(extractedDraft))")
        return sections.joined(separator: "\n\n")
    }

    private func summarizedRecipeDraft(_ draft: RecipeDraft) -> String {
        var lines: [String] = []

        if !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Current extracted title: \(draft.title)")
        }

        if !draft.ingredients.isEmpty {
            let ingredientSummary = draft.ingredients.prefix(12).map { formattedIngredient($0) }.joined(separator: ", ")
            lines.append("Top-level ingredients: \(ingredientSummary)")
        }

        if !draft.sections.isEmpty {
            let sectionSummary = draft.sections.map { section in
                let ingredientSummary = section.ingredients.prefix(6).map { formattedIngredient($0) }.joined(separator: ", ")
                let stepSummary = section.steps.prefix(3).joined(separator: " | ")
                return "\(section.title): ingredients [\(ingredientSummary)] steps [\(stepSummary)]"
            }
            .joined(separator: "\n")
            lines.append("Recipe parts:\n\(sectionSummary)")
        }

        if !draft.steps.isEmpty {
            let stepSummary = draft.steps.prefix(6).joined(separator: " | ")
            lines.append("Steps: \(stepSummary)")
        }

        if !draft.tips.isEmpty {
            lines.append("Tips: \(draft.tips.prefix(3).joined(separator: " | "))")
        }

        return lines.joined(separator: "\n")
    }

    private static func openingExcerpt(from sourceText: String) -> String {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let lines = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let excerpt = lines.prefix(12).joined(separator: "\n")
        return String(excerpt.prefix(900))
    }
}

enum OpenAIRecipeEnhancerError: LocalizedError {
    case invalidResponse
    case apiError(String)
    case missingOutput
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The AI service returned an invalid response."
        case .apiError(let message):
            return message
        case .missingOutput:
            return "The AI service did not return a recipe."
        case .invalidImage:
            return "One of the selected images could not be encoded for AI analysis."
        }
    }
}

private struct OpenAIAPIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String?
    }

    let error: APIError
}

private struct OpenAIResponseEnvelope: Decodable {
    let outputText: String?
    let output: [OpenAIOutputItem]?

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }

    var outputJSONString: String? {
        if let outputText, !outputText.isEmpty {
            return outputText
        }

        return output?
            .flatMap(\.content)
            .first(where: { $0.type == "output_text" || $0.type == "text" })?
            .text
    }

    var refusalText: String? {
        output?
            .flatMap(\.content)
            .first(where: { $0.type == "refusal" })?
            .refusal
    }
}

private struct OpenAIOutputItem: Decodable {
    let content: [OpenAIOutputContent]
}

private struct OpenAIOutputContent: Decodable {
    let type: String
    let text: String?
    let refusal: String?
}

private struct OpenAIRecipeDraft: Decodable {
    let title: String
    let sections: [OpenAIRecipeSection]
    let ingredients: [OpenAIRecipeIngredient]
    let steps: [String]
    let tips: [String]
    let timeHints: [String]

    func makeRecipeDraft(fallback: RecipeDraft) -> RecipeDraft {
        let normalizedSections = sections.compactMap { $0.makeSection() }
        let normalizedIngredients = normalizedRecipeIngredients(ingredients)
        let sectionIngredients = normalizedSections.flatMap(\.ingredients)
        let filteredIngredients = normalizedIngredients.filter { ingredient in
            !sectionIngredients.contains(where: { sameIngredient($0, ingredient) })
        }

        let normalizedTitle = RecipeParser.resolvedTitle(
            candidate: title.trimmingCharacters(in: .whitespacesAndNewlines),
            fallback: fallback.title,
            ingredientNames: (filteredIngredients + sectionIngredients).map(\.name)
        )

        let normalizedSteps = deduplicatedTextItems(steps)
        let sectionSteps = Set(normalizedSections.flatMap(\.steps))
        let filteredSteps = deduplicatedTextItems(normalizedSteps.filter { !sectionSteps.contains($0) })

        let normalizedTips = deduplicatedTextItems(RecipeParser.sanitizedTips(
            tips.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        ))

        let normalizedTimeHints = deduplicatedTextItems(timeHints)

        return RecipeDraft(
            title: normalizedTitle.isEmpty ? RecipeParser.sanitizedTitle(fallback.title) : normalizedTitle,
            ingredients: filteredIngredients.isEmpty && normalizedSections.isEmpty ? fallback.ingredients : filteredIngredients,
            steps: filteredSteps.isEmpty && normalizedSections.isEmpty ? fallback.steps : filteredSteps,
            tips: normalizedTips.isEmpty ? RecipeParser.sanitizedTips(fallback.tips) : normalizedTips,
            timeHints: normalizedTimeHints.isEmpty ? fallback.timeHints : normalizedTimeHints,
            sections: normalizedSections.isEmpty ? fallback.sections : normalizedSections
        )
    }
}

private struct OpenAIRecipeTitleResponse: Decodable {
    let openingTitleCandidate: String
    let inferredDishName: String
    let finalTitle: String
    let titleMakesSense: Bool
    let reason: String
}

private struct OpenAIRecipeIngredient: Decodable {
    let name: String
    let amount: String
    let unit: String
}

private struct OpenAIRecipeSection: Decodable {
    let title: String
    let ingredients: [OpenAIRecipeIngredient]
    let steps: [String]

    func makeSection() -> RecipeSection? {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedIngredients = normalizedRecipeIngredients(ingredients)

        let normalizedSteps = deduplicatedTextItems(steps)

        guard !normalizedTitle.isEmpty || !normalizedIngredients.isEmpty || !normalizedSteps.isEmpty else {
            return nil
        }

        return RecipeSection(
            title: normalizedTitle.isEmpty ? "Part" : normalizedTitle,
            ingredients: normalizedIngredients,
            steps: normalizedSteps
        )
    }
}

private func normalizedRecipeIngredients(_ ingredients: [OpenAIRecipeIngredient]) -> [RecipeIngredient] {
    let normalized = ingredients.compactMap { ingredient -> RecipeIngredient? in
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
    }.map(normalizeAlternativeIngredient)

    return deduplicatedIngredients(mergeAlternativeIngredients(normalized))
}

private let alternativeIngredientFormKeywords = [
    "extract", "essence", "paste", "bean", "pod",
    "精", "荚", "莢", "籽", "粉", "酱", "醬", "露", "膏"
]

private func mergeAlternativeIngredients(_ ingredients: [RecipeIngredient]) -> [RecipeIngredient] {
    guard ingredients.count >= 2 else { return ingredients }

    var merged: [RecipeIngredient] = []
    var index = 0

    while index < ingredients.count {
        let current = ingredients[index]

        if index + 1 < ingredients.count {
            let next = ingredients[index + 1]

            if shouldMergeAlternativeIngredients(current, next) {
                let mergedLine = "\(formattedIngredient(current)) 或 \(formattedIngredient(next))"
                merged.append(
                    RecipeIngredient(
                        name: mergedLine,
                        amount: nil,
                        unit: nil,
                        rawLine: mergedLine
                    )
                )
                index += 2
                continue
            }
        }

        merged.append(current)
        index += 1
    }

    return merged
}

private func deduplicatedIngredients(_ ingredients: [RecipeIngredient]) -> [RecipeIngredient] {
    var results: [RecipeIngredient] = []

    for ingredient in ingredients {
        if !results.contains(where: { sameIngredient($0, ingredient) }) {
            results.append(ingredient)
        }
    }

    return results
}

private func deduplicatedTextItems(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var results: [String] = []

    for value in values {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }

        let key = normalizedTextKey(trimmed)
        guard seen.insert(key).inserted else { continue }
        results.append(trimmed)
    }

    return results
}

private func normalizedTextKey(_ value: String) -> String {
    value
        .lowercased()
        .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"[，。、“”‘’!！?？:：;；,.\-_/\\\(\)（）\[\]【】]"#, with: "", options: .regularExpression)
}

private func normalizeAlternativeIngredient(_ ingredient: RecipeIngredient) -> RecipeIngredient {
    let separators = ["/", "／", "或"]
    let matchedSeparator = separators.first { ingredient.name.contains($0) && (ingredient.amount?.contains($0) == true) }

    guard let separator = matchedSeparator else {
        return ingredient
    }

    let nameParts = ingredient.name
        .components(separatedBy: separator)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    let amountParts = (ingredient.amount ?? "")
        .components(separatedBy: separator)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    guard nameParts.count == 2, amountParts.count == 2 else {
        return ingredient
    }

    let left = formatAlternativePart(
        name: nameParts[0],
        amount: amountParts[0],
        unit: ingredient.unit
    )
    let right = formatAlternativePart(
        name: nameParts[1],
        amount: amountParts[1],
        unit: ingredient.unit
    )

    let merged = "\(left) 或 \(right)"
    return RecipeIngredient(name: merged, amount: nil, unit: nil, rawLine: merged)
}

private func shouldMergeAlternativeIngredients(_ lhs: RecipeIngredient, _ rhs: RecipeIngredient) -> Bool {
    let leftName = lhs.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let rightName = rhs.name.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !leftName.isEmpty, !rightName.isEmpty else { return false }
    guard !containsAlternativeMarker(leftName), !containsAlternativeMarker(rightName) else { return false }

    let leftCore = alternativeIngredientCore(from: leftName)
    let rightCore = alternativeIngredientCore(from: rightName)

    guard !leftCore.isEmpty, leftCore == rightCore else { return false }
    guard leftCore.count >= 2 else { return false }

    return hasAlternativeFormKeyword(leftName) && hasAlternativeFormKeyword(rightName)
}

private func containsAlternativeMarker(_ value: String) -> Bool {
    let markers = ["或", "或者", "/", "／", "二选一", "二選一", "任选", "任選", "可替换", "可替換", "代替"]
    return markers.contains { value.localizedCaseInsensitiveContains($0) }
}

private func hasAlternativeFormKeyword(_ value: String) -> Bool {
    let normalized = value.lowercased()
    return alternativeIngredientFormKeywords.contains { normalized.contains($0) }
}

private func alternativeIngredientCore(from value: String) -> String {
    var normalized = value
        .lowercased()
        .replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"（[^）]*）"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)

    for keyword in alternativeIngredientFormKeywords.sorted(by: { $0.count > $1.count }) {
        normalized = normalized.replacingOccurrences(of: keyword, with: "")
    }

    return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func formattedIngredient(_ ingredient: RecipeIngredient) -> String {
    let amountUnit = [ingredient.amount, ingredient.unit]
        .compactMap { $0 }
        .joined()

    return amountUnit.isEmpty ? ingredient.name : "\(ingredient.name) \(amountUnit)"
}

private func sameIngredient(_ lhs: RecipeIngredient, _ rhs: RecipeIngredient) -> Bool {
    lhs.name.trimmingCharacters(in: .whitespacesAndNewlines)
        .localizedCaseInsensitiveCompare(rhs.name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame &&
    (lhs.amount ?? "").trimmingCharacters(in: .whitespacesAndNewlines) ==
    (rhs.amount ?? "").trimmingCharacters(in: .whitespacesAndNewlines) &&
    (lhs.unit ?? "").trimmingCharacters(in: .whitespacesAndNewlines) ==
    (rhs.unit ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}

private func formatAlternativePart(name: String, amount: String, unit: String?) -> String {
    var cleanedAmount = amount.trimmingCharacters(in: .whitespacesAndNewlines)

    if cleanedAmount.localizedCaseInsensitiveContains(name) {
        cleanedAmount = cleanedAmount.replacingOccurrences(of: name, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let usesStandaloneUnit = cleanedAmount.range(of: #"[A-Za-z一-龥]+$"#, options: .regularExpression) != nil
    let suffix = (unit ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let amountUnit = suffix.isEmpty || usesStandaloneUnit
        ? cleanedAmount
        : cleanedAmount + suffix

    return amountUnit.isEmpty ? name : "\(name) \(amountUnit)"
}
