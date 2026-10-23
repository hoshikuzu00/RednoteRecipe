# Output Schema

The recipe parser should produce one strict JSON object with these fields.

## Top-level fields

- `title: string`
- `sections: RecipeSection[]`
- `ingredients: RecipeIngredient[]`
- `steps: string[]`
- `tips: string[]`
- `timeHints: string[]`

## RecipeIngredient

- `name: string`
- `amount: string`
- `unit: string`

Rules:
- `name` is required
- `amount` and `unit` may be empty strings if not visible
- do not fabricate normalized units

## RecipeSection

- `title: string`
- `ingredients: RecipeIngredient[]`
- `steps: string[]`

Use sections when the post clearly splits the recipe into named parts, such as:
- dough / filling
- sauce / topping
- crust / custard
- marinade / coating / frying

## Field Semantics

### title
The final dish name, not random opening text.

### ingredients
Use for top-level ingredients only.
Do not duplicate ingredients that already belong inside a section.

### steps
Use only for top-level steps.
If the visible method is entirely part-based, keep top-level `steps` empty.

### tips
Short practical advice, reminders, substitutions, or serving notes.
Do not include platform engagement bait or generic commentary.

### timeHints
Only use for leftover time or temperature facts that do not fit naturally inside a step.

## Empty-field policy

If the post does not support a field strongly enough:
- leave it empty
- do not infer a fake placeholder

## Stability Policy

The parser should prefer:
- empty over invented
- structured over noisy
- title sanity over title recall
- image evidence over post commentary when images contain recipe content
