---
name: osaurus-pptx
description: Create PowerPoint (.pptx) presentations from scratch using the PPTX plugin. Use when the user asks to build, generate, or create a PowerPoint presentation, slide deck, or .pptx file.
metadata:
  author: osaurus
  version: "0.1.0"
---

# PPTX

Create PowerPoint (.pptx) presentations from scratch. This plugin is creation-only — treat every presentation as a fresh build.

## Workflow

Always follow this sequence:

1. **Plan first.** Decide the slide count, layout for each slide, and content before calling any tools. Elements cannot be modified after creation, so get it right on the first pass.
2. **`create_presentation`** — returns a `presentation_id`, slide dimensions, and theme info.
3. **`add_slide`** — add one slide at a time. Each returns a `slide_number`. Populate the slide with elements immediately before adding the next slide.
4. **Add elements** — use `add_text`, `add_image`, `add_shape`, `add_table`, `add_chart`, or `set_slide_background` to populate the current slide.
5. **`save_presentation`** — write the final `.pptx` file. Nothing is written to disk until this step.

Never skip steps. Never add elements before creating a slide. Always save at the end.

## Coordinate System

All positions and sizes are in **inches**, measured from the top-left corner of the slide.

| Aspect ratio | Width | Height |
|--------------|-------|--------|
| 16:9 (default) | 13.33" | 7.5" |
| 4:3 | 10.0" | 7.5" |

The `create_presentation` response includes `width_inches` and `height_inches` — always use these for positioning calculations rather than hardcoded values.

**Safe margins:** Leave at least **0.5"** on all edges. Usable area for 16:9 is x: 0.5"–12.83", y: 0.5"–7.0".

## Layout Recipes

Reference coordinates for common 16:9 slide layouts. Adjust proportionally for other aspect ratios.

### Title Slide

```
Title:    x=1.0  y=2.0  w=11.33 h=1.5  font_size=40 bold=true  alignment=center
Subtitle: x=1.0  y=4.0  w=11.33 h=1.0  font_size=24            alignment=center
```

### Section Header

```
Heading:  x=1.0  y=2.5  w=11.33 h=1.5  font_size=36 bold=true  alignment=center
```

### Title + Body

```
Title:    x=0.75 y=0.5  w=11.83 h=1.0  font_size=32 bold=true
Body:     x=0.75 y=1.75 w=11.83 h=5.0  font_size=18 bullets=true
```

### Title + Two Columns

```
Title:    x=0.75 y=0.5  w=11.83 h=1.0  font_size=32 bold=true
Left:     x=0.75 y=1.75 w=5.67  h=5.0  font_size=16
Right:    x=6.67 y=1.75 w=5.67  h=5.0  font_size=16
```

### Title + Image

```
Title:    x=0.75 y=0.5  w=11.83 h=1.0  font_size=32 bold=true
Image:    x=2.5  y=1.75 w=8.33  h=5.0
```

### Title + Image Left + Text Right

```
Title:    x=0.75 y=0.5  w=11.83 h=1.0  font_size=32 bold=true
Image:    x=0.75 y=1.75 w=5.67  h=5.0
Text:     x=6.67 y=1.75 w=5.67  h=5.0  font_size=16
```

### Title + Table or Chart

```
Title:    x=0.75 y=0.5  w=11.83 h=1.0  font_size=32 bold=true
Table:    x=0.75 y=1.75 w=11.83 h=5.0
Chart:    x=1.5  y=1.75 w=10.33 h=5.0
```

### Full-Bleed Image (no title)

```
Image:    x=0.0  y=0.0  w=13.33 h=7.5
```

## Themes

Choose a theme at creation time with the `theme` parameter. Let the theme handle styling — avoid hardcoding colors.

| Theme | Style | Best for |
|-------|-------|----------|
| `modern` (default) | Blue/orange, Calibri | General purpose |
| `corporate` | Navy/steel blue, Georgia headings | Business, formal |
| `creative` | Pink/purple, Avenir Next | Marketing, design |
| `minimal` | Grayscale, Helvetica Neue | Clean, text-heavy |
| `dark` | Purple/teal on dark bg, SF Pro | Technical, modern |

**Dark theme warning:** Background color is `121212`. Avoid dark text colors. Set slide backgrounds explicitly if needed.

**Choosing a theme:** Default to `modern` unless the user specifies a preference or the content suggests otherwise (e.g., quarterly business reviews suit `corporate`; pitch decks suit `creative`; developer talks suit `dark`).

## Design Best Practices

Follow these guidelines to produce professional-looking slides:

- **Keep slides focused.** One idea per slide. Aim for 5–7 bullet points max per slide.
- **Use short text.** Bullet points should be phrases, not sentences. Keep titles under 8 words.
- **Vary layouts.** Alternate between text-heavy, visual, and data slides to maintain visual interest.
- **Use font hierarchy.** Titles: 32–40pt bold. Body: 16–18pt. Captions: 12–14pt.
- **Use charts over tables** when showing trends, comparisons, or proportions. Reserve tables for precise reference data.
- **End with a closing slide.** Use a section header layout with "Thank You", "Questions?", or a call to action.

## Tool Reference

### `create_presentation`

- `size` controls aspect ratio, not layout. Default is `"16:9"`. Also accepts `"4:3"` or custom `"WxH"` (e.g., `"10x7.5"`).
- `theme` selects a built-in theme. See the Themes section above.

### `add_slide`

- `layout` is **metadata only**. It does not auto-generate content. Every slide starts blank. You must add all elements manually.

### `add_text`

- Use `\n` for line breaks and multi-paragraph text.
- Set `bullets=true` for bullet-pointed lists.
- Hex colors must omit the `#` prefix: use `"FF0000"`, not `"#FF0000"`.
- For centered titles, set `alignment: "center"` and `bold: true`.

### `add_image`

- Paths can be relative to the workspace or absolute.
- Supported formats: PNG, JPG, GIF, SVG, BMP, TIFF.
- Requires user permission (`ask` policy).

### `add_shape`

- Available types: `rect`, `round_rect`, `ellipse`, `triangle`, `diamond`, `pentagon`, `hexagon`, `octagon`, `star4`, `star5`, `star6`, `right_arrow`, `left_arrow`, `up_arrow`, `down_arrow`, `heart`, `cloud`, `lightning`, `line`, `parallelogram`, `trapezoid`.
- Shapes can contain text via the `text` parameter — useful for labeled diagrams and flowcharts.

### `add_table`

- `rows` is a 2D array of strings. The first row is the header by default (`has_header: true`).
- Column widths auto-distribute evenly. Use `column_widths` for custom sizing (array length must match column count).

### `add_chart`

- Types: `bar`, `column`, `line`, `pie`, `doughnut`.
- Each series needs a `name` and `values` array. Optionally set a `color` per series.
- `categories` are the x-axis labels.

### `set_slide_background`

- Sets a solid color background for a slide. Useful with the `dark` theme or for accent slides.

### `delete_slide`

- Removes a slide by `slide_number`. Use this to correct mistakes — delete the slide, re-add it, and rebuild its elements.

### `get_presentation_info`

- Returns slide count and metadata. Pass `include_details: true` to see all elements on all slides. Use this to verify the presentation before saving.

### `read_presentation`

- Reads an existing `.pptx` file. Only preserves text elements and slide backgrounds. Images, shapes, tables, and charts are not parsed. Use primarily for inspecting text content.

### `save_presentation`

- Always call this when done. Nothing is persisted until you save.
- The `.pptx` extension is added automatically if missing.
- Requires user permission (`ask` policy).

## Limitations and Corrections

**Elements cannot be modified after creation.** There are no tools to update text, reposition elements, or change properties on existing elements. Plan each slide fully before adding elements.

**Slides cannot be reordered.** Slides are ordered by insertion. Plan the sequence in advance. If order matters and it's wrong, rebuild the presentation.

**To fix a slide:** Call `delete_slide` to remove it, `add_slide` to re-add at the same position, rebuild all its elements, then `save_presentation`.

**To inspect what was built:** Call `get_presentation_info` with `include_details: true` to review all slides and elements before saving.

## Example

Build a 3-slide corporate presentation:

```
1. create_presentation(title="Q4 Report", theme="corporate")
   → presentation_id, width=13.33, height=7.5

2. add_slide(presentation_id, layout="title")
   → slide 1
3. add_text(presentation_id, slide_number=1, text="Q4 2025 Report",
     x=1.0, y=2.0, width=11.33, height=1.5,
     font_size=40, bold=true, alignment="center")
4. add_text(presentation_id, slide_number=1, text="Annual Review",
     x=1.0, y=4.0, width=11.33, height=1.0,
     font_size=24, alignment="center")

5. add_slide(presentation_id, layout="title_content")
   → slide 2
6. add_text(presentation_id, slide_number=2, text="Key Metrics",
     x=0.75, y=0.5, width=11.83, height=1.0,
     font_size=32, bold=true)
7. add_chart(presentation_id, slide_number=2, chart_type="column",
     categories=["Oct", "Nov", "Dec"],
     series=[{name: "Revenue", values: [120, 135, 150]}],
     title="Monthly Revenue",
     x=1.5, y=1.75, width=10.33, height=5.0)

8. add_slide(presentation_id, layout="blank")
   → slide 3
9. add_text(presentation_id, slide_number=3, text="Thank You",
     x=1.0, y=2.5, width=11.33, height=1.5,
     font_size=36, bold=true, alignment="center")

10. save_presentation(presentation_id, path="Q4_Report.pptx")
```
