---
name: recipe-post-parser
description: Extract a structured recipe from social recipe posts that may contain screenshots, text-heavy posts, linked page text, or cooking-video key frames. Use when the goal is to turn one post into stable recipe JSON with title, sections, ingredients, steps, tips, and timeHints while preferring image evidence over commentary and applying a separate title-resolution pass.
---

# Recipe Post Parser

Use this skill when a single social post needs to become one structured recipe.

This skill is optimized for:
- screenshot-heavy recipe posts
- text-heavy recipe posts
- mixed text plus screenshots
- cooking videos that have already been converted into key frames

This skill does not invent missing cooking facts. It extracts structure from visible evidence and only makes minimal structural inferences when the post strongly supports them.

## Workflow

1. Decide the evidence mix.
If there are text-bearing images or video frames, prefer images as the main source.
If there are many images, use text only as a small supplement.
If there are few images, let text fill more gaps.
If there are no useful images, use text-first parsing.

2. Extract the main recipe draft.
Return one JSON object with:
- `title`
- `sections`
- `ingredients`
- `steps`
- `tips`
- `timeHints`

3. Run a separate title-resolution pass.
Title should not be accepted blindly from the first visible phrase.
Prefer:
- page title
- opening title-like text
- the dish name implied by the extracted recipe structure

4. Reject unstable titles.
If the candidate title does not sound like a real dish, recipe, or named recipe component, discard it.

## Stability Rules

- Do not merely transcribe fragments line by line.
- Do not treat decorative cover text or commentary as the dish name.
- Do not use a single seasoning, sauce, flavor name, or brand name as title unless the whole recipe is truly for that exact item.
- Do not include plain water as an ingredient unless it is clearly a named or special liquid.
- If ingredients are grouped into named parts, keep them inside `sections`.
- If grouped ingredients are visible but method is not, keep `steps` empty and rely on `sections`.
- If the method is visible, extract steps in order.
- Keep the output in the main language of the post.
- If unsure, leave the field empty instead of guessing.

## What To Read

- Read [references/prompt-contract.md](references/prompt-contract.md) for the exact extraction behavior and prompt logic.
- Read [references/output-schema.md](references/output-schema.md) for field semantics and output constraints.
- Read [references/media-routing.md](references/media-routing.md) when deciding image-first, text-first, or mixed behavior.

## Notes

- This skill is a stable prompt/specification layer.
- If the app prompt changes later, keep this skill in sync with [OpenAIRecipeEnhancer.swift](/Users/chonggu/Documents/Mine/App/rednoteApp/Sources/OpenAIRecipeEnhancer.swift).
