import Foundation

// MARK: - Shared Decodable Types

struct FolderContext: Decodable {
  let working_directory: String
}

// MARK: - Path Validation Result

enum PathResult {
  case success(String)
  case failure(String)
}

// MARK: - Path Security

/// Canonical, component-aware containment check. Resolves symlinks on both
/// sides so lexical tricks (`..`, sibling prefixes, symlinked directories)
/// cannot escape the root.
func isContained(_ path: String, in root: String) -> Bool {
  let p = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
  let r = URL(fileURLWithPath: root).standardizedFileURL.resolvingSymlinksInPath().path
  return p == r || p.hasPrefix(r.hasSuffix("/") ? r : r + "/")
}

/// Canonicalize a path that may not exist yet: symlinks are resolved on the
/// deepest existing ancestor and the non-existing tail is re-appended.
func canonicalizePath(_ path: String) -> String {
  let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
  var existing = standardized
  var tail: [String] = []
  while !FileManager.default.fileExists(atPath: existing), existing != "/" {
    let url = URL(fileURLWithPath: existing)
    tail.append(url.lastPathComponent)
    existing = url.deletingLastPathComponent().path
  }
  var resolved = URL(fileURLWithPath: existing).resolvingSymlinksInPath()
  for component in tail.reversed() {
    resolved.appendPathComponent(component)
  }
  return resolved.path
}

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
  let resolved = canonicalizePath(absolutePath)
  guard isContained(resolved, in: workDir) else {
    return .failure("Path is outside the working directory")
  }

  return .success(resolved)
}

// MARK: - Numeric Validation

/// Returns an error message when the value is non-finite or outside the sane
/// range, nil when acceptable. Values reaching EMU conversion trap in
/// Int(Double) if NaN/infinite/huge, so these must be rejected up front.
func firstNumericError(_ checks: [(value: Double?, name: String, min: Double, max: Double)])
  -> String?
{
  for check in checks {
    guard let v = check.value else { continue }
    if !v.isFinite {
      return "\(check.name) must be a finite number"
    }
    if v < check.min || v > check.max {
      return "\(check.name) must be between \(check.min) and \(check.max)"
    }
  }
  return nil
}

// MARK: - Error Envelope Helper

func failureEnvelope(_ context: String, _ error: Error) -> String {
  if error is ProcessTimeoutError {
    return Envelope.failure(.timeout, "\(context): \(error)")
  }
  return Envelope.failure(.executionError, "\(context): \(error)")
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
      return Envelope.failure(.invalidArgs, "Invalid arguments. Required: title (string)")
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
        guard parts.count == 2,
          let w = Double(parts[0]),
          let h = Double(parts[1])
        else {
          return Envelope.failure(
            .invalidArgs,
            "Invalid size: \(size). Valid: '16:9', '4:3', or 'WxH' in inches (e.g. '10x7.5')")
        }
        if let err = firstNumericError([
          (w, "size width", 1, 200), (h, "size height", 1, 200),
        ]) {
          return Envelope.failure(.invalidArgs, err)
        }
        slideSize = .custom(width: w, height: h)
      }
    } else {
      slideSize = .widescreen
    }

    let validThemes = ["modern", "corporate", "creative", "minimal", "dark"]
    if let themeName = input.theme, !validThemes.contains(themeName.lowercased()) {
      return Envelope.failure(
        .invalidArgs,
        "Invalid theme: \(themeName). Valid: \(validThemes.joined(separator: ", "))")
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
      return Envelope.failure(.invalidArgs, "Invalid arguments. Required: presentation_id (string)")
    }

    guard let pres = presentations[input.presentation_id] else {
      return Envelope.failure(.notFound, "Presentation not found: \(input.presentation_id)")
    }

    let layoutType: SlideLayoutType
    if let layout = input.layout {
      guard let parsed = SlideLayoutType(rawValue: layout) else {
        return Envelope.failure(
          .invalidArgs,
          "Invalid layout: \(layout). Valid: blank, title, title_content, section_header, two_content, title_only"
        )
      }
      layoutType = parsed
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
      return Envelope.failure(.invalidArgs, "Invalid arguments. Required: presentation_id, slide_number, text")
    }

    guard let pres = presentations[input.presentation_id] else {
      return Envelope.failure(.notFound, "Presentation not found: \(input.presentation_id)")
    }

    guard input.slide_number >= 1 && input.slide_number <= pres.slides.count else {
      return Envelope.failure(
        .invalidArgs,
        "Invalid slide number: \(input.slide_number). Presentation has \(pres.slides.count) slides."
      )
    }

    if let err = firstNumericError([
      (input.x, "x", -1000, 1000),
      (input.y, "y", -1000, 1000),
      (input.width, "width", 0, 1000),
      (input.height, "height", 0, 1000),
      (input.font_size, "font_size", 1, 1000),
      (input.line_spacing, "line_spacing", 0, 1000),
      (input.rotation, "rotation", -3600, 3600),
    ]) {
      return Envelope.failure(.invalidArgs, err)
    }

    let validAlignments = ["left", "l", "center", "ctr", "right", "r", "justify", "just"]
    if let a = input.alignment, !validAlignments.contains(a.lowercased()) {
      return Envelope.failure(
        .invalidArgs, "Invalid alignment: \(a). Valid: left, center, right, justify")
    }
    let validVerticalAlignments = ["top", "t", "middle", "center", "ctr", "bottom", "b"]
    if let v = input.vertical_alignment, !validVerticalAlignments.contains(v.lowercased()) {
      return Envelope.failure(
        .invalidArgs, "Invalid vertical_alignment: \(v). Valid: top, middle, bottom")
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
      return Envelope.failure(.invalidArgs, "Invalid arguments. Required: presentation_id, slide_number, path")
    }

    guard let pres = presentations[input.presentation_id] else {
      return Envelope.failure(.notFound, "Presentation not found: \(input.presentation_id)")
    }

    guard input.slide_number >= 1 && input.slide_number <= pres.slides.count else {
      return Envelope.failure(
        .invalidArgs,
        "Invalid slide number: \(input.slide_number). Presentation has \(pres.slides.count) slides."
      )
    }

    if let err = firstNumericError([
      (input.x, "x", -1000, 1000),
      (input.y, "y", -1000, 1000),
      (input.width, "width", 0, 1000),
      (input.height, "height", 0, 1000),
    ]) {
      return Envelope.failure(.invalidArgs, err)
    }

    // Validate path
    let pathResult = validatePath(input.path, workingDirectory: input._context?.working_directory)
    let absolutePath: String
    switch pathResult {
    case .success(let p): absolutePath = p
    case .failure(let msg): return Envelope.failure(.invalidArgs, msg)
    }

    guard FileManager.default.fileExists(atPath: absolutePath) else {
      return Envelope.failure(.notFound, "Image file not found: \(input.path)")
    }

    let ext = (absolutePath as NSString).pathExtension.lowercased()
    let validExts = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "svg"]
    guard validExts.contains(ext) else {
      return Envelope.failure(
        .invalidArgs,
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
      return Envelope.failure(.invalidArgs, "Invalid arguments. Required: presentation_id, slide_number, shape_type")
    }

    guard let pres = presentations[input.presentation_id] else {
      return Envelope.failure(.notFound, "Presentation not found: \(input.presentation_id)")
    }

    guard input.slide_number >= 1 && input.slide_number <= pres.slides.count else {
      return Envelope.failure(
        .invalidArgs,
        "Invalid slide number: \(input.slide_number). Presentation has \(pres.slides.count) slides."
      )
    }

    guard let shapeType = ShapeType(rawValue: input.shape_type) else {
      let validTypes = [
        "rect", "round_rect", "ellipse", "triangle", "diamond", "pentagon", "hexagon", "octagon",
        "star4", "star5", "star6", "right_arrow", "left_arrow", "up_arrow", "down_arrow", "heart",
        "cloud", "lightning", "line", "parallelogram", "trapezoid",
      ]
      return Envelope.failure(
        .invalidArgs,
        "Invalid shape type: \(input.shape_type). Valid: \(validTypes.joined(separator: ", "))")
    }

    if let err = firstNumericError([
      (input.x, "x", -1000, 1000),
      (input.y, "y", -1000, 1000),
      (input.width, "width", 0, 1000),
      (input.height, "height", 0, 1000),
      (input.border_width, "border_width", 0, 100),
      (input.text_size, "text_size", 1, 1000),
      (input.rotation, "rotation", -3600, 3600),
    ]) {
      return Envelope.failure(.invalidArgs, err)
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
      return Envelope.failure(
        .invalidArgs,
        "Invalid arguments. Required: presentation_id, slide_number, rows (2D array)")
    }

    guard let pres = presentations[input.presentation_id] else {
      return Envelope.failure(.notFound, "Presentation not found: \(input.presentation_id)")
    }

    guard input.slide_number >= 1 && input.slide_number <= pres.slides.count else {
      return Envelope.failure(
        .invalidArgs,
        "Invalid slide number: \(input.slide_number). Presentation has \(pres.slides.count) slides."
      )
    }

    guard !input.rows.isEmpty else {
      return Envelope.failure(.invalidArgs, "Table must have at least one row")
    }

    var numericChecks: [(value: Double?, name: String, min: Double, max: Double)] = [
      (input.x, "x", -1000, 1000),
      (input.y, "y", -1000, 1000),
      (input.width, "width", 0, 1000),
      (input.height, "height", 0, 1000),
      (input.font_size, "font_size", 1, 1000),
    ]
    for (idx, width) in (input.column_widths ?? []).enumerated() {
      numericChecks.append((width, "column_widths[\(idx)]", 0, 1000))
    }
    if let err = firstNumericError(numericChecks) {
      return Envelope.failure(.invalidArgs, err)
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
      return Envelope.failure(
        .invalidArgs,
        "Invalid arguments. Required: presentation_id, slide_number, chart_type, categories, series"
      )
    }

    guard let pres = presentations[input.presentation_id] else {
      return Envelope.failure(.notFound, "Presentation not found: \(input.presentation_id)")
    }

    guard input.slide_number >= 1 && input.slide_number <= pres.slides.count else {
      return Envelope.failure(
        .invalidArgs,
        "Invalid slide number: \(input.slide_number). Presentation has \(pres.slides.count) slides."
      )
    }

    guard let chartType = ChartType(rawValue: input.chart_type) else {
      return Envelope.failure(
        .invalidArgs,
        "Invalid chart type: \(input.chart_type). Valid: bar, column, line, pie, doughnut")
    }

    guard !input.series.isEmpty else {
      return Envelope.failure(.invalidArgs, "Chart must have at least one data series")
    }

    guard !input.categories.isEmpty else {
      return Envelope.failure(.invalidArgs, "Chart must have at least one category")
    }

    if let err = firstNumericError([
      (input.x, "x", -1000, 1000),
      (input.y, "y", -1000, 1000),
      (input.width, "width", 0, 1000),
      (input.height, "height", 0, 1000),
    ]) {
      return Envelope.failure(.invalidArgs, err)
    }
    for series in input.series {
      if let err = firstNumericError(
        series.values.map { ($0 as Double?, "series \"\(series.name)\" value", -1e12, 1e12) })
      {
        return Envelope.failure(.invalidArgs, err)
      }
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
      return Envelope.failure(
        .invalidArgs,
        "Invalid arguments. Required: presentation_id, slide_number, and either color or gradient_color1+gradient_color2"
      )
    }

    guard let pres = presentations[input.presentation_id] else {
      return Envelope.failure(.notFound, "Presentation not found: \(input.presentation_id)")
    }

    guard input.slide_number >= 1 && input.slide_number <= pres.slides.count else {
      return Envelope.failure(
        .invalidArgs,
        "Invalid slide number: \(input.slide_number). Presentation has \(pres.slides.count) slides."
      )
    }

    if let err = firstNumericError([
      (input.gradient_angle, "gradient_angle", -3600, 3600)
    ]) {
      return Envelope.failure(.invalidArgs, err)
    }

    let slide = pres.slides[input.slide_number - 1]

    if let color = input.color {
      slide.background = SlideBackground(type: .solid(color: color))
    } else if let c1 = input.gradient_color1, let c2 = input.gradient_color2 {
      slide.background = SlideBackground(
        type: .gradient(color1: c1, color2: c2, angle: input.gradient_angle ?? 270))
    } else {
      return Envelope.failure(
        .invalidArgs,
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
      return Envelope.failure(.invalidArgs, "Invalid arguments. Required: presentation_id, slide_number")
    }

    guard let pres = presentations[input.presentation_id] else {
      return Envelope.failure(.notFound, "Presentation not found: \(input.presentation_id)")
    }

    guard input.slide_number >= 1 && input.slide_number <= pres.slides.count else {
      return Envelope.failure(
        .invalidArgs,
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
    let path: String
    let _context: FolderContext?
  }

  func run(args: String, presentations: inout [String: Presentation]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return Envelope.failure(.invalidArgs, "Invalid arguments. Required: path (string)")
    }

    let pathResult = validatePath(input.path, workingDirectory: input._context?.working_directory)
    let absolutePath: String
    switch pathResult {
    case .success(let p): absolutePath = p
    case .failure(let msg): return Envelope.failure(.invalidArgs, msg)
    }

    guard FileManager.default.fileExists(atPath: absolutePath) else {
      return Envelope.failure(.notFound, "File not found: \(input.path)")
    }

    do {
      let pres = try PPTXReader.read(from: absolutePath)
      presentations[pres.id] = pres

      return jsonSuccess([
        "presentation_id": pres.id,
        "title": pres.title,
        "slide_count": pres.slides.count,
        "source_path": absolutePath,
      ])
    } catch {
      return failureEnvelope("Failed to read PPTX", error)
    }
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
      return Envelope.failure(.invalidArgs, "Invalid arguments. Required: presentation_id")
    }

    guard let pres = presentations[input.presentation_id] else {
      return Envelope.failure(.notFound, "Presentation not found: \(input.presentation_id)")
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
      return Envelope.failure(.invalidArgs, "Invalid arguments. Required: presentation_id, path")
    }

    guard let pres = presentations[input.presentation_id] else {
      return Envelope.failure(.notFound, "Presentation not found: \(input.presentation_id)")
    }

    let pathResult = validatePath(input.path, workingDirectory: input._context?.working_directory)
    let absolutePath: String
    switch pathResult {
    case .success(let p): absolutePath = p
    case .failure(let msg): return Envelope.failure(.invalidArgs, msg)
    }

    // Ensure path ends with .pptx
    let finalPath = absolutePath.hasSuffix(".pptx") ? absolutePath : "\(absolutePath).pptx"

    do {
      let writeResult = try PPTXWriter.write(presentation: pres, to: finalPath)
      return jsonSuccess([
        "path": finalPath,
        "slide_count": pres.slides.count,
        "presentation_id": pres.id,
        "skipped_images": writeResult.skippedImages,
      ])
    } catch {
      return failureEnvelope("Failed to save presentation", error)
    }
  }
}
