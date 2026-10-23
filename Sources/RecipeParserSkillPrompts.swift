import Foundation

enum RecipeParserSkillPromptError: LocalizedError {
    case bundleNotLoaded
    case missingDocument(String)
    case missingSection(document: String, section: String)
    case emptyPrompt(String)

    var errorDescription: String? {
        switch self {
        case .bundleNotLoaded:
            return "The bundled recipe parser skill could not be loaded."
        case .missingDocument(let document):
            return "The recipe parser skill is missing required document: \(document)."
        case .missingSection(let document, let section):
            return "The recipe parser skill is missing required section '\(section)' in \(document)."
        case .emptyPrompt(let promptName):
            return "The recipe parser skill produced an empty \(promptName) prompt."
        }
    }
}

enum RecipeParserSkillPrompts {
    static func extractionDeveloperPrompt() throws -> String {
        let docs = try RecipeParserSkillBundle.load()

        let workflow = try docs.requiredSection("Workflow", in: "SKILL.md")
        let stabilityRules = try docs.requiredSection("Stability Rules", in: "SKILL.md")
        let mainRole = try docs.requiredSection("Main Extraction Role", in: "prompt-contract.md")
        let requiredOutput = try docs.requiredSection("Required Output", in: "prompt-contract.md")
        let titlePolicy = try docs.requiredSection("Title Policy", in: "prompt-contract.md")
        let structuralPolicy = try docs.requiredSection("Structural Inference Policy", in: "prompt-contract.md")
        let ingredientPolicy = try docs.requiredSection("Ingredient Policy", in: "prompt-contract.md")
        let topLevelFields = try docs.requiredSection("Top-level fields", in: "output-schema.md")
        let fieldSemantics = try docs.requiredSection("Field Semantics", in: "output-schema.md")

        let parts = [
            "You are following the bundled `recipe-post-parser` skill.",
            mainRole,
            workflow,
            requiredOutput,
            topLevelFields,
            structuralPolicy,
            ingredientPolicy,
            titlePolicy,
            fieldSemantics,
            stabilityRules
        ]
            .map(normalizeSection)
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else {
            throw RecipeParserSkillPromptError.emptyPrompt("extraction")
        }

        return parts.joined(separator: "\n\n")
    }

    static func titleDeveloperPrompt() throws -> String {
        let docs = try RecipeParserSkillBundle.load()

        let titlePolicy = try docs.requiredSection("Title Policy", in: "prompt-contract.md")
        let titlePass = try docs.requiredSection("Title Finalization Pass", in: "prompt-contract.md")
        let titleSection = try docs.requiredSection("title", in: "output-schema.md")

        let parts = [
            "You are following the bundled `recipe-post-parser` skill and only finalizing the recipe title for one post.",
            """
            Return a strict JSON object with:
            - openingTitleCandidate: the strongest title candidate from the page title or the opening part of the post
            - inferredDishName: the dish name you infer after reading the extracted recipe structure
            - finalTitle: the best final title after comparing the opening title candidate and the inferred dish name
            - titleMakesSense: true only if the final title sounds like a real dish, recipe, or named recipe component
            - reason: one short sentence explaining the judgment
            """,
            titlePolicy,
            titlePass,
            titleSection
        ]
            .map(normalizeSection)
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else {
            throw RecipeParserSkillPromptError.emptyPrompt("title")
        }

        return parts.joined(separator: "\n\n")
    }

    private static func normalizeSection(_ section: String) -> String {
        section
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

private struct RecipeParserSkillBundle {
    let documents: [String: String]

    static func load() throws -> RecipeParserSkillBundle {
        let urls = markdownFileURLs()
        guard !urls.isEmpty else { throw RecipeParserSkillPromptError.bundleNotLoaded }

        var documents: [String: String] = [:]

        for url in urls {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
            documents[url.lastPathComponent] = text
        }

        guard !documents.isEmpty else {
            throw RecipeParserSkillPromptError.bundleNotLoaded
        }

        return RecipeParserSkillBundle(documents: documents)
    }

    func section(_ title: String, in documentName: String) -> String? {
        guard let text = documents[documentName] else { return nil }
        return extractSection(named: title, from: text)
    }

    func requiredSection(_ title: String, in documentName: String) throws -> String {
        guard documents[documentName] != nil else {
            throw RecipeParserSkillPromptError.missingDocument(documentName)
        }

        guard let section = section(title, in: documentName) else {
            throw RecipeParserSkillPromptError.missingSection(document: documentName, section: title)
        }

        return section
    }

    private func extractSection(named title: String, from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        var sectionLevel: Int?
        var collected: [String] = []

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            let level = trimmedLine.prefix(while: { $0 == "#" }).count
            let headingText = trimmedLine.dropFirst(level)
            if (1...6).contains(level), headingText.first?.isWhitespace == true {
                let heading = headingText.trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespaces))

                if let sectionLevel {
                    if level <= sectionLevel {
                        break
                    }
                } else if heading.caseInsensitiveCompare(title) == .orderedSame {
                    sectionLevel = level
                    continue
                }
            }

            if sectionLevel != nil {
                collected.append(line)
            }
        }

        let section = collected
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return section.isEmpty ? nil : section
    }

    private static func markdownFileURLs() -> [URL] {
        guard let root = Bundle.main.resourceURL else { return [] }

        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var urls: [URL] = []

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension.lowercased() == "md" else { continue }
            if fileURL.path.contains("recipe-post-parser") {
                urls.append(fileURL)
            }
        }

        return urls
    }
}
