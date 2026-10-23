# Prompt Contract

This file captures the current recipe extraction behavior in a reusable form.

## Main Extraction Role

The model should behave as if instructed with this contract:

`You are reading screenshots or key frames from one recipe post. Return strict recipe JSON. Use only visible information. Do not guess missing facts. Do not merely classify fragments line by line. Infer the intended recipe structure only when that structure is strongly supported by visible content.`

## Required Output

- `title`: the finished dish name
- `sections`: optional named recipe parts, each with its own ingredients and steps
- `ingredients`: top-level ingredients or packaged components
- `steps`: cooking steps in order
- `tips`: short practical notes or reminders
- `timeHints`: only leftover standalone time or temperature details that do not fit naturally inside a step

## Title Policy

Title should be handled conservatively.

Prefer:
1. page title
2. opening title-like text near the beginning of the post
3. the dish name implied by the extracted ingredients, sections, and steps

Reject titles that are mainly:
- commentary
- mood phrases
- action sentences
- brand names
- single seasonings
- single sauces
- decorative cover slogans

The model should effectively apply this rule:

`Before accepting the final title, read it once and reject it if it does not make culinary sense.`

## Structural Inference Policy

Allowed:
- merge obvious fragments that belong to the same step
- infer that grouped ingredients belong to named recipe parts when the post clearly separates them
- use screenshots as the main evidence for ingredient tables and step diagrams

Not allowed:
- invent quantities, cooking times, or missing steps
- turn commentary into ingredients or steps
- upgrade a weak hint into a hard fact

## Ingredient Policy

- Keep packaged components if they are visibly used.
- Keep alternative or substitute forms together only when the post clearly presents them as alternatives.
- Do not include plain water unless it is clearly a named or special liquid.

## Text Sufficiency Policy

For text-only decisions:

Mark text as sufficient only when it clearly contains enough recipe substance to save a useful recipe.

Mark text as not sufficient when it is mostly:
- commentary
- references to other pages or parts
- missing most concrete ingredients
- missing most concrete steps

## Title Finalization Pass

The title pass should behave as if asked to return:
- `openingTitleCandidate`
- `inferredDishName`
- `finalTitle`
- `titleMakesSense`
- `reason`

And should follow this logic:
- read the whole extracted recipe first
- compare opening/page-title candidates against the inferred dish name
- keep the best title only if it sounds like a real dish or recipe component
- if neither candidate makes sense, leave `finalTitle` empty and mark `titleMakesSense = false`

## Media Prompting Policy

For image-heavy posts:
- use screenshots as the main source of truth
- use text mostly for title or short notes

For mixed posts:
- use page title and opening text for dish naming
- use screenshots for ingredient tables and step instructions
- use supplemental text only to fill gaps clearly supported by the screenshots

For text-heavy posts:
- use text as the main source of truth

## Stability Goal

The purpose of this contract is not to maximize recall at all costs.
It is to make outputs stable, culinary-sensible, and hard to derail by noisy post text.
