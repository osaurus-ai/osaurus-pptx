---
name: osaurus-pptx
description: Create, inspect, patch, render, validate, and export PowerPoint presentations using the Osaurus PPTX plugin. Use for .pptx editing, .ppt/.pptx conversion, presentation previews, and high-fidelity deck workflows.
metadata:
  author: osaurus
  version: "0.2.0"
---

# Osaurus PPTX

Use this plugin for PowerPoint work that needs file fidelity. New decks can be built with the writer tools. Existing decks should be edited with the package patch tools so masters, layouts, images, charts, media, and unrelated OOXML parts remain in place.

## Mandatory Workflow

For any existing file:

1. Inspect the attachment with `read_presentation` or `validate_presentation`.
2. Patch with the narrowest tool: `update_text`, `replace_image`, `move_resize_element`, `duplicate_slide`, or `reorder_slides`.
3. Render with `render_presentation` or export with `export_presentation`.
4. Validate the changed `.pptx` with `validate_presentation`.
5. Share both the `.pptx` and a PDF preview when the converter is available.

If LibreOffice is not installed, `render_presentation` and converter-backed exports return `converter_unavailable`. Report that status plainly instead of pretending a visual preview was checked.

## Attachments

Osaurus passes preserved input files in `_context.attachments`:

```json
{
  "id": "attachment-id",
  "filename": "deck.pptx",
  "mime_type": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  "file_size": 12345,
  "host_path": "/Users/.../.osaurus/attachments/.../deck.pptx"
}
```

Prefer `attachment_id` over copying `host_path` into prompts. The plugin allows attachment files outside the workspace only when they are present in `_context.attachments`.

## File Policy

- `.pptx` is the editable canonical format.
- `.ppt`, `.pot`, and binary legacy PowerPoint files are convert-only. Use `export_presentation(format: "pptx")` when LibreOffice is available, then inspect the converted `.pptx`.
- `read_presentation` accepts `.pptx`, `.ppsx`, and `.potx`, not `.ppt`.
- `export_presentation(format: "pdf")` uses LibreOffice's `impress_pdf_Export`.
- `export_presentation(format: "pptx")` copies `.pptx` directly or uses LibreOffice for legacy input.

## Coordinate System

All element patch coordinates are in inches from the top-left of the slide. Use `read_presentation` or `validate_presentation` to get `width_inches` and `height_inches` before setting coordinates.

Common dimensions:

| Aspect ratio | Width | Height |
|--------------|-------|--------|
| 16:9 | 13.33" | 7.5" |
| 4:3 | 10.0" | 7.5" |

Keep normal content at least 0.5" from each edge unless the user asks for full bleed.

## Existing Deck Tools

### `read_presentation`

Reads a `.pptx`, `.ppsx`, or `.potx` into memory and returns stable slide and element IDs. Text IDs look like `slide1-sp2`; image IDs look like `slide1-pic1`.

The in-memory model is intentionally partial. Use its IDs for targeted package patching; do not assume all deck features are represented as model elements.

### `validate_presentation`

Checks a PPTX-style package, blocks unsafe ZIP entries, confirms core parts, returns slide count, dimensions, and structural slide details.

### `update_text`

Patches text in the original OOXML package and writes a new `.pptx`.

Use either:

- `element_id` from `read_presentation`
- `match_text` for a targeted replacement

Always provide `output_path`; this tool does not overwrite the source file.

### `replace_image`

Replaces an existing image part. If the replacement file extension differs from the original, the tool updates the slide relationship target and adds the needed content type default.

### `move_resize_element`

Updates the transform for an existing text or image element. Coordinates are inches.

### `duplicate_slide`

Duplicates a slide and appends it to the deck. Use `reorder_slides` afterward if the duplicate belongs elsewhere.

### `reorder_slides`

Reorders slides with a 1-based complete permutation, for example `[3, 1, 2]`.

### `set_speaker_notes`

Patches speaker notes for one slide and writes a new `.pptx`. This creates notesSlide/notesMaster package parts when needed. Always run `validate_presentation` afterward.

## Creation Tools

For brand-new decks, use:

1. `create_presentation`
2. `add_slide`
3. `add_text`, `add_image`, `add_shape`, `add_table`, `add_chart`, and `set_slide_background`
4. `save_presentation`
5. `render_presentation`
6. `validate_presentation`

Creation tools write a clean generated PPTX package. They are not the right path for preserving an existing complex deck.

## Render Before Complete

A high-fidelity task is incomplete until it has:

- a changed `.pptx` or exported file,
- a validation report,
- and a PDF preview or an explicit `converter_unavailable` result.

Never mark a visual deck change complete based only on XML/package success.
