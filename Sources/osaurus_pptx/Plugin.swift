import Foundation

// MARK: - Manifest

/// File-scope plugin manifest JSON, returned verbatim by `get_manifest`.
let pptxManifestJSON = """
  {
    "plugin_id": "osaurus.pptx",
    "name": "PPTX",
    "version": "0.1.0",
    "description": "Create, modify, and export PowerPoint presentations. Supports text, images, shapes, tables, charts, themes, and more.",
    "license": "MIT",
    "authors": [],
    "min_macos": "15.0",
    "min_osaurus": "0.5.0",
    "capabilities": {
      "tools": [
        {
          "id": "create_presentation",
          "description": "Create a new PowerPoint presentation. Returns a presentation_id to use with other tools.",
          "parameters": {
            "type": "object",
            "properties": {
              "title": {"type": "string", "description": "Presentation title"},
              "size": {"type": "string", "description": "Slide size: '16:9' (default), '4:3', or 'WxH' in inches (e.g. '10x7.5')"},
              "theme": {"type": "string", "description": "Theme preset: modern (default), corporate, creative, minimal, dark"}
            },
            "required": ["title"]
          },
          "requirements": [],
          "permission_policy": "auto"
        },
        {
          "id": "add_slide",
          "description": "Add a new slide to a presentation. The layout parameter is metadata only — you must add elements (text, images, shapes, etc.) manually using add_text, add_image, and other tools.",
          "parameters": {
            "type": "object",
            "properties": {
              "presentation_id": {"type": "string", "description": "Presentation ID from create_presentation"},
              "layout": {"type": "string", "description": "Layout type: blank (default), title, title_content, section_header, two_content, title_only"}
            },
            "required": ["presentation_id"]
          },
          "requirements": [],
          "permission_policy": "auto"
        },
        {
          "id": "add_text",
          "description": "Add a text box to a slide with rich formatting options.",
          "parameters": {
            "type": "object",
            "properties": {
              "presentation_id": {"type": "string", "description": "Presentation ID"},
              "slide_number": {"type": "integer", "description": "Slide number (1-based)"},
              "text": {"type": "string", "description": "Text content (use \\n for line breaks)"},
              "x": {"type": "number", "description": "X position in inches from left (default: 1.0)"},
              "y": {"type": "number", "description": "Y position in inches from top (default: 1.0)"},
              "width": {"type": "number", "description": "Width in inches (default: 8.0)"},
              "height": {"type": "number", "description": "Height in inches (default: 1.5)"},
              "font_size": {"type": "number", "description": "Font size in points (default: 18)"},
              "font_face": {"type": "string", "description": "Font name (default: theme font)"},
              "font_color": {"type": "string", "description": "Hex color e.g. 'FF0000' (default: theme text color)"},
              "bold": {"type": "boolean", "description": "Bold text (default: false)"},
              "italic": {"type": "boolean", "description": "Italic text (default: false)"},
              "underline": {"type": "boolean", "description": "Underline text (default: false)"},
              "alignment": {"type": "string", "description": "Text alignment: left (default), center, right, justify"},
              "vertical_alignment": {"type": "string", "description": "Vertical alignment: top (default), middle, bottom"},
              "line_spacing": {"type": "number", "description": "Line spacing in points"},
              "bullets": {"type": "boolean", "description": "Show bullet points (default: false)"},
              "word_wrap": {"type": "boolean", "description": "Enable word wrap (default: true)"},
              "rotation": {"type": "number", "description": "Rotation in degrees"}
            },
            "required": ["presentation_id", "slide_number", "text"]
          },
          "requirements": [],
          "permission_policy": "auto"
        },
        {
          "id": "add_image",
          "description": "Add an image to a slide from a file in the workspace. Supports PNG, JPG, GIF, SVG, BMP, TIFF.",
          "parameters": {
            "type": "object",
            "properties": {
              "presentation_id": {"type": "string", "description": "Presentation ID"},
              "slide_number": {"type": "integer", "description": "Slide number (1-based)"},
              "path": {"type": "string", "description": "Path to image file (relative to workspace or absolute)"},
              "x": {"type": "number", "description": "X position in inches (default: 2.0)"},
              "y": {"type": "number", "description": "Y position in inches (default: 2.0)"},
              "width": {"type": "number", "description": "Width in inches (default: 5.0)"},
              "height": {"type": "number", "description": "Height in inches (default: 3.5)"}
            },
            "required": ["presentation_id", "slide_number", "path"]
          },
          "requirements": [],
          "permission_policy": "ask"
        },
        {
          "id": "add_shape",
          "description": "Add a geometric shape to a slide. 21 shape types available including rectangles, arrows, stars, and more.",
          "parameters": {
            "type": "object",
            "properties": {
              "presentation_id": {"type": "string", "description": "Presentation ID"},
              "slide_number": {"type": "integer", "description": "Slide number (1-based)"},
              "shape_type": {"type": "string", "description": "Shape type: rect, round_rect, ellipse, triangle, diamond, pentagon, hexagon, octagon, star4, star5, star6, right_arrow, left_arrow, up_arrow, down_arrow, heart, cloud, lightning, line, parallelogram, trapezoid"},
              "x": {"type": "number", "description": "X position in inches (default: 3.0)"},
              "y": {"type": "number", "description": "Y position in inches (default: 2.0)"},
              "width": {"type": "number", "description": "Width in inches (default: 3.0)"},
              "height": {"type": "number", "description": "Height in inches (default: 2.0)"},
              "fill_color": {"type": "string", "description": "Fill color as hex (e.g. '4472C4')"},
              "border_color": {"type": "string", "description": "Border color as hex"},
              "border_width": {"type": "number", "description": "Border width in points (default: 1.0)"},
              "text": {"type": "string", "description": "Text to display inside shape"},
              "text_color": {"type": "string", "description": "Text color as hex (default: theme text color)"},
              "text_size": {"type": "number", "description": "Text size in points (default: 14)"},
              "rotation": {"type": "number", "description": "Rotation in degrees"}
            },
            "required": ["presentation_id", "slide_number", "shape_type"]
          },
          "requirements": [],
          "permission_policy": "auto"
        },
        {
          "id": "add_table",
          "description": "Add a data table to a slide with header styling, alternating row colors, and optional cell merging.",
          "parameters": {
            "type": "object",
            "properties": {
              "presentation_id": {"type": "string", "description": "Presentation ID"},
              "slide_number": {"type": "integer", "description": "Slide number (1-based)"},
              "rows": {"type": "array", "items": {"type": "array", "items": {"type": "string"}}, "description": "2D array of cell values. First row is header if has_header is true."},
              "x": {"type": "number", "description": "X position in inches (default: 1.0)"},
              "y": {"type": "number", "description": "Y position in inches (default: 1.5)"},
              "width": {"type": "number", "description": "Width in inches (default: 11.0)"},
              "height": {"type": "number", "description": "Height in inches (default: 4.0)"},
              "has_header": {"type": "boolean", "description": "First row is styled as header (default: true)"},
              "header_color": {"type": "string", "description": "Header background color as hex (default: theme primary)"},
              "header_text_color": {"type": "string", "description": "Header text color as hex (default: white)"},
              "alternate_row_color": {"type": "string", "description": "Alternating row background color as hex"},
              "border_color": {"type": "string", "description": "Border color as hex (default: theme primary)"},
              "font_size": {"type": "number", "description": "Font size in points (default: 12)"},
              "font_face": {"type": "string", "description": "Font name (default: theme font)"},
              "column_widths": {"type": "array", "items": {"type": "number"}, "description": "Column widths in inches (must match column count)"},
              "merged_cells": {"type": "array", "items": {"type": "object", "properties": {"row": {"type": "integer"}, "col": {"type": "integer"}, "rowSpan": {"type": "integer"}, "colSpan": {"type": "integer"}}}, "description": "Cells to merge (0-based row/col indices)"}
            },
            "required": ["presentation_id", "slide_number", "rows"]
          },
          "requirements": [],
          "permission_policy": "auto"
        },
        {
          "id": "add_chart",
          "description": "Add a chart to a slide. Supports bar, column, line, pie, and doughnut chart types.",
          "parameters": {
            "type": "object",
            "properties": {
              "presentation_id": {"type": "string", "description": "Presentation ID"},
              "slide_number": {"type": "integer", "description": "Slide number (1-based)"},
              "chart_type": {"type": "string", "description": "Chart type: bar, column, line, pie, doughnut"},
              "categories": {"type": "array", "items": {"type": "string"}, "description": "Category labels (x-axis)"},
              "series": {"type": "array", "items": {"type": "object", "properties": {"name": {"type": "string"}, "values": {"type": "array", "items": {"type": "number"}}, "color": {"type": "string"}}, "required": ["name", "values"]}, "description": "Data series array"},
              "title": {"type": "string", "description": "Chart title"},
              "x": {"type": "number", "description": "X position in inches (default: 1.5)"},
              "y": {"type": "number", "description": "Y position in inches (default: 1.5)"},
              "width": {"type": "number", "description": "Width in inches (default: 8.0)"},
              "height": {"type": "number", "description": "Height in inches (default: 5.0)"},
              "show_legend": {"type": "boolean", "description": "Show legend (default: true)"},
              "show_data_labels": {"type": "boolean", "description": "Show data labels (default: false)"}
            },
            "required": ["presentation_id", "slide_number", "chart_type", "categories", "series"]
          },
          "requirements": [],
          "permission_policy": "auto"
        },
        {
          "id": "set_slide_background",
          "description": "Set a slide's background to a solid color or gradient.",
          "parameters": {
            "type": "object",
            "properties": {
              "presentation_id": {"type": "string", "description": "Presentation ID"},
              "slide_number": {"type": "integer", "description": "Slide number (1-based)"},
              "color": {"type": "string", "description": "Solid background color as hex (e.g. '1F3864')"},
              "gradient_color1": {"type": "string", "description": "Gradient start color as hex"},
              "gradient_color2": {"type": "string", "description": "Gradient end color as hex"},
              "gradient_angle": {"type": "number", "description": "Gradient angle in degrees (default: 270, top to bottom)"}
            },
            "required": ["presentation_id", "slide_number"]
          },
          "requirements": [],
          "permission_policy": "auto"
        },
        {
          "id": "delete_slide",
          "description": "Remove a slide from a presentation by its number.",
          "parameters": {
            "type": "object",
            "properties": {
              "presentation_id": {"type": "string", "description": "Presentation ID"},
              "slide_number": {"type": "integer", "description": "Slide number to delete (1-based)"}
            },
            "required": ["presentation_id", "slide_number"]
          },
          "requirements": [],
          "permission_policy": "ask"
        },
        {
          "id": "read_presentation",
          "description": "Read an existing PPTX file into memory for viewing or modification. Returns a presentation_id.",
          "parameters": {
            "type": "object",
            "properties": {
              "path": {"type": "string", "description": "Path to PPTX file (relative to workspace or absolute)"}
            },
            "required": ["path"]
          },
          "requirements": [],
          "permission_policy": "ask"
        },
        {
          "id": "get_presentation_info",
          "description": "Get metadata and content summary for a presentation. Use include_details=true for full element details.",
          "parameters": {
            "type": "object",
            "properties": {
              "presentation_id": {"type": "string", "description": "Presentation ID"},
              "include_details": {"type": "boolean", "description": "Include detailed element info for each slide (default: false)"}
            },
            "required": ["presentation_id"]
          },
          "requirements": [],
          "permission_policy": "auto"
        },
        {
          "id": "save_presentation",
          "description": "Save a presentation as a .pptx file to the workspace.",
          "parameters": {
            "type": "object",
            "properties": {
              "presentation_id": {"type": "string", "description": "Presentation ID"},
              "path": {"type": "string", "description": "Output file path (relative to workspace or absolute). .pptx extension added if missing."}
            },
            "required": ["presentation_id", "path"]
          },
          "requirements": [],
          "permission_policy": "ask"
        }
      ]
    }
  }
  """

// MARK: - C ABI surface

// Opaque context
private typealias osr_plugin_ctx_t = UnsafeMutableRawPointer

// Function pointers
private typealias osr_free_string_t = @convention(c) (UnsafePointer<CChar>?) -> Void
private typealias osr_init_t = @convention(c) () -> osr_plugin_ctx_t?
private typealias osr_destroy_t = @convention(c) (osr_plugin_ctx_t?) -> Void
private typealias osr_get_manifest_t = @convention(c) (osr_plugin_ctx_t?) -> UnsafePointer<CChar>?
private typealias osr_invoke_t =
  @convention(c) (
    osr_plugin_ctx_t?,
    UnsafePointer<CChar>?,  // type
    UnsafePointer<CChar>?,  // id
    UnsafePointer<CChar>?  // payload
  ) -> UnsafePointer<CChar>?

private struct osr_plugin_api {
  var free_string: osr_free_string_t?
  var `init`: osr_init_t?
  var destroy: osr_destroy_t?
  var get_manifest: osr_get_manifest_t?
  var invoke: osr_invoke_t?
}

// MARK: - Plugin Context

private class PluginContext: @unchecked Sendable {
  var presentations: [String: Presentation] = [:]

  // Tools
  let createPresentation = CreatePresentationTool()
  let addSlide = AddSlideTool()
  let addText = AddTextTool()
  let addImage = AddImageTool()
  let addShape = AddShapeTool()
  let addTable = AddTableTool()
  let addChart = AddChartTool()
  let setSlideBackground = SetSlideBackgroundTool()
  let deleteSlide = DeleteSlideTool()
  let readPresentation = ReadPresentationTool()
  let getPresentationInfo = GetPresentationInfoTool()
  let savePresentation = SavePresentationTool()
}

// Helper to return C strings
private func makeCString(_ s: String) -> UnsafePointer<CChar>? {
  return UnsafePointer(strdup(s))
}

// MARK: - API Implementation

nonisolated(unsafe) private var api: osr_plugin_api = {
  var api = osr_plugin_api()

  api.free_string = { ptr in
    if let p = ptr { free(UnsafeMutableRawPointer(mutating: p)) }
  }

  api.`init` = {
    let ctx = PluginContext()
    return Unmanaged.passRetained(ctx).toOpaque()
  }

  api.destroy = { ctxPtr in
    guard let ctxPtr = ctxPtr else { return }
    Unmanaged<PluginContext>.fromOpaque(ctxPtr).release()
  }

  api.get_manifest = { _ in
    return makeCString(pptxManifestJSON)
  }

  api.invoke = { ctxPtr, typePtr, idPtr, payloadPtr in
    guard let ctxPtr = ctxPtr,
      let typePtr = typePtr,
      let idPtr = idPtr,
      let payloadPtr = payloadPtr
    else { return nil }

    let ctx = Unmanaged<PluginContext>.fromOpaque(ctxPtr).takeUnretainedValue()
    let type = String(cString: typePtr)
    let id = String(cString: idPtr)
    let payload = String(cString: payloadPtr)

    guard type == "tool" else {
      return makeCString(Envelope.failure(.invalidArgs, "Unknown capability type: \(type)"))
    }

    let result: String
    switch id {
    case ctx.createPresentation.name:
      result = ctx.createPresentation.run(args: payload, presentations: &ctx.presentations)
    case ctx.addSlide.name:
      result = ctx.addSlide.run(args: payload, presentations: &ctx.presentations)
    case ctx.addText.name:
      result = ctx.addText.run(args: payload, presentations: &ctx.presentations)
    case ctx.addImage.name:
      result = ctx.addImage.run(args: payload, presentations: &ctx.presentations)
    case ctx.addShape.name:
      result = ctx.addShape.run(args: payload, presentations: &ctx.presentations)
    case ctx.addTable.name:
      result = ctx.addTable.run(args: payload, presentations: &ctx.presentations)
    case ctx.addChart.name:
      result = ctx.addChart.run(args: payload, presentations: &ctx.presentations)
    case ctx.setSlideBackground.name:
      result = ctx.setSlideBackground.run(args: payload, presentations: &ctx.presentations)
    case ctx.deleteSlide.name:
      result = ctx.deleteSlide.run(args: payload, presentations: &ctx.presentations)
    case ctx.readPresentation.name:
      result = ctx.readPresentation.run(args: payload, presentations: &ctx.presentations)
    case ctx.getPresentationInfo.name:
      result = ctx.getPresentationInfo.run(args: payload, presentations: &ctx.presentations)
    case ctx.savePresentation.name:
      result = ctx.savePresentation.run(args: payload, presentations: &ctx.presentations)
    default:
      result = Envelope.failure(.notFound, "Unknown tool: \(id)")
    }

    return makeCString(result)
  }

  return api
}()

@_cdecl("osaurus_plugin_entry")
public func osaurus_plugin_entry() -> UnsafeRawPointer? {
  return UnsafeRawPointer(&api)
}
