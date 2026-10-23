// Appended to the production Foundation-only model code by run_recipe_regressions.py.
// Fixtures exercise the actual JSON decoder and recipe normalization without network calls.
private let decoder = JSONDecoder()
private let fallback = RecipeDraft(
    title: "家常番茄炒蛋",
    ingredients: [RecipeIngredient(name: "番茄", amount: "2", unit: "个", rawLine: "番茄 2 个")],
    steps: ["翻炒番茄。"], tips: [], timeHints: ["5分钟"], sections: []
)

private func recipe(_ json: String) throws -> RecipeDraft {
    try decoder.decode(OpenAIRecipeDraft.self, from: Data(json.utf8)).makeRecipeDraft(fallback: fallback)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

private let grouped = try recipe(#"""
{
  "title": " 番茄炒蛋 ",
  "ingredients": [
    {"name":" 盐 ","amount":" 1 ","unit":" 克 "},
    {"name":"盐","amount":"1","unit":"克"},
    {"name":"糖","amount":"","unit":""},
    {"name":"  ","amount":"1","unit":"克"}
  ],
  "steps": [" 拌匀。 ","盛出！","盛出", "  "],
  "sections": [
    {"title":" 酱汁 ","ingredients":[
      {"name":"盐","amount":"1","unit":"克"},
      {"name":" 盐 ","amount":" 1 ","unit":" 克 "}
    ],"steps":[" 拌匀。 ","拌匀", ""]},
    {"title":" ","ingredients":[],"steps":[]}
  ],
  "tips": [],
  "timeHints": [" 5分钟 ", "5分钟", ""]
}
"""#)
expect(grouped.title == "番茄炒蛋", "Title whitespace changed")
expect(grouped.ingredients.map(\.name) == ["糖"], "Section ingredients must be removed from top level")
expect(grouped.ingredients[0].amount == nil && grouped.ingredients[0].unit == nil, "Empty amount/unit must stay nil")
expect(grouped.sections.count == 1 && grouped.sections[0].title == "酱汁", "Empty sections must be discarded")
expect(grouped.sections[0].ingredients.count == 1, "Ingredient deduplication changed")
expect(grouped.sections[0].ingredients[0].rawLine == "盐 1 克", "Ingredient whitespace normalization changed")
expect(grouped.sections[0].steps == ["拌匀。"], "Step punctuation deduplication changed")
expect(grouped.steps == ["盛出！"], "Step order or section filtering changed")
expect(grouped.timeHints == ["5分钟"], "Time hints must be trimmed and deduplicated")

private let quantities = try recipe(#"""
{"title":"番茄炒蛋","sections":[],"ingredients":[
 {"name":"盐","amount":"1","unit":"克"},
 {"name":"盐","amount":"2","unit":"克"}
],"steps":["搅拌"],"tips":[],"timeHints":[]}
"""#)
expect(quantities.ingredients.count == 2, "Different ingredient quantities must remain separate")

private let alternatives = try recipe(#"""
{"title":"香草蛋糕","ingredients":[
 {"name":"香草精/香草荚","amount":"2/1","unit":"克"}
],"sections":[{"title":"蛋糕糊","ingredients":[
 {"name":"香草精/香草荚","amount":"2/1","unit":"克"}
],"steps":["拌匀"]}],"steps":[],"tips":[],"timeHints":[]}
"""#)
expect(alternatives.ingredients.isEmpty, "Alternative ingredient normalization must match across sections")
expect(alternatives.sections[0].ingredients.count == 1, "Alternatives must stay one ingredient")
expect(alternatives.sections[0].ingredients[0].name.contains("或"), "Alternative ingredient formatting changed")

private let empty = try recipe(#"""
{"title":"","ingredients":[],"sections":[],"steps":[],"tips":[],"timeHints":[]}
"""#)
expect(empty.ingredients == fallback.ingredients, "Empty AI ingredients must preserve local ingredients")
expect(empty.steps == fallback.steps && empty.timeHints == fallback.timeHints, "Empty AI output must preserve local steps/times")
expect(empty.title == fallback.title, "Empty AI title must preserve the local title")

private let unnamedSection = try recipe(#"""
{"title":"番茄炒蛋","ingredients":[],"sections":[{"title":" ","ingredients":[],"steps":["炒熟"]}],"steps":[],"tips":[],"timeHints":[]}
"""#)
expect(unnamedSection.sections[0].title == "Part", "A nonempty unnamed section must retain its default title")
expect(unnamedSection.ingredients.isEmpty && unnamedSection.steps.isEmpty, "Section-only recipes must not regain unrelated fallback content")

private let direct = try decoder.decode(OpenAIResponseEnvelope.self, from: Data(#"{"output_text":"direct","output":[{"content":[{"type":"output_text","text":"nested"}]}]}"#.utf8))
expect(direct.outputJSONString == "direct", "Direct output must take precedence")
private let nested = try decoder.decode(OpenAIResponseEnvelope.self, from: Data(#"{"output":[{"content":[{"type":"output_text","text":"nested"}]}]}"#.utf8))
expect(nested.outputJSONString == "nested", "Nested API output must be decoded")
private let refused = try decoder.decode(OpenAIResponseEnvelope.self, from: Data(#"{"output":[{"content":[{"type":"refusal","refusal":"declined"}]}]}"#.utf8))
expect(refused.refusalText == "declined" && refused.outputJSONString == nil, "Refusals must not become recipe output")
private let missing = try decoder.decode(OpenAIResponseEnvelope.self, from: Data("{}".utf8))
expect(missing.outputJSONString == nil, "Missing output must remain detectable")

print("PASS: 9 offline recipe normalization and response-envelope regression scenarios")
