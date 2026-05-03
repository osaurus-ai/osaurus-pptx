import Foundation

// MARK: - Shared Decodable Types

struct FolderContext: Decodable {
  let working_directory: String?
  let attachments: [InputAttachment]?
}

struct InputAttachment: Decodable {
  let id: String
  let filename: String
  let mime_type: String
  let file_size: Int?
  let host_path: String

  var pathExtension: String {
    (host_path as NSString).pathExtension.lowercased()
  }
}

// MARK: - Path Validation Result

enum PathResult {
  case success(String)
  case failure(String)
}

// MARK: - Path Security

func validatePath(_ path: String, workingDirectory: String?) -> PathResult {
  guard let workDir = workingDirectory else {
    // If no working directory context, only allow absolute paths
    if path.hasPrefix("/") {
      return .success(path)
    }
    return .failure("No working directory context. Please select a folder in Osaurus Agent Mode.")
  }

  let absolutePath: String
  if path.hasPrefix("/") {
    absolutePath = path
  } else {
    absolutePath = "\(workDir)/\(path)"
  }

  // Resolve and validate
  let resolved = URL(fileURLWithPath: absolutePath).standardized.path
  let resolvedWorkDir = URL(fileURLWithPath: workDir).standardized.path
  guard resolved == resolvedWorkDir || resolved.hasPrefix(resolvedWorkDir + "/") else {
    return .failure("Path is outside the working directory")
  }

  return .success(resolved)
}

func resolveInputPath(
  path: String?,
  attachmentId: String?,
  context: FolderContext?,
  allowedExtensions: Set<String>
) -> PathResult {
  let attachments = context?.attachments ?? []

  if let attachmentId, !attachmentId.isEmpty {
    guard
      let attachment = attachments.first(where: {
        $0.id == attachmentId || $0.filename == attachmentId || $0.host_path == attachmentId
      })
    else {
      return .failure("Attachment not found in _context.attachments: \(attachmentId)")
    }
    return validateResolvedInputPath(
      attachment.host_path, displayName: attachment.filename, allowedExtensions: allowedExtensions)
  }

  if let path, !path.isEmpty {
    if let attachment = attachments.first(where: {
      $0.id == path || $0.filename == path || $0.host_path == path
    }) {
      return validateResolvedInputPath(
        attachment.host_path, displayName: attachment.filename, allowedExtensions: allowedExtensions)
    }

    let pathResult = validatePath(path, workingDirectory: context?.working_directory)
    switch pathResult {
    case .success(let resolved):
      return validateResolvedInputPath(
        resolved, displayName: path, allowedExtensions: allowedExtensions)
    case .failure(let message):
      return .failure(message)
    }
  }

  return .failure("Provide either path or attachment_id")
}

func validateResolvedInputPath(
  _ resolvedPath: String,
  displayName: String,
  allowedExtensions: Set<String>
) -> PathResult {
  let ext = (resolvedPath as NSString).pathExtension.lowercased()
  guard allowedExtensions.contains(ext) else {
    return .failure(
      "Unsupported file format for \(displayName): \(ext). Supported: \(allowedExtensions.sorted().joined(separator: ", "))"
    )
  }

  guard FileManager.default.fileExists(atPath: resolvedPath) else {
    return .failure("File not found: \(displayName)")
  }

  return .success(resolvedPath)
}

func resolveSourcePresentationPath(
  path: String?,
  attachmentId: String?,
  presentationId: String?,
  context: FolderContext?,
  presentations: [String: Presentation]
) -> PathResult {
  if path != nil || attachmentId != nil {
    return resolveInputPath(
      path: path,
      attachmentId: attachmentId,
      context: context,
      allowedExtensions: ["ppt", "pptx", "ppsx", "potx"])
  }

  if let presentationId {
    guard let presentation = presentations[presentationId] else {
      return .failure("Presentation not found: \(presentationId)")
    }
    guard let sourcePath = presentation.sourcePath else {
      return .failure("Presentation \(presentationId) was created in memory and has no source file")
    }
    return validateResolvedInputPath(
      sourcePath,
      displayName: sourcePath,
      allowedExtensions: ["ppt", "pptx", "ppsx", "potx"])
  }

  return .failure("Provide path, attachment_id, or presentation_id")
}

func structuredStatus(_ status: String, message: String, fields: [String: Any] = [:]) -> String {
  var result = fields
  result["status"] = status
  result["message"] = message
  return jsonSuccess(result)
}

// MARK: - Tool: create_presentation

struct CreatePresentationTool {
  let name = "create_presentation"

  struct Args: Decodable {
    let title: String
    let size: String?  // "16:9", "4:3", or "WxH" in inches
    let theme: String?  // "modern", "corporate", "creative", "minimal", "dark"
    let _context: FolderContext?
  }

  func run(args: String, presentations: inout [String: Presentation]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return jsonError("Invalid arguments. Required: title (string)")
    }

    let slideSize: SlideSize
    if let size = input.size {
      switch size {
      case "16:9", "widescreen":
        slideSize = .widescreen
      case "4:3", "standard":
        slideSize = .standard
      default:
        // Try to parse "WxH" format
        let parts = size.split(separator: "x")
        if parts.count == 2,
          let w = Double(parts[0]),
          let h = Double(parts[1])
        {
          slideSize = .custom(width: w, height: h)
        } else {
          slideSize = .widescreen
        }
      }
    } else {
      slideSize = .widescreen
    }

    let theme = ThemePresets.named(input.theme ?? "modern")
    let pres = Presentation(title: input.title, layout: slideSize, theme: theme)

    presentations[pres.id] = pres

    let widthInches = Double(pres.slideWidth) / Double(Units.emuPerInch)
    let heightInches = Double(pres.slideHeight) / Double(Units.emuPerInch)

    return jsonSuccess([
      "presentation_id": pres.id,
      "title": pres.title,
      "theme": theme.name,
      "slide_count": 0,
      "width_inches": widthInches,
      "height_inches": heightInches,
    ])
  }
}

// MARK: - Tool: add_slide

struct AddSlideTool {
  let name = "add_slide"

  struct Args: Decodable {
    let presentation_id: String
    let layout: String?  // "blank", "title", "title_content", "section_header", "two_content", "title_only"
    let _context: FolderContext?
  }

  func run(args: String, presentations: inout [String: Presentation]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return jsonError("Invalid arguments. Required: presentation_id (string)")
    }

    guard let pres = presentations[input.presentation_id] else {
      return jsonError("Presentation not found: \(input.presentation_id)")
    }

    let layoutType: SlideLayoutType
    if let layout = input.layout {
      layoutType = SlideLayoutType(rawValue: layout) ?? .blank
    } else {
      layoutType = .blank
    }

    let slide = Slide(layoutType: layoutType)
    pres.slides.append(slide)
    let slideNumber = pres.slides.count

    return jsonSuccess([
      "slide_number": slideNumber,
      "slide_id": slide.id,
      "layout": layoutType.rawValue,
      "presentation_id": pres.id,
    ])
  }
}

// MARK: - Tool: add_text

struct AddTextTool {
  let name = "add_text"

  struct Args: Decodable {
    let presentation_id: String
    let slide_number: Int
    let text: String
    let x: Double?
    let y: Double?
    let width: Double?
    let height: Double?
    let font_size: Double?
    let font_face: String?
    let font_color: String?
    let bold: Bool?
    let italic: Bool?
    let underline: Bool?
    let alignment: String?
    let vertical_alignment: String?
    let line_spacing: Double?
    let bullets: Bool?
    let word_wrap: Bool?
    let rotation: Double?
    let _context: FolderContext?
  }

  func run(args: String, presentations: inout [String: Presentation]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return jsonError("Invalid arguments. Required: presentation_id, slide_number, text")
    }

    guard let pres = presentations[input.presentation_id] else {
      return jsonError("Presentation not found: \(input.presentation_id)")
    }

    guard input.slide_number >= 1 && input.slide_number <= pres.slides.count else {
      return jsonError(
        "Invalid slide number: \(input.slide_number). Presentation has \(pres.slides.count) slides."
      )
    }

    let slide = pres.slides[input.slide_number - 1]
    let position = ElementPosition(
      x: input.x ?? 1.0,
      y: input.y ?? 1.0,
      width: input.width ?? 8.0,
      height: input.height ?? 1.5
    )

    let textEl = TextElement(
      text: input.text,
      position: position,
      fontSize: input.font_size ?? 18,
      fontFace: input.font_face ?? pres.theme.fontBody,
      fontColor: input.font_color ?? pres.theme.textColor,
      bold: input.bold ?? false,
      italic: input.italic ?? false,
      underline: input.underline ?? false,
      alignment: TextAlignment(from: input.alignment ?? "left"),
      verticalAlignment: VerticalAlignment(from: input.vertical_alignment ?? "top"),
      lineSpacing: input.line_spacing,
      bullets: input.bullets ?? false,
      wordWrap: input.word_wrap ?? true,
      rotation: input.rotation
    )

    slide.elements.append(textEl)

    return jsonSuccess([
      "element_id": textEl.elementId,
      "slide_number": input.slide_number,
      "element_type": "text",
    ])
  }
}

// MARK: - Tool: add_image

struct AddImageTool {
  let name = "add_image"

  struct Args: Decodable {
    let presentation_id: String
    let slide_number: Int
    let path: String
    let x: Double?
    let y: Double?
    let width: Double?
    let height: Double?
    let _context: FolderContext?
  }

  func run(args: String, presentations: inout [String: Presentation]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return jsonError("Invalid arguments. Required: presentation_id, slide_number, path")
    }

    guard let pres = presentations[input.presentation_id] else {
      return jsonError("Presentation not found: \(input.presentation_id)")
    }

    guard input.slide_number >= 1 && input.slide_number <= pres.slides.count else {
      return jsonError("Invalid slide number: \(input.slide_number)")
    }

    // Validate path
    let pathResult = validatePath(input.path, workingDirectory: input._context?.working_directory)
    let absolutePath: String
    switch pathResult {
    case .success(let p): absolutePath = p
    case .failure(let msg): return jsonError(msg)
    }

    guard FileManager.default.fileExists(atPath: absolutePath) else {
      return jsonError("Image file not found: \(input.path)")
    }

    let ext = (absolutePath as NSString).pathExtension.lowercased()
    let validExts = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "svg"]
    guard validExts.contains(ext) else {
      return jsonError(
        "Unsupported image format: \(ext). Supported: \(validExts.joined(separator: ", "))")
    }

    let slide = pres.slides[input.slide_number - 1]
    let position = ElementPosition(
      x: input.x ?? 2.0,
      y: input.y ?? 2.0,
      width: input.width ?? 5.0,
      height: input.height ?? 3.5
    )

    let imageEl = ImageElement(
      sourcePath: absolutePath,
      position: position,
      imageExtension: ext == "jpeg" ? "jpg" : ext
    )

    slide.elements.append(imageEl)

    return jsonSuccess([
      "element_id": imageEl.elementId,
      "slide_number": input.slide_number,
      "element_type": "image",
      "path": absolutePath,
    ])
  }
}

// MARK: - Tool: add_shape

struct AddShapeTool {
  let name = "add_shape"

  struct Args: Decodable {
    let presentation_id: String
    let slide_number: Int
    let shape_type: String
    let x: Double?
    let y: Double?
    let width: Double?
    let height: Double?
    let fill_color: String?
    let border_color: String?
    let border_width: Double?
    let text: String?
    let text_color: String?
    let text_size: Double?
    let rotation: Double?
    let _context: FolderContext?
  }

  func run(args: String, presentations: inout [String: Presentation]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return jsonError("Invalid arguments. Required: presentation_id, slide_number, shape_type")
    }

    guard let pres = presentations[input.presentation_id] else {
      return jsonError("Presentation not found: \(input.presentation_id)")
    }

    guard input.slide_number >= 1 && input.slide_number <= pres.slides.count else {
      return jsonError("Invalid slide number: \(input.slide_number)")
    }

    guard let shapeType = ShapeType(rawValue: input.shape_type) else {
      let validTypes = [
        "rect", "round_rect", "ellipse", "triangle", "diamond", "pentagon", "hexagon", "octagon",
        "star4", "star5", "star6", "right_arrow", "left_arrow", "up_arrow", "down_arrow", "heart",
        "cloud", "lightning", "line", "parallelogram", "trapezoid",
      ]
      return jsonError(
        "Invalid shape type: \(input.shape_type). Valid: \(validTypes.joined(separator: ", "))")
    }

    let slide = pres.slides[input.slide_number - 1]
    let position = ElementPosition(
      x: input.x ?? 3.0,
      y: input.y ?? 2.0,
      width: input.width ?? 3.0,
      height: input.height ?? 2.0
    )

    let shapeEl = ShapeElement(
      shapeType: shapeType,
      position: position,
      fillColor: input.fill_color,
      borderColor: input.border_color,
      borderWidth: input.border_width ?? 1.0,
      text: input.text,
      textColor: input.text_color ?? pres.theme.textColor,
      textSize: input.text_size ?? 14,
      rotation: input.rotation
    )

    slide.elements.append(shapeEl)

    return jsonSuccess([
      "element_id": shapeEl.elementId,
      "slide_number": input.slide_number,
      "element_type": "shape",
      "shape_type": input.shape_type,
    ])
  }
}

// MARK: - Tool: add_table

struct AddTableTool {
  let name = "add_table"

  struct Args: Decodable {
    let presentation_id: String
    let slide_number: Int
    let rows: [[String]]
    let x: Double?
    let y: Double?
    let width: Double?
    let height: Double?
    let has_header: Bool?
    let header_color: String?
    let header_text_color: String?
    let alternate_row_color: String?
    let border_color: String?
    let font_size: Double?
    let font_face: String?
    let column_widths: [Double]?
    let merged_cells: [MergedCell]?
    let _context: FolderContext?
  }

  func run(args: String, presentations: inout [String: Presentation]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return jsonError(
        "Invalid arguments. Required: presentation_id, slide_number, rows (2D array)")
    }

    guard let pres = presentations[input.presentation_id] else {
      return jsonError("Presentation not found: \(input.presentation_id)")
    }

    guard input.slide_number >= 1 && input.slide_number <= pres.slides.count else {
      return jsonError("Invalid slide number: \(input.slide_number)")
    }

    guard !input.rows.isEmpty else {
      return jsonError("Table must have at least one row")
    }

    let slide = pres.slides[input.slide_number - 1]
    let position = ElementPosition(
      x: input.x ?? 1.0,
      y: input.y ?? 1.5,
      width: input.width ?? 11.0,
      height: input.height ?? 4.0
    )

    let tableEl = TableElement(
      rows: input.rows,
      position: position,
      hasHeader: input.has_header ?? true,
      headerColor: input.header_color ?? pres.theme.primaryColor,
      headerTextColor: input.header_text_color ?? pres.theme.lightTextColor,
      alternateRowColor: input.alternate_row_color,
      borderColor: input.border_color ?? pres.theme.primaryColor,
      fontSize: input.font_size ?? 12,
      fontFace: input.font_face ?? pres.theme.fontBody,
      columnWidths: input.column_widths,
      mergedCells: input.merged_cells ?? []
    )

    slide.elements.append(tableEl)

    return jsonSuccess([
      "element_id": tableEl.elementId,
      "slide_number": input.slide_number,
      "element_type": "table",
      "row_count": input.rows.count,
      "column_count": input.rows.first?.count ?? 0,
    ])
  }
}

// MARK: - Tool: add_chart

struct AddChartTool {
  let name = "add_chart"

  struct Args: Decodable {
    let presentation_id: String
    let slide_number: Int
    let chart_type: String  // "bar", "column", "line", "pie", "doughnut"
    let categories: [String]
    let series: [ChartSeriesArg]
    let title: String?
    let x: Double?
    let y: Double?
    let width: Double?
    let height: Double?
    let show_legend: Bool?
    let show_data_labels: Bool?
    let _context: FolderContext?
  }

  struct ChartSeriesArg: Decodable {
    let name: String
    let values: [Double]
    let color: String?
  }

  func run(args: String, presentations: inout [String: Presentation]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return jsonError(
        "Invalid arguments. Required: presentation_id, slide_number, chart_type, categories, series"
      )
    }

    guard let pres = presentations[input.presentation_id] else {
      return jsonError("Presentation not found: \(input.presentation_id)")
    }

    guard input.slide_number >= 1 && input.slide_number <= pres.slides.count else {
      return jsonError("Invalid slide number: \(input.slide_number)")
    }

    guard let chartType = ChartType(rawValue: input.chart_type) else {
      return jsonError(
        "Invalid chart type: \(input.chart_type). Valid: bar, column, line, pie, doughnut")
    }

    guard !input.series.isEmpty else {
      return jsonError("Chart must have at least one data series")
    }

    guard !input.categories.isEmpty else {
      return jsonError("Chart must have at least one category")
    }

    let slide = pres.slides[input.slide_number - 1]
    let position = ElementPosition(
      x: input.x ?? 1.5,
      y: input.y ?? 1.5,
      width: input.width ?? 8.0,
      height: input.height ?? 5.0
    )

    let seriesModels = input.series.map {
      ChartSeries(name: $0.name, values: $0.values, color: $0.color)
    }

    let chartEl = ChartElement(
      chartType: chartType,
      position: position,
      chartTitle: input.title,
      series: seriesModels,
      categories: input.categories,
      showLegend: input.show_legend ?? true,
      showDataLabels: input.show_data_labels ?? false
    )

    slide.elements.append(chartEl)

    return jsonSuccess([
      "element_id": chartEl.elementId,
      "slide_number": input.slide_number,
      "element_type": "chart",
      "chart_type": input.chart_type,
    ])
  }
}

// MARK: - Tool: set_slide_background

struct SetSlideBackgroundTool {
  let name = "set_slide_background"

  struct Args: Decodable {
    let presentation_id: String
    let slide_number: Int
    let color: String?
    let gradient_color1: String?
    let gradient_color2: String?
    let gradient_angle: Double?
    let _context: FolderContext?
  }

  func run(args: String, presentations: inout [String: Presentation]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return jsonError(
        "Invalid arguments. Required: presentation_id, slide_number, and either color or gradient_color1+gradient_color2"
      )
    }

    guard let pres = presentations[input.presentation_id] else {
      return jsonError("Presentation not found: \(input.presentation_id)")
    }

    guard input.slide_number >= 1 && input.slide_number <= pres.slides.count else {
      return jsonError("Invalid slide number: \(input.slide_number)")
    }

    let slide = pres.slides[input.slide_number - 1]

    if let color = input.color {
      slide.background = SlideBackground(type: .solid(color: color))
    } else if let c1 = input.gradient_color1, let c2 = input.gradient_color2 {
      slide.background = SlideBackground(
        type: .gradient(color1: c1, color2: c2, angle: input.gradient_angle ?? 270))
    } else {
      return jsonError(
        "Provide either 'color' for solid background or 'gradient_color1' and 'gradient_color2' for gradient"
      )
    }

    return jsonSuccess([
      "slide_number": input.slide_number,
      "background": "set",
    ])
  }
}

// MARK: - Tool: delete_slide

struct DeleteSlideTool {
  let name = "delete_slide"

  struct Args: Decodable {
    let presentation_id: String
    let slide_number: Int
    let _context: FolderContext?
  }

  func run(args: String, presentations: inout [String: Presentation]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return jsonError("Invalid arguments. Required: presentation_id, slide_number")
    }

    guard let pres = presentations[input.presentation_id] else {
      return jsonError("Presentation not found: \(input.presentation_id)")
    }

    guard input.slide_number >= 1 && input.slide_number <= pres.slides.count else {
      return jsonError(
        "Invalid slide number: \(input.slide_number). Presentation has \(pres.slides.count) slides."
      )
    }

    pres.slides.remove(at: input.slide_number - 1)

    return jsonSuccess([
      "deleted_slide_number": input.slide_number,
      "remaining_slides": pres.slides.count,
    ])
  }
}

// MARK: - Tool: read_presentation

struct ReadPresentationTool {
  let name = "read_presentation"

  struct Args: Decodable {
    let path: String?
    let attachment_id: String?
    let _context: FolderContext?
  }

  func run(args: String, presentations: inout [String: Presentation]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return jsonError("Invalid arguments. Provide path or attachment_id")
    }

    let pathResult = resolveInputPath(
      path: input.path,
      attachmentId: input.attachment_id,
      context: input._context,
      allowedExtensions: ["pptx", "ppsx", "potx"])
    let absolutePath: String
    switch pathResult {
    case .success(let p): absolutePath = p
    case .failure(let msg): return jsonError(msg)
    }

    do {
      let pres = try PPTXReader.read(from: absolutePath)
      presentations[pres.id] = pres

      let slidesJSON = ReadPresentationTool.describeSlides(pres)
      return jsonSuccess([
        "presentation_id": pres.id,
        "title": pres.title,
        "slide_count": pres.slides.count,
        "width_inches": Double(pres.slideWidth) / Double(Units.emuPerInch),
        "height_inches": Double(pres.slideHeight) / Double(Units.emuPerInch),
        "source_path": absolutePath,
        "slides": JSONRaw(slidesJSON),
        "fidelity_warnings": pres.fidelityWarnings,
      ])
    } catch {
      return jsonError("Failed to read PPTX: \(error)")
    }
  }

  private static func describeSlides(_ presentation: Presentation) -> String {
    var slides: [String] = []
    for (slideIndex, slide) in presentation.slides.enumerated() {
      var elements: [String] = []
      for element in slide.elements {
        if let text = element as? TextElement {
          elements.append(
            """
            {"id": "\(jsonEscape(text.elementId))", "type": "text", "text": "\(jsonEscape(text.text))", "x": \(text.position.x), "y": \(text.position.y), "width": \(text.position.width), "height": \(text.position.height), "font_size": \(text.fontSize)}
            """)
        } else if let image = element as? ImageElement {
          elements.append(
            """
            {"id": "\(jsonEscape(image.elementId))", "type": "image", "path": "\(jsonEscape(image.sourcePath))", "x": \(image.position.x), "y": \(image.position.y), "width": \(image.position.width), "height": \(image.position.height)}
            """)
        }
      }
      slides.append(
        """
        {"number": \(slideIndex + 1), "id": "\(jsonEscape(slide.id))", "layout": "\(slide.layoutType.rawValue)", "element_count": \(slide.elements.count), "elements": [\(elements.joined(separator: ","))]}
        """)
    }
    return "[\(slides.joined(separator: ","))]"
  }
}

// MARK: - Tool: get_presentation_info

struct GetPresentationInfoTool {
  let name = "get_presentation_info"

  struct Args: Decodable {
    let presentation_id: String
    let include_details: Bool?
    let _context: FolderContext?
  }

  func run(args: String, presentations: inout [String: Presentation]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return jsonError("Invalid arguments. Required: presentation_id")
    }

    guard let pres = presentations[input.presentation_id] else {
      return jsonError("Presentation not found: \(input.presentation_id)")
    }

    let widthInches = Double(pres.slideWidth) / Double(Units.emuPerInch)
    let heightInches = Double(pres.slideHeight) / Double(Units.emuPerInch)

    if input.include_details == true {
      // Build detailed slide info
      var slidesJSON = "["
      for (idx, slide) in pres.slides.enumerated() {
        if idx > 0 { slidesJSON += ", " }

        var elementsJSON = "["
        for (eIdx, element) in slide.elements.enumerated() {
          if eIdx > 0 { elementsJSON += ", " }
          elementsJSON += describeElement(element)
        }
        elementsJSON += "]"

        let bgDesc: String
        if let bg = slide.background {
          switch bg.type {
          case .solid(let c): bgDesc = "solid:\(c)"
          case .gradient(let c1, let c2, _): bgDesc = "gradient:\(c1)-\(c2)"
          }
        } else {
          bgDesc = "none"
        }

        slidesJSON +=
          "{\"number\": \(idx + 1), \"layout\": \"\(slide.layoutType.rawValue)\", \"background\": \"\(bgDesc)\", \"element_count\": \(slide.elements.count), \"elements\": \(elementsJSON)}"
      }
      slidesJSON += "]"

      return jsonSuccess([
        "presentation_id": pres.id,
        "title": pres.title,
        "theme": pres.theme.name,
        "slide_count": pres.slides.count,
        "width_inches": widthInches,
        "height_inches": heightInches,
        "slides": JSONRaw(slidesJSON),
      ])
    } else {
      var slidesSummary = "["
      for (idx, slide) in pres.slides.enumerated() {
        if idx > 0 { slidesSummary += ", " }
        slidesSummary +=
          "{\"number\": \(idx + 1), \"layout\": \"\(slide.layoutType.rawValue)\", \"element_count\": \(slide.elements.count)}"
      }
      slidesSummary += "]"

      return jsonSuccess([
        "presentation_id": pres.id,
        "title": pres.title,
        "theme": pres.theme.name,
        "slide_count": pres.slides.count,
        "width_inches": widthInches,
        "height_inches": heightInches,
        "slides": JSONRaw(slidesSummary),
      ])
    }
  }

  private func describeElement(_ element: SlideElement) -> String {
    if let text = element as? TextElement {
      let preview = String(text.text.prefix(50))
      return
        "{\"type\": \"text\", \"id\": \"\(text.elementId)\", \"text\": \"\(jsonEscape(preview))\", \"font_size\": \(text.fontSize), \"bold\": \(text.bold), \"x\": \(text.position.x), \"y\": \(text.position.y), \"width\": \(text.position.width), \"height\": \(text.position.height)}"
    } else if let image = element as? ImageElement {
      return
        "{\"type\": \"image\", \"id\": \"\(image.elementId)\", \"path\": \"\(jsonEscape(image.sourcePath))\", \"x\": \(image.position.x), \"y\": \(image.position.y), \"width\": \(image.position.width), \"height\": \(image.position.height)}"
    } else if let shape = element as? ShapeElement {
      return
        "{\"type\": \"shape\", \"id\": \"\(shape.elementId)\", \"shape_type\": \"\(shape.shapeType.rawValue)\", \"x\": \(shape.position.x), \"y\": \(shape.position.y), \"width\": \(shape.position.width), \"height\": \(shape.position.height)}"
    } else if let table = element as? TableElement {
      return
        "{\"type\": \"table\", \"id\": \"\(table.elementId)\", \"rows\": \(table.rows.count), \"columns\": \(table.rows.first?.count ?? 0)}"
    } else if let chart = element as? ChartElement {
      return
        "{\"type\": \"chart\", \"id\": \"\(chart.elementId)\", \"chart_type\": \"\(chart.chartType.rawValue)\", \"series_count\": \(chart.series.count)}"
    }
    return "{\"type\": \"unknown\"}"
  }
}

// MARK: - Tool: save_presentation

struct SavePresentationTool {
  let name = "save_presentation"

  struct Args: Decodable {
    let presentation_id: String
    let path: String
    let _context: FolderContext?
  }

  func run(args: String, presentations: inout [String: Presentation]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return jsonError("Invalid arguments. Required: presentation_id, path")
    }

    guard let pres = presentations[input.presentation_id] else {
      return jsonError("Presentation not found: \(input.presentation_id)")
    }

    let pathResult = validatePath(input.path, workingDirectory: input._context?.working_directory)
    let absolutePath: String
    switch pathResult {
    case .success(let p): absolutePath = p
    case .failure(let msg): return jsonError(msg)
    }

    // Ensure path ends with .pptx
    let finalPath = absolutePath.hasSuffix(".pptx") ? absolutePath : "\(absolutePath).pptx"

    do {
      try PPTXWriter.write(presentation: pres, to: finalPath)
      return jsonSuccess([
        "path": finalPath,
        "slide_count": pres.slides.count,
        "presentation_id": pres.id,
      ])
    } catch {
      return jsonError("Failed to save presentation: \(error)")
    }
  }
}

// MARK: - Tool: validate_presentation

struct ValidatePresentationTool {
  let name = "validate_presentation"

  struct Args: Decodable {
    let path: String?
    let attachment_id: String?
    let _context: FolderContext?
  }

  func run(args: String) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return jsonError("Invalid arguments. Provide path or attachment_id")
    }

    let source = resolveInputPath(
      path: input.path,
      attachmentId: input.attachment_id,
      context: input._context,
      allowedExtensions: ["pptx", "ppsx", "potx"])
    let absolutePath: String
    switch source {
    case .success(let path): absolutePath = path
    case .failure(let message): return jsonError(message)
    }

    do {
      let inspection = try PPTXPackage.inspect(filePath: absolutePath)
      return jsonSuccess([
        "valid": true,
        "path": absolutePath,
        "slide_count": inspection.slideCount,
        "width_inches": Double(inspection.widthEMU) / Double(Units.emuPerInch),
        "height_inches": Double(inspection.heightEMU) / Double(Units.emuPerInch),
        "slides": JSONRaw(inspection.slidesJSON),
        "warnings": inspection.warnings,
      ])
    } catch {
      return jsonSuccess([
        "valid": false,
        "path": absolutePath,
        "errors": [String(describing: error)],
      ])
    }
  }
}

// MARK: - Tool: export_presentation

struct ExportPresentationTool {
  let name = "export_presentation"

  struct Args: Decodable {
    let path: String?
    let attachment_id: String?
    let presentation_id: String?
    let output_path: String
    let format: String?
    let _context: FolderContext?
  }

  func run(args: String, presentations: [String: Presentation]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return jsonError("Invalid arguments. Required: output_path plus path, attachment_id, or presentation_id")
    }

    let source = resolveSourcePresentationPath(
      path: input.path,
      attachmentId: input.attachment_id,
      presentationId: input.presentation_id,
      context: input._context,
      presentations: presentations)
    let inputPath: String
    switch source {
    case .success(let path): inputPath = path
    case .failure(let message): return jsonError(message)
    }

    let requestedFormat = (input.format ?? (input.output_path as NSString).pathExtension)
      .lowercased()
    let format = requestedFormat.isEmpty ? "pdf" : requestedFormat
    guard ["pdf", "pptx"].contains(format) else {
      return jsonError("Unsupported export format: \(format). Supported: pdf, pptx")
    }

    let outputResult = validatePath(input.output_path, workingDirectory: input._context?.working_directory)
    let outputPath: String
    switch outputResult {
    case .success(let path): outputPath = path.hasSuffix(".\(format)") ? path : "\(path).\(format)"
    case .failure(let message): return jsonError(message)
    }

    let inputExt = (inputPath as NSString).pathExtension.lowercased()
    if format == "pptx", inputExt == "pptx" {
      do {
        let outputDir = (outputPath as NSString).deletingLastPathComponent
        try createDirectoryIfNeeded(outputDir)
        if FileManager.default.fileExists(atPath: outputPath) {
          try FileManager.default.removeItem(atPath: outputPath)
        }
        try FileManager.default.copyItem(atPath: inputPath, toPath: outputPath)
        return jsonSuccess([
          "status": "ok",
          "input_path": inputPath,
          "output_path": outputPath,
          "format": format,
          "converter_used": false,
        ])
      } catch {
        return jsonError("Failed to copy PPTX: \(error)")
      }
    }

    let filter: String
    switch format {
    case "pdf":
      filter = "impress_pdf_Export"
    case "pptx":
      filter = "Impress MS PowerPoint 2007 XML"
    default:
      filter = ""
    }

    do {
      let result = try ConverterHelper.convertPresentation(
        inputPath: inputPath,
        outputPath: outputPath,
        format: format,
        filter: filter)
      return converterResultJSON(result, format: format)
    } catch {
      return jsonError("Export failed: \(error)")
    }
  }
}

// MARK: - Tool: render_presentation

struct RenderPresentationTool {
  let name = "render_presentation"

  struct Args: Decodable {
    let path: String?
    let attachment_id: String?
    let presentation_id: String?
    let output_path: String?
    let _context: FolderContext?
  }

  func run(args: String, presentations: [String: Presentation]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return jsonError("Invalid arguments. Provide path, attachment_id, or presentation_id")
    }

    let source = resolveSourcePresentationPath(
      path: input.path,
      attachmentId: input.attachment_id,
      presentationId: input.presentation_id,
      context: input._context,
      presentations: presentations)
    let inputPath: String
    switch source {
    case .success(let path): inputPath = path
    case .failure(let message): return jsonError(message)
    }

    let defaultName =
      ((inputPath as NSString).lastPathComponent as NSString).deletingPathExtension + ".pdf"
    let requestedOutput = input.output_path ?? defaultName
    let outputResult = validatePath(requestedOutput, workingDirectory: input._context?.working_directory)
    let outputPath: String
    switch outputResult {
    case .success(let path): outputPath = path.hasSuffix(".pdf") ? path : "\(path).pdf"
    case .failure(let message): return jsonError(message)
    }

    do {
      let result = try ConverterHelper.convertPresentation(
        inputPath: inputPath,
        outputPath: outputPath,
        format: "pdf",
        filter: "impress_pdf_Export")
      return converterResultJSON(result, format: "pdf")
    } catch {
      return jsonError("Render failed: \(error)")
    }
  }
}

// MARK: - Tool: update_text

struct UpdateTextTool {
  let name = "update_text"

  struct Args: Decodable {
    let path: String?
    let attachment_id: String?
    let presentation_id: String?
    let output_path: String
    let slide_number: Int
    let element_id: String?
    let match_text: String?
    let replacement_text: String
    let _context: FolderContext?
  }

  func run(args: String, presentations: [String: Presentation]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return jsonError(
        "Invalid arguments. Required: output_path, slide_number, replacement_text, plus path/attachment_id/presentation_id")
    }
    guard input.element_id != nil || input.match_text != nil else {
      return jsonError("Provide element_id or match_text so update_text has a precise target")
    }

    let source = resolveSourcePresentationPath(
      path: input.path,
      attachmentId: input.attachment_id,
      presentationId: input.presentation_id,
      context: input._context,
      presentations: presentations)
    let inputPath: String
    switch source {
    case .success(let path): inputPath = path
    case .failure(let message): return jsonError(message)
    }

    let outputPathResult = validatePath(input.output_path, workingDirectory: input._context?.working_directory)
    let outputPath: String
    switch outputPathResult {
    case .success(let path): outputPath = path.hasSuffix(".pptx") ? path : "\(path).pptx"
    case .failure(let message): return jsonError(message)
    }

    do {
      let report = try PPTXPackage.updateText(
        inputPath: inputPath,
        outputPath: outputPath,
        slideNumber: input.slide_number,
        elementId: input.element_id,
        matchText: input.match_text,
        replacementText: input.replacement_text)
      return jsonSuccess([
        "status": "ok",
        "output_path": report.outputPath,
        "changed_count": report.changedCount,
        "warnings": report.warnings,
      ])
    } catch {
      return jsonError("Failed to update text: \(error)")
    }
  }
}

// MARK: - Tool: replace_image

struct ReplaceImageTool {
  let name = "replace_image"

  struct Args: Decodable {
    let path: String?
    let attachment_id: String?
    let presentation_id: String?
    let output_path: String
    let slide_number: Int
    let element_id: String
    let image_path: String
    let _context: FolderContext?
  }

  func run(args: String, presentations: [String: Presentation]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return jsonError("Invalid arguments. Required: output_path, slide_number, element_id, image_path")
    }

    let source = resolveSourcePresentationPath(
      path: input.path,
      attachmentId: input.attachment_id,
      presentationId: input.presentation_id,
      context: input._context,
      presentations: presentations)
    let inputPath: String
    switch source {
    case .success(let path): inputPath = path
    case .failure(let message): return jsonError(message)
    }

    let imageResult = validatePath(input.image_path, workingDirectory: input._context?.working_directory)
    let imagePath: String
    switch imageResult {
    case .success(let path): imagePath = path
    case .failure(let message): return jsonError(message)
    }

    let outputResult = validatePath(input.output_path, workingDirectory: input._context?.working_directory)
    let outputPath: String
    switch outputResult {
    case .success(let path): outputPath = path.hasSuffix(".pptx") ? path : "\(path).pptx"
    case .failure(let message): return jsonError(message)
    }

    do {
      let report = try PPTXPackage.replaceImage(
        inputPath: inputPath,
        outputPath: outputPath,
        slideNumber: input.slide_number,
        elementId: input.element_id,
        imagePath: imagePath)
      return jsonSuccess([
        "status": "ok",
        "output_path": report.outputPath,
        "changed_count": report.changedCount,
        "warnings": report.warnings,
      ])
    } catch {
      return jsonError("Failed to replace image: \(error)")
    }
  }
}

// MARK: - Tool: move_resize_element

struct MoveResizeElementTool {
  let name = "move_resize_element"

  struct Args: Decodable {
    let path: String?
    let attachment_id: String?
    let presentation_id: String?
    let output_path: String
    let slide_number: Int
    let element_id: String
    let x: Double?
    let y: Double?
    let width: Double?
    let height: Double?
    let _context: FolderContext?
  }

  func run(args: String, presentations: [String: Presentation]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return jsonError("Invalid arguments. Required: output_path, slide_number, element_id")
    }

    let source = resolveSourcePresentationPath(
      path: input.path,
      attachmentId: input.attachment_id,
      presentationId: input.presentation_id,
      context: input._context,
      presentations: presentations)
    let inputPath: String
    switch source {
    case .success(let path): inputPath = path
    case .failure(let message): return jsonError(message)
    }

    let outputResult = validatePath(input.output_path, workingDirectory: input._context?.working_directory)
    let outputPath: String
    switch outputResult {
    case .success(let path): outputPath = path.hasSuffix(".pptx") ? path : "\(path).pptx"
    case .failure(let message): return jsonError(message)
    }

    do {
      let report = try PPTXPackage.moveResizeElement(
        inputPath: inputPath,
        outputPath: outputPath,
        slideNumber: input.slide_number,
        elementId: input.element_id,
        x: input.x,
        y: input.y,
        width: input.width,
        height: input.height)
      return jsonSuccess([
        "status": "ok",
        "output_path": report.outputPath,
        "changed_count": report.changedCount,
        "warnings": report.warnings,
      ])
    } catch {
      return jsonError("Failed to move/resize element: \(error)")
    }
  }
}

// MARK: - Tool: duplicate_slide

struct DuplicateSlideTool {
  let name = "duplicate_slide"

  struct Args: Decodable {
    let path: String?
    let attachment_id: String?
    let presentation_id: String?
    let output_path: String
    let slide_number: Int
    let _context: FolderContext?
  }

  func run(args: String, presentations: [String: Presentation]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return jsonError("Invalid arguments. Required: output_path and slide_number")
    }

    let source = resolveSourcePresentationPath(
      path: input.path,
      attachmentId: input.attachment_id,
      presentationId: input.presentation_id,
      context: input._context,
      presentations: presentations)
    let inputPath: String
    switch source {
    case .success(let path): inputPath = path
    case .failure(let message): return jsonError(message)
    }

    let outputResult = validatePath(input.output_path, workingDirectory: input._context?.working_directory)
    let outputPath: String
    switch outputResult {
    case .success(let path): outputPath = path.hasSuffix(".pptx") ? path : "\(path).pptx"
    case .failure(let message): return jsonError(message)
    }

    do {
      let report = try PPTXPackage.duplicateSlide(
        inputPath: inputPath,
        outputPath: outputPath,
        slideNumber: input.slide_number)
      return jsonSuccess([
        "status": "ok",
        "output_path": report.outputPath,
        "changed_count": report.changedCount,
        "warnings": report.warnings,
      ])
    } catch {
      return jsonError("Failed to duplicate slide: \(error)")
    }
  }
}

// MARK: - Tool: reorder_slides

struct ReorderSlidesTool {
  let name = "reorder_slides"

  struct Args: Decodable {
    let path: String?
    let attachment_id: String?
    let presentation_id: String?
    let output_path: String
    let slide_order: [Int]
    let _context: FolderContext?
  }

  func run(args: String, presentations: [String: Presentation]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return jsonError("Invalid arguments. Required: output_path and slide_order")
    }

    let source = resolveSourcePresentationPath(
      path: input.path,
      attachmentId: input.attachment_id,
      presentationId: input.presentation_id,
      context: input._context,
      presentations: presentations)
    let inputPath: String
    switch source {
    case .success(let path): inputPath = path
    case .failure(let message): return jsonError(message)
    }

    let outputResult = validatePath(input.output_path, workingDirectory: input._context?.working_directory)
    let outputPath: String
    switch outputResult {
    case .success(let path): outputPath = path.hasSuffix(".pptx") ? path : "\(path).pptx"
    case .failure(let message): return jsonError(message)
    }

    do {
      let report = try PPTXPackage.reorderSlides(
        inputPath: inputPath,
        outputPath: outputPath,
        slideOrder: input.slide_order)
      return jsonSuccess([
        "status": "ok",
        "output_path": report.outputPath,
        "changed_count": report.changedCount,
        "warnings": report.warnings,
      ])
    } catch {
      return jsonError("Failed to reorder slides: \(error)")
    }
  }
}

// MARK: - Tool: set_speaker_notes

struct SetSpeakerNotesTool {
  let name = "set_speaker_notes"

  struct Args: Decodable {
    let path: String?
    let attachment_id: String?
    let presentation_id: String?
    let output_path: String?
    let slide_number: Int?
    let notes: String?
    let _context: FolderContext?
  }

  func run(args: String, presentations: [String: Presentation]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return jsonError("Invalid arguments. Required: output_path, slide_number, notes")
    }
    guard let slideNumber = input.slide_number, let notes = input.notes else {
      return jsonError("Required: slide_number and notes")
    }
    guard let output = input.output_path else {
      return jsonError("Required: output_path")
    }

    let source = resolveSourcePresentationPath(
      path: input.path,
      attachmentId: input.attachment_id,
      presentationId: input.presentation_id,
      context: input._context,
      presentations: presentations)
    let inputPath: String
    switch source {
    case .success(let path): inputPath = path
    case .failure(let message): return jsonError(message)
    }

    let outputResult = validatePath(output, workingDirectory: input._context?.working_directory)
    let outputPath: String
    switch outputResult {
    case .success(let path): outputPath = path.hasSuffix(".pptx") ? path : "\(path).pptx"
    case .failure(let message): return jsonError(message)
    }

    do {
      let report = try PPTXPackage.setSpeakerNotes(
        inputPath: inputPath,
        outputPath: outputPath,
        slideNumber: slideNumber,
        notes: notes)
      return jsonSuccess([
        "status": "ok",
        "output_path": report.outputPath,
        "changed_count": report.changedCount,
        "warnings": report.warnings,
      ])
    } catch {
      return jsonError("Failed to set speaker notes: \(error)")
    }
  }
}

private func converterResultJSON(_ result: ConverterResult, format: String) -> String {
  jsonSuccess([
    "status": result.status,
    "input_path": result.inputPath,
    "output_path": result.outputPath ?? "",
    "format": format,
    "converter_path": result.executablePath ?? "",
    "message": result.message,
    "converter_used": result.executablePath != nil,
  ])
}
