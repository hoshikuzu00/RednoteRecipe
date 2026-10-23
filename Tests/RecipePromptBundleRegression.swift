import Foundation

let resourceRoot = Bundle.main.resourceURL!
precondition(resourceRoot.lastPathComponent == "Resources", "Expected a real app bundle resource directory")

let extraction = try RecipeParserSkillPrompts.extractionDeveloperPrompt()
precondition(extraction.contains("recipe-post-parser"))
precondition(extraction.contains("### title"), "Parent sections must include child headings")
precondition(extraction.contains("Only use for leftover time or temperature facts"), "Parent sections must include every child section")
precondition(!extraction.contains("## Empty-field policy"), "Parent sections must stop before the next sibling heading")

let title = try RecipeParserSkillPrompts.titleDeveloperPrompt()
precondition(title.contains("The final dish name, not random opening text."))
precondition(!title.contains("Use for top-level ingredients only."), "Child sections must stop before the next sibling heading")
print("PASS: bundled extraction (\(extraction.count) characters) and title (\(title.count) characters) prompts")

// Exercise a real packaging failure so missing documents cannot silently weaken the prompts.
let schema = resourceRoot.appendingPathComponent("recipe-post-parser/references/output-schema.md")
try FileManager.default.removeItem(at: schema)
do {
    _ = try RecipeParserSkillPrompts.extractionDeveloperPrompt()
    fatalError("A missing schema document must fail explicitly")
} catch RecipeParserSkillPromptError.missingDocument(let name) {
    precondition(name == "output-schema.md")
}
print("PASS: missing bundled document is rejected")
