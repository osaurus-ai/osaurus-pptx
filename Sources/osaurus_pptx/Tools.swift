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
  guard resolved.hasPrefix(workDir) else {
    return .failure("Path is outside the working directory")
  }

  return .success(resolved)
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
    let path: String
    let _context: FolderContext?
  }

  func run(args: String, presentations: inout [String: Presentation]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return jsonError("Invalid arguments. Required: path (string)")
    }

    let pathResult = validatePath(input.path, workingDirectory: input._context?.working_directory)
    let absolutePath: String
    switch pathResult {
    case .success(let p): absolutePath = p
    case .failure(let msg): return jsonError(msg)
    }

    guard FileManager.default.fileExists(atPath: absolutePath) else {
      return jsonError("File not found: \(input.path)")
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
      return jsonError("Failed to read PPTX: \(error)")
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
    let overwrite: Bool?
    let dryRun: Bool?
    let _context: FolderContext?

    enum CodingKeys: String, CodingKey {
      case presentation_id
      case path
      case overwrite
      case dryRun = "dry_run"
      case _context
    }
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
    let exists = FileManager.default.fileExists(atPath: finalPath)

    if input.dryRun == true {
      return jsonSuccess([
        "path": finalPath,
        "slide_count": pres.slides.count,
        "presentation_id": pres.id,
        "file_exists": exists,
        "would_overwrite": exists,
        "dry_run": true,
      ])
    }

    if exists && input.overwrite != true {
      return jsonError("File already exists: \(finalPath). Pass overwrite=true to replace it.")
    }

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
