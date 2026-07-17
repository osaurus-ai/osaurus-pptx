import Foundation

// MARK: - Zip Archive Safety

/// Errors raised while validating an untrusted zip archive before extraction.
enum ZipArchiveError: Error, CustomStringConvertible {
  case unreadable(String)
  case notAZipArchive
  case tooManyEntries(count: Int, limit: Int)
  case totalSizeTooLarge(bytes: UInt64, limit: UInt64)
  case compressionRatioTooHigh(ratio: UInt64, limit: UInt64)
  case unsafeEntryPath(String)
  case symlinkEntry(String)

  var description: String {
    switch self {
    case .unreadable(let path):
      return "Cannot open archive for validation: \(path)"
    case .notAZipArchive:
      return "File is not a valid zip archive"
    case .tooManyEntries(let count, let limit):
      return "Archive has too many entries (\(count) > \(limit))"
    case .totalSizeTooLarge(let bytes, let limit):
      return "Archive uncompressed size \(bytes) bytes exceeds limit of \(limit) bytes"
    case .compressionRatioTooHigh(let ratio, let limit):
      return "Archive compression ratio \(ratio):1 exceeds limit of \(limit):1 (possible zip bomb)"
    case .unsafeEntryPath(let name):
      return "Archive entry path escapes extraction root: \(name)"
    case .symlinkEntry(let name):
      return "Archive contains a symlink entry: \(name)"
    }
  }
}

/// Metadata for a single archive entry, read from the central directory.
struct ZipEntry {
  let name: String
  let compressedSize: UInt64
  let uncompressedSize: UInt64
  let isSymlink: Bool
}

/// Validates untrusted zip archives (entry count, uncompressed size,
/// compression ratio, entry path containment, symlinks) by reading the
/// central directory, before any extraction happens.
enum ZipArchiveGuard {
  static let maxEntries = 10_000
  static let maxTotalUncompressedBytes: UInt64 = 512 * 1024 * 1024
  static let maxCompressionRatio: UInt64 = 100
  /// Ratio is only enforced above this uncompressed size so tiny archives
  /// with highly compressible XML are not rejected.
  static let ratioEnforcementThresholdBytes: UInt64 = 1024 * 1024

  @discardableResult
  static func validate(archiveAt path: String) throws -> [ZipEntry] {
    let entries = try readCentralDirectory(at: path)

    if entries.count > maxEntries {
      throw ZipArchiveError.tooManyEntries(count: entries.count, limit: maxEntries)
    }

    var totalCompressed: UInt64 = 0
    var totalUncompressed: UInt64 = 0
    for entry in entries {
      if entry.isSymlink {
        throw ZipArchiveError.symlinkEntry(entry.name)
      }
      if !isEntryPathSafe(entry.name) {
        throw ZipArchiveError.unsafeEntryPath(entry.name)
      }
      totalCompressed &+= entry.compressedSize
      totalUncompressed &+= entry.uncompressedSize
    }

    if totalUncompressed > maxTotalUncompressedBytes {
      throw ZipArchiveError.totalSizeTooLarge(
        bytes: totalUncompressed, limit: maxTotalUncompressedBytes)
    }
    if totalUncompressed > ratioEnforcementThresholdBytes {
      let ratio = totalUncompressed / max(totalCompressed, 1)
      if ratio > maxCompressionRatio {
        throw ZipArchiveError.compressionRatioTooHigh(ratio: ratio, limit: maxCompressionRatio)
      }
    }

    return entries
  }

  /// An entry path is safe when it is relative and cannot climb out of the
  /// extraction root.
  static func isEntryPathSafe(_ name: String) -> Bool {
    if name.isEmpty { return false }
    if name.contains("\0") { return false }
    if name.hasPrefix("/") || name.hasPrefix("\\") { return false }
    let components = name.split(whereSeparator: { $0 == "/" || $0 == "\\" })
    if components.contains("..") { return false }
    // Windows drive-letter prefixes such as "C:"
    if let first = components.first, first.count >= 2, first.dropFirst().first == ":" {
      return false
    }
    return true
  }

  // MARK: - Central Directory Parsing

  private static func readCentralDirectory(at path: String) throws -> [ZipEntry] {
    guard let handle = FileHandle(forReadingAtPath: path) else {
      throw ZipArchiveError.unreadable(path)
    }
    defer { try? handle.close() }

    guard let fileSize = try? handle.seekToEnd(), fileSize >= 22 else {
      throw ZipArchiveError.notAZipArchive
    }

    // End-of-central-directory record: fixed 22 bytes plus up to 64 KB comment.
    let tailLength = min(fileSize, 22 + 65_535)
    try handle.seek(toOffset: fileSize - tailLength)
    guard let tail = try handle.read(upToCount: Int(tailLength)), tail.count == Int(tailLength)
    else {
      throw ZipArchiveError.notAZipArchive
    }

    var eocdIndex = -1
    var i = tail.count - 22
    while i >= 0 {
      if tail[i] == 0x50, tail[i + 1] == 0x4B, tail[i + 2] == 0x05, tail[i + 3] == 0x06 {
        eocdIndex = i
        break
      }
      i -= 1
    }
    guard eocdIndex >= 0 else { throw ZipArchiveError.notAZipArchive }

    let entryCount = Int(readUInt16(tail, eocdIndex + 10))
    let cdSize = readUInt32(tail, eocdIndex + 12)
    let cdOffset = readUInt32(tail, eocdIndex + 16)

    // ZIP64 markers imply counts/sizes far beyond the enforced limits.
    if entryCount == 0xFFFF {
      throw ZipArchiveError.tooManyEntries(count: entryCount, limit: maxEntries)
    }
    if cdSize == 0xFFFF_FFFF || cdOffset == 0xFFFF_FFFF {
      throw ZipArchiveError.totalSizeTooLarge(
        bytes: UInt64.max, limit: maxTotalUncompressedBytes)
    }
    if entryCount > maxEntries {
      throw ZipArchiveError.tooManyEntries(count: entryCount, limit: maxEntries)
    }
    guard UInt64(cdOffset) + UInt64(cdSize) <= fileSize else {
      throw ZipArchiveError.notAZipArchive
    }

    try handle.seek(toOffset: UInt64(cdOffset))
    guard let cd = try handle.read(upToCount: Int(cdSize)), cd.count == Int(cdSize) else {
      throw ZipArchiveError.notAZipArchive
    }

    var entries: [ZipEntry] = []
    var pos = 0
    while pos + 46 <= cd.count {
      guard readUInt32(cd, pos) == 0x0201_4B50 else { break }
      let versionMadeBy = readUInt16(cd, pos + 4)
      let compressedSize = readUInt32(cd, pos + 20)
      let uncompressedSize = readUInt32(cd, pos + 24)
      let nameLength = Int(readUInt16(cd, pos + 28))
      let extraLength = Int(readUInt16(cd, pos + 30))
      let commentLength = Int(readUInt16(cd, pos + 32))
      let externalAttributes = readUInt32(cd, pos + 38)

      guard pos + 46 + nameLength <= cd.count else { throw ZipArchiveError.notAZipArchive }
      let nameData = cd.subdata(in: (pos + 46)..<(pos + 46 + nameLength))
      let name = String(decoding: nameData, as: UTF8.self)

      if compressedSize == 0xFFFF_FFFF || uncompressedSize == 0xFFFF_FFFF {
        throw ZipArchiveError.totalSizeTooLarge(
          bytes: UInt64.max, limit: maxTotalUncompressedBytes)
      }

      let hostOS = (versionMadeBy >> 8) & 0xFF
      let unixMode = (externalAttributes >> 16) & 0xFFFF
      let isSymlink = hostOS == 3 && (unixMode & 0xF000) == 0xA000

      entries.append(
        ZipEntry(
          name: name,
          compressedSize: UInt64(compressedSize),
          uncompressedSize: UInt64(uncompressedSize),
          isSymlink: isSymlink
        ))
      if entries.count > maxEntries {
        throw ZipArchiveError.tooManyEntries(count: entries.count, limit: maxEntries)
      }

      pos += 46 + nameLength + extraLength + commentLength
    }

    if entries.isEmpty && entryCount > 0 {
      throw ZipArchiveError.notAZipArchive
    }

    return entries
  }

  private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
    UInt16(data[data.startIndex + offset])
      | (UInt16(data[data.startIndex + offset + 1]) << 8)
  }

  private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
    UInt32(data[data.startIndex + offset])
      | (UInt32(data[data.startIndex + offset + 1]) << 8)
      | (UInt32(data[data.startIndex + offset + 2]) << 16)
      | (UInt32(data[data.startIndex + offset + 3]) << 24)
  }
}
