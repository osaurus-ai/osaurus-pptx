import Foundation

// MARK: - OOXML Namespace Constants

enum OOXML {
  static let nsA = "http://schemas.openxmlformats.org/drawingml/2006/main"
  static let nsR = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  static let nsP = "http://schemas.openxmlformats.org/presentationml/2006/main"
  static let nsContentTypes = "http://schemas.openxmlformats.org/package/2006/content-types"
  static let nsRelationships = "http://schemas.openxmlformats.org/package/2006/relationships"
  static let nsCoreProps = "http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
  static let nsDC = "http://purl.org/dc/elements/1.1/"
  static let nsDCTerms = "http://purl.org/dc/terms/"
  static let nsXSI = "http://www.w3.org/2001/XMLSchema-instance"

  static let relTypeOfficeDoc =
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
  static let relTypeCoreProps =
    "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties"
  static let relTypeSlide =
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide"
  static let relTypeSlideMaster =
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster"
  static let relTypeSlideLayout =
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout"
  static let relTypeTheme =
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme"
  static let relTypeImage =
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image"
  static let relTypeChart =
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart"
  static let relTypeNotesSlide =
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide"
  static let relTypeNotesMaster =
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster"
  static let nsChart = "http://schemas.openxmlformats.org/drawingml/2006/chart"

  static let contentTypePresentationML =
    "application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"
  static let contentTypeSlide =
    "application/vnd.openxmlformats-officedocument.presentationml.slide+xml"
  static let contentTypeSlideMaster =
    "application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"
  static let contentTypeSlideLayout =
    "application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"
  static let contentTypeTheme = "application/vnd.openxmlformats-officedocument.theme+xml"
  static let contentTypeRels = "application/vnd.openxmlformats-package.relationships+xml"
  static let contentTypeCoreProps = "application/vnd.openxmlformats-package.core-properties+xml"
  static let contentTypeChart = "application/vnd.openxmlformats-officedocument.drawingml.chart+xml"
  static let contentTypeNotesSlide =
    "application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml"
  static let contentTypeNotesMaster =
    "application/vnd.openxmlformats-officedocument.presentationml.notesMaster+xml"
  static let contentTypeXML = "application/xml"
}

// MARK: - Unit Conversion

enum Units {
  static let emuPerInch: Int = 914400
  static let emuPerPoint: Int = 12700
  static func inchesToEMU(_ inches: Double) -> Int {
    Int(inches * Double(emuPerInch))
  }

  static func pointsToEMU(_ points: Double) -> Int {
    Int(points * Double(emuPerPoint))
  }

  static func pointsToHundredths(_ points: Double) -> Int {
    Int(points * 100)
  }
}

// MARK: - Default Slide Dimensions

enum SlideDimensions {
  static let wideWidth = 12_192_000  // 16:9 (exactly 13+1/3 inches)
  static let wideHeight = Units.inchesToEMU(7.5)
  static let standardWidth = Units.inchesToEMU(10.0)  // 4:3
  static let standardHeight = Units.inchesToEMU(7.5)
}

// MARK: - XML Escaping

func xmlEscape(_ s: String) -> String {
  s.replacingOccurrences(of: "&", with: "&amp;")
    .replacingOccurrences(of: "<", with: "&lt;")
    .replacingOccurrences(of: ">", with: "&gt;")
    .replacingOccurrences(of: "\"", with: "&quot;")
    .replacingOccurrences(of: "'", with: "&apos;")
}

// MARK: - JSON Escaping

func jsonEscape(_ s: String) -> String {
  s.replacingOccurrences(of: "\\", with: "\\\\")
    .replacingOccurrences(of: "\"", with: "\\\"")
    .replacingOccurrences(of: "\n", with: "\\n")
    .replacingOccurrences(of: "\r", with: "\\r")
    .replacingOccurrences(of: "\t", with: "\\t")
}

// MARK: - JSON Response Helpers

func jsonSuccess(_ fields: [String: Any]) -> String {
  var parts: [String] = []
  for (key, value) in fields {
    switch value {
    case let s as String:
      parts.append("\"\(jsonEscape(key))\": \"\(jsonEscape(s))\"")
    case let i as Int:
      parts.append("\"\(jsonEscape(key))\": \(i)")
    case let d as Double:
      parts.append("\"\(jsonEscape(key))\": \(d)")
    case let b as Bool:
      parts.append("\"\(jsonEscape(key))\": \(b ? "true" : "false")")
    case let arr as [String]:
      let items = arr.map { "\"\(jsonEscape($0))\"" }.joined(separator: ", ")
      parts.append("\"\(jsonEscape(key))\": [\(items)]")
    default:
      // For pre-formatted JSON strings (raw)
      if let raw = value as? JSONRaw {
        parts.append("\"\(jsonEscape(key))\": \(raw.value)")
      }
    }
  }
  return "{\(parts.joined(separator: ", "))}"
}

func jsonError(_ message: String) -> String {
  "{\"error\": \"\(jsonEscape(message))\"}"
}

/// Wrapper to pass pre-formatted JSON into jsonSuccess
struct JSONRaw {
  let value: String
  init(_ value: String) { self.value = value }
}

// MARK: - Color Helpers

/// Parse a hex color string (with or without #) and return 6-char hex
func parseHexColor(_ color: String) -> String {
  let cleaned = color.hasPrefix("#") ? String(color.dropFirst()) : color
  if cleaned.count == 6 {
    return cleaned.uppercased()
  }
  if cleaned.count == 3 {
    return cleaned.map { "\($0)\($0)" }.joined().uppercased()
  }
  return "000000"
}

/// Convert hex color to OOXML srgbClr element
func srgbClrXML(_ hex: String, alpha: Double? = nil) -> String {
  let color = parseHexColor(hex)
  if let alpha = alpha, alpha < 1.0 {
    let alphaVal = Int(alpha * 100000)
    return "<a:srgbClr val=\"\(color)\"><a:alpha val=\"\(alphaVal)\"/></a:srgbClr>"
  }
  return "<a:srgbClr val=\"\(color)\"/>"
}

// MARK: - Process Runner

func runProcess(_ executable: String, arguments: [String], currentDirectory: String? = nil) throws
  -> (output: String, exitCode: Int32)
{
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  if let dir = currentDirectory {
    process.currentDirectoryURL = URL(fileURLWithPath: dir)
  }

  let pipe = Pipe()
  process.standardOutput = pipe
  process.standardError = pipe

  try process.run()
  process.waitUntilExit()

  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  let output = String(data: data, encoding: .utf8) ?? ""
  return (output, process.terminationStatus)
}

// MARK: - File Manager Helpers

func createDirectoryIfNeeded(_ path: String) throws {
  try FileManager.default.createDirectory(
    atPath: path,
    withIntermediateDirectories: true,
    attributes: nil
  )
}

func writeFile(_ content: String, to path: String) throws {
  try content.write(toFile: path, atomically: true, encoding: .utf8)
}

func writeData(_ data: Data, to path: String) throws {
  try data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

// MARK: - Image Content Type

func imageContentType(for ext: String) -> String {
  switch ext.lowercased() {
  case "png": return "image/png"
  case "jpg", "jpeg": return "image/jpeg"
  case "gif": return "image/gif"
  case "bmp": return "image/bmp"
  case "tiff", "tif": return "image/tiff"
  case "svg": return "image/svg+xml"
  default: return "image/png"
  }
}
