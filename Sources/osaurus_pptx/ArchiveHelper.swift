import Foundation

enum ArchiveHelper {
  static func validateZipEntries(_ filePath: String) throws -> [String] {
    let result = try runProcess("/usr/bin/unzip", arguments: ["-Z1", filePath])
    guard result.exitCode == 0 else {
      throw PPTXError.unzipFailed(result.output)
    }

    let entries = result.output.split(whereSeparator: \.isNewline).map(String.init)
    for entry in entries {
      guard isSafeZipEntry(entry) else {
        throw PPTXError.invalidFile("Unsafe ZIP entry blocked: \(entry)")
      }
    }
    return entries
  }

  static func extractZipSafely(_ filePath: String, to destination: String) throws {
    _ = try validateZipEntries(filePath)
    try createDirectoryIfNeeded(destination)

    let result = try runProcess(
      "/usr/bin/unzip",
      arguments: ["-q", "-o", filePath, "-d", destination])
    guard result.exitCode == 0 else {
      throw PPTXError.unzipFailed(result.output)
    }
  }

  static func zipDirectory(_ directory: String, to outputPath: String) throws {
    if FileManager.default.fileExists(atPath: outputPath) {
      try FileManager.default.removeItem(atPath: outputPath)
    }

    let result = try runProcess(
      "/usr/bin/zip",
      arguments: ["-r", "-q", outputPath, "."],
      currentDirectory: directory)
    guard result.exitCode == 0 else {
      throw PPTXError.zipFailed(result.output)
    }
  }

  static func isSafeZipEntry(_ entry: String) -> Bool {
    guard !entry.isEmpty else { return false }
    guard !entry.hasPrefix("/") && !entry.hasPrefix("\\") && !entry.hasPrefix("~") else {
      return false
    }
    guard !entry.contains("\\") && !entry.contains("\0") else { return false }

    let components = entry.split(separator: "/", omittingEmptySubsequences: false)
    return !components.contains("..")
  }
}
