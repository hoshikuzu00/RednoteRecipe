# Media Routing

This file describes how recipe evidence should be prioritized before the main extraction pass.

## Global Rule

If there are useful text-bearing images or video frames, images should lead.
Text becomes supplemental.

## Image Posts

- If many text-bearing images exist, use image-first.
- If only a few text-bearing images exist, use mixed mode.
- If no text-bearing images exist, fall back to text-first.

## Video Posts

- Convert the video into key frames first.
- Only keep frames that contain meaningful text.
- If repeated adjacent frames contain the same subtitle text, keep the strongest frame from that subtitle run.
- Send the resulting frames to the recipe parser as images.

## Text Weight By Image Count

Suggested policy:

- `>= 12` images: keep only title/opening text and a small amount of notes
- `6...11` images: keep a moderate amount of text
- `1...5` images: allow more supplemental text
- `0` images: use text-first

## Why This Exists

Pure prompt wording is not enough to stabilize recipe extraction.
The evidence routing policy matters:
- too much commentary hurts title quality
- too few images hurts step extraction
- low-quality video frames hurt ingredient reading

This routing policy is part of the stable behavior, not an implementation detail.
