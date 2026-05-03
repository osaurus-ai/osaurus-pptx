import Foundation

struct ConverterResult {
  let status: String
  let inputPath: String
  let outputPath: String?
  let executablePath: String?
  let message: String
}

enum ConverterHelper {
  static let candidatePaths = [
    "/Applications/LibreOffice.app/Contents/MacOS/soffice",
    "/usr/local/bin/soffice",
    "/opt/homebrew/bin/soffice",
  ]

  static func detectSoffice() -> String? {
    candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
  }

  static func convertPresentation(
    inputPath: String,
    outputPath: String,
    format: String,
    filter: String? = nil
  ) throws -> ConverterResult {
    guard let soffice = detectSoffice() else {
      return ConverterResult(
        status: "converter_unavailable",
        inputPath: inputPath,
        outputPath: nil,
        executablePath: nil,
        message:
          "LibreOffice was not found. Install LibreOffice or add soffice at /Applications/LibreOffice.app/Contents/MacOS/soffice, /usr/local/bin/soffice, or /opt/homebrew/bin/soffice.")
    }

    let tempDir = NSTemporaryDirectory() + "osaurus_pptx_convert_\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: tempDir) }
    try createDirectoryIfNeeded(tempDir)

    let convertTo = filter.map { "\(format):\($0)" } ?? format
    let result = try runProcess(
      soffice,
      arguments: [
        "--headless",
        "--convert-to",
        convertTo,
        "--outdir",
        tempDir,
        inputPath,
      ])

    guard result.exitCode == 0 else {
      return ConverterResult(
        status: "conversion_failed",
        inputPath: inputPath,
        outputPath: nil,
        executablePath: soffice,
        message: result.output.isEmpty ? "LibreOffice conversion failed" : result.output)
    }

    let generatedName =
      ((inputPath as NSString).lastPathComponent as NSString).deletingPathExtension + ".\(format)"
    let generatedPath = "\(tempDir)/\(generatedName)"
    guard FileManager.default.fileExists(atPath: generatedPath) else {
      return ConverterResult(
        status: "conversion_failed",
        inputPath: inputPath,
        outputPath: nil,
        executablePath: soffice,
        message: "LibreOffice did not produce expected output: \(generatedName)")
    }

    let outputDir = (outputPath as NSString).deletingLastPathComponent
    try createDirectoryIfNeeded(outputDir)
    if FileManager.default.fileExists(atPath: outputPath) {
      try FileManager.default.removeItem(atPath: outputPath)
    }
    try FileManager.default.moveItem(atPath: generatedPath, toPath: outputPath)

    return ConverterResult(
      status: "ok",
      inputPath: inputPath,
      outputPath: outputPath,
      executablePath: soffice,
      message: "Converted presentation to \(format)")
  }
}
