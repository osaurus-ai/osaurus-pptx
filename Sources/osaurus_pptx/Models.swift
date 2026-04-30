import Foundation

// MARK: - Presentation

final class Presentation: @unchecked Sendable {
  let id: String
  var title: String
  var slides: [Slide] = []
  var theme: Theme
  var slideWidth: Int  // EMU
  var slideHeight: Int  // EMU
  var sourcePath: String?  // If read from file
  var fidelityWarnings: [String] = []

  init(
    id: String = UUID().uuidString, title: String, layout: SlideSize = .widescreen,
    theme: Theme = ThemePresets.modern
  ) {
    self.id = id
    self.title = title
    self.theme = theme
    switch layout {
    case .widescreen:
      self.slideWidth = SlideDimensions.wideWidth
      self.slideHeight = SlideDimensions.wideHeight
    case .standard:
      self.slideWidth = SlideDimensions.standardWidth
      self.slideHeight = SlideDimensions.standardHeight
    case .custom(let w, let h):
      self.slideWidth = Units.inchesToEMU(w)
      self.slideHeight = Units.inchesToEMU(h)
    }
  }
}

// MARK: - Slide Size

enum SlideSize {
  case widescreen  // 16:9
  case standard  // 4:3
  case custom(width: Double, height: Double)  // inches
}

// MARK: - Slide Layout Type

enum SlideLayoutType: String, Codable {
  case blank
  case title
  case titleContent = "title_content"
  case sectionHeader = "section_header"
  case twoContent = "two_content"
  case titleOnly = "title_only"
}

// MARK: - Slide

final class Slide: @unchecked Sendable {
  let id: String
  var layoutType: SlideLayoutType
  var elements: [SlideElement] = []
  var background: SlideBackground?

  init(id: String = UUID().uuidString, layoutType: SlideLayoutType = .blank) {
    self.id = id
    self.layoutType = layoutType
  }
}

// MARK: - Slide Elements

protocol SlideElement: AnyObject {
  var elementId: String { get }
  var elementType: String { get }
}

// MARK: - Position & Size

struct ElementPosition {
  var x: Double  // inches from left
  var y: Double  // inches from top
  var width: Double  // inches
  var height: Double  // inches

  var xEMU: Int { Units.inchesToEMU(x) }
  var yEMU: Int { Units.inchesToEMU(y) }
  var widthEMU: Int { Units.inchesToEMU(width) }
  var heightEMU: Int { Units.inchesToEMU(height) }
}

// MARK: - Text Element

final class TextElement: SlideElement, @unchecked Sendable {
  let elementId: String
  let elementType = "text"
  var position: ElementPosition
  var text: String
  var fontSize: Double  // points
  var fontFace: String
  var fontColor: String  // hex
  var bold: Bool
  var italic: Bool
  var underline: Bool
  var alignment: TextAlignment
  var verticalAlignment: VerticalAlignment
  var lineSpacing: Double?  // points
  var bullets: Bool
  var wordWrap: Bool
  var rotation: Double?  // degrees

  init(
    elementId: String = UUID().uuidString,
    text: String,
    position: ElementPosition,
    fontSize: Double = 18,
    fontFace: String = "Calibri",
    fontColor: String = "000000",
    bold: Bool = false,
    italic: Bool = false,
    underline: Bool = false,
    alignment: TextAlignment = .left,
    verticalAlignment: VerticalAlignment = .top,
    lineSpacing: Double? = nil,
    bullets: Bool = false,
    wordWrap: Bool = true,
    rotation: Double? = nil
  ) {
    self.elementId = elementId
    self.text = text
    self.position = position
    self.fontSize = fontSize
    self.fontFace = fontFace
    self.fontColor = fontColor
    self.bold = bold
    self.italic = italic
    self.underline = underline
    self.alignment = alignment
    self.verticalAlignment = verticalAlignment
    self.lineSpacing = lineSpacing
    self.bullets = bullets
    self.wordWrap = wordWrap
    self.rotation = rotation
  }
}

enum TextAlignment: String, Codable {
  case left = "l"
  case center = "ctr"
  case right = "r"
  case justify = "just"

  init(from string: String) {
    switch string.lowercased() {
    case "center", "ctr": self = .center
    case "right", "r": self = .right
    case "justify", "just": self = .justify
    default: self = .left
    }
  }
}

enum VerticalAlignment: String, Codable {
  case top = "t"
  case middle = "ctr"
  case bottom = "b"

  init(from string: String) {
    switch string.lowercased() {
    case "middle", "center", "ctr": self = .middle
    case "bottom", "b": self = .bottom
    default: self = .top
    }
  }
}

// MARK: - Image Element

final class ImageElement: SlideElement, @unchecked Sendable {
  let elementId: String
  let elementType = "image"
  var position: ElementPosition
  var sourcePath: String  // absolute path to image file
  var imageExtension: String  // e.g., "png", "jpg"
  var rId: String?  // relationship ID, set during writing

  init(
    elementId: String = UUID().uuidString,
    sourcePath: String,
    position: ElementPosition,
    imageExtension: String = "png"
  ) {
    self.elementId = elementId
    self.sourcePath = sourcePath
    self.position = position
    self.imageExtension = imageExtension
  }
}

// MARK: - Shape Element

final class ShapeElement: SlideElement, @unchecked Sendable {
  let elementId: String
  let elementType = "shape"
  var position: ElementPosition
  var shapeType: ShapeType
  var fillColor: String?  // hex
  var borderColor: String?  // hex
  var borderWidth: Double  // points
  var text: String?
  var textColor: String  // hex
  var textSize: Double  // points
  var rotation: Double?  // degrees

  init(
    elementId: String = UUID().uuidString,
    shapeType: ShapeType,
    position: ElementPosition,
    fillColor: String? = nil,
    borderColor: String? = nil,
    borderWidth: Double = 1.0,
    text: String? = nil,
    textColor: String = "000000",
    textSize: Double = 14,
    rotation: Double? = nil
  ) {
    self.elementId = elementId
    self.shapeType = shapeType
    self.position = position
    self.fillColor = fillColor
    self.borderColor = borderColor
    self.borderWidth = borderWidth
    self.text = text
    self.textColor = textColor
    self.textSize = textSize
    self.rotation = rotation
  }
}

enum ShapeType: String, Codable {
  case rect
  case roundRect = "round_rect"
  case ellipse
  case triangle
  case diamond
  case pentagon
  case hexagon
  case octagon
  case star4
  case star5
  case star6
  case rightArrow = "right_arrow"
  case leftArrow = "left_arrow"
  case upArrow = "up_arrow"
  case downArrow = "down_arrow"
  case heart
  case cloud
  case lightning
  case line
  case parallelogram
  case trapezoid

  var ooxmlPreset: String {
    switch self {
    case .rect: return "rect"
    case .roundRect: return "roundRect"
    case .ellipse: return "ellipse"
    case .triangle: return "triangle"
    case .diamond: return "diamond"
    case .pentagon: return "pentagon"
    case .hexagon: return "hexagon"
    case .octagon: return "octagon"
    case .star4: return "star4"
    case .star5: return "star5"
    case .star6: return "star6"
    case .rightArrow: return "rightArrow"
    case .leftArrow: return "leftArrow"
    case .upArrow: return "upArrow"
    case .downArrow: return "downArrow"
    case .heart: return "heart"
    case .cloud: return "cloud"
    case .lightning: return "lightningBolt"
    case .line: return "line"
    case .parallelogram: return "parallelogram"
    case .trapezoid: return "trapezoid"
    }
  }
}

// MARK: - Table Element

final class TableElement: SlideElement, @unchecked Sendable {
  let elementId: String
  let elementType = "table"
  var position: ElementPosition
  var rows: [[String]]  // 2D array of cell values
  var hasHeader: Bool
  var headerColor: String  // hex
  var headerTextColor: String  // hex
  var alternateRowColor: String?  // hex
  var borderColor: String  // hex
  var fontSize: Double  // points
  var fontFace: String
  var columnWidths: [Double]?  // inches, optional
  var mergedCells: [MergedCell]  // cell merges

  init(
    elementId: String = UUID().uuidString,
    rows: [[String]],
    position: ElementPosition,
    hasHeader: Bool = true,
    headerColor: String = "4472C4",
    headerTextColor: String = "FFFFFF",
    alternateRowColor: String? = "D9E2F3",
    borderColor: String = "8EAADB",
    fontSize: Double = 12,
    fontFace: String = "Calibri",
    columnWidths: [Double]? = nil,
    mergedCells: [MergedCell] = []
  ) {
    self.elementId = elementId
    self.rows = rows
    self.position = position
    self.hasHeader = hasHeader
    self.headerColor = headerColor
    self.headerTextColor = headerTextColor
    self.alternateRowColor = alternateRowColor
    self.borderColor = borderColor
    self.fontSize = fontSize
    self.fontFace = fontFace
    self.columnWidths = columnWidths
    self.mergedCells = mergedCells
  }
}

struct MergedCell: Codable {
  let row: Int
  let col: Int
  let rowSpan: Int
  let colSpan: Int
}

// MARK: - Chart Element

final class ChartElement: SlideElement, @unchecked Sendable {
  let elementId: String
  let elementType = "chart"
  var position: ElementPosition
  var chartType: ChartType
  var chartTitle: String?
  var series: [ChartSeries]
  var categories: [String]
  var showLegend: Bool
  var showDataLabels: Bool
  var rId: String?  // relationship ID, set during writing
  var chartIndex: Int = 0  // index for file naming

  init(
    elementId: String = UUID().uuidString,
    chartType: ChartType,
    position: ElementPosition,
    chartTitle: String? = nil,
    series: [ChartSeries],
    categories: [String],
    showLegend: Bool = true,
    showDataLabels: Bool = false
  ) {
    self.elementId = elementId
    self.chartType = chartType
    self.position = position
    self.chartTitle = chartTitle
    self.series = series
    self.categories = categories
    self.showLegend = showLegend
    self.showDataLabels = showDataLabels
  }
}

enum ChartType: String, Codable {
  case bar
  case column
  case line
  case pie
  case doughnut
}

struct ChartSeries: Codable {
  let name: String
  let values: [Double]
  let color: String?  // hex
}

// MARK: - Slide Background

struct SlideBackground {
  enum BackgroundType {
    case solid(color: String)
    case gradient(color1: String, color2: String, angle: Double)
  }
  let type: BackgroundType
}

// MARK: - Theme

struct Theme {
  let name: String
  let primaryColor: String  // hex
  let secondaryColor: String  // hex
  let accentColor1: String  // hex
  let accentColor2: String  // hex
  let accentColor3: String  // hex
  let accentColor4: String  // hex
  let backgroundColor: String  // hex
  let textColor: String  // hex
  let lightTextColor: String  // hex
  let fontHeading: String
  let fontBody: String
}

// MARK: - Theme Presets

enum ThemePresets {
  static let modern = Theme(
    name: "Modern",
    primaryColor: "4472C4",
    secondaryColor: "ED7D31",
    accentColor1: "A5A5A5",
    accentColor2: "FFC000",
    accentColor3: "5B9BD5",
    accentColor4: "70AD47",
    backgroundColor: "FFFFFF",
    textColor: "333333",
    lightTextColor: "FFFFFF",
    fontHeading: "Calibri Light",
    fontBody: "Calibri"
  )

  static let corporate = Theme(
    name: "Corporate",
    primaryColor: "1F3864",
    secondaryColor: "2E75B6",
    accentColor1: "BDD7EE",
    accentColor2: "9DC3E6",
    accentColor3: "2E75B6",
    accentColor4: "1F3864",
    backgroundColor: "FFFFFF",
    textColor: "1F3864",
    lightTextColor: "FFFFFF",
    fontHeading: "Georgia",
    fontBody: "Calibri"
  )

  static let creative = Theme(
    name: "Creative",
    primaryColor: "E91E63",
    secondaryColor: "9C27B0",
    accentColor1: "FF9800",
    accentColor2: "4CAF50",
    accentColor3: "2196F3",
    accentColor4: "607D8B",
    backgroundColor: "FFFFFF",
    textColor: "212121",
    lightTextColor: "FFFFFF",
    fontHeading: "Avenir Next",
    fontBody: "Avenir Next"
  )

  static let minimal = Theme(
    name: "Minimal",
    primaryColor: "333333",
    secondaryColor: "666666",
    accentColor1: "999999",
    accentColor2: "CCCCCC",
    accentColor3: "E0E0E0",
    accentColor4: "F5F5F5",
    backgroundColor: "FFFFFF",
    textColor: "333333",
    lightTextColor: "FFFFFF",
    fontHeading: "Helvetica Neue",
    fontBody: "Helvetica Neue"
  )

  static let dark = Theme(
    name: "Dark",
    primaryColor: "BB86FC",
    secondaryColor: "03DAC6",
    accentColor1: "CF6679",
    accentColor2: "FF7043",
    accentColor3: "FFD54F",
    accentColor4: "81C784",
    backgroundColor: "121212",
    textColor: "E0E0E0",
    lightTextColor: "FFFFFF",
    fontHeading: "SF Pro Display",
    fontBody: "SF Pro Text"
  )

  static func named(_ name: String) -> Theme {
    switch name.lowercased() {
    case "corporate": return corporate
    case "creative": return creative
    case "minimal": return minimal
    case "dark": return dark
    default: return modern
    }
  }
}
