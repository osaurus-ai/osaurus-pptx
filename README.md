# osaurus-pptx

An [Osaurus](https://osaurus.ai) plugin for creating, inspecting, patching, rendering, validating, and exporting PowerPoint presentations.

New `.pptx` decks can be generated without external dependencies. Existing deck edits use package-level OOXML patching where possible so unrelated masters, layouts, charts, media, and relationships are preserved. Rendering and legacy `.ppt` conversion are optional LibreOffice-backed helpers.

## Tools

| Tool                    | Description                                                                                         |
| ----------------------- | --------------------------------------------------------------------------------------------------- |
| `create_presentation`   | Create a new presentation with a title, layout (16:9, 4:3, custom), and theme                       |
| `add_slide`             | Add a slide with a layout type (blank, title, title_content, section_header, etc.)                  |
| `add_text`              | Add a text box with rich formatting — font, size, color, bold, italic, alignment, bullets, rotation |
| `add_image`             | Add an image from a file (PNG, JPG, GIF, SVG, BMP, TIFF)                                            |
| `add_shape`             | Add a geometric shape (21 types including rect, ellipse, arrows, stars, heart, cloud)               |
| `add_table`             | Add a data table with header styling, alternating row colors, and cell merging                      |
| `add_chart`             | Add a chart (bar, column, line, pie, doughnut) with series data                                     |
| `set_slide_background`  | Set a solid color or gradient background on a slide                                                 |
| `delete_slide`          | Remove a slide by number                                                                            |
| `read_presentation`     | Read an existing .pptx file into memory                                                             |
| `get_presentation_info` | Get metadata and content summary, with optional detailed element info                               |
| `save_presentation`     | Save a presentation as a .pptx file                                                                 |
| `validate_presentation` | Validate and structurally inspect a PPTX-style package                                              |
| `render_presentation`   | Render a presentation to PDF using LibreOffice when available                                       |
| `export_presentation`   | Export PPT/PPTX/PPSX/POTX to PDF or PPTX                                                           |
| `update_text`           | Patch text in an existing PPTX package and write a new file                                         |
| `replace_image`         | Replace an existing image part while updating relationships/content types as needed                 |
| `move_resize_element`   | Move or resize an existing text/image element using inch coordinates                                |
| `duplicate_slide`       | Duplicate a slide and append it to the deck                                                         |
| `reorder_slides`        | Reorder slides using a 1-based complete permutation                                                 |
| `set_speaker_notes`     | Patch speaker notes for a slide                                                                     |

## High-fidelity workflow

Existing file tasks should follow:

1. Attach/import the original file.
2. Inspect with `read_presentation` or `validate_presentation`.
3. Patch with the narrowest package tool.
4. Render/export with `render_presentation` or `export_presentation`.
5. Validate the changed package before sharing.

`.pptx` is the editable canonical format. Legacy `.ppt` is convert-only and requires LibreOffice.

## Themes

Five built-in themes: **Modern** (default), **Corporate**, **Creative**, **Minimal**, and **Dark**. Each theme controls colors, fonts, and styling across all elements.

## Development

### Build

```bash
swift build -c release
```

### Test

```bash
swift test
```

### Install locally

```bash
osaurus manifest extract .build/release/libosaurus-pptx.dylib
osaurus tools package osaurus.pptx 0.1.0
osaurus tools install ./osaurus.pptx-0.1.0.zip
```

## Publishing

This project includes a GitHub Actions workflow (`.github/workflows/release.yml`) that automatically builds and releases the plugin when you push a version tag.

```bash
git tag v0.1.0
git push origin v0.1.0
```

## License

MIT
