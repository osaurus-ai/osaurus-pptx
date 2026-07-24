import Foundation
import Testing

@testable import osaurus_pptx

// MARK: - Zip Fixture Builder

/// Builds zip archives byte-by-byte (central directory + EOCD) so tests can
/// craft malicious metadata that real zip tools refuse to produce.
enum ZipFixture {
  struct Entry {
    var name: String
    var compressedSize: UInt32 = 100
    var uncompressedSize: UInt32 = 100
    // Unix regular file 0644 in the upper 16 bits.
    var externalAttributes: UInt32 = 0x81A4 << 16
    // Upper byte 3 = Unix host.
    var versionMadeBy: UInt16 = 0x031E
  }

  static func make(entries: [Entry]) -> Data {
    var cd = Data()
    for entry in entries {
      append32(&cd, 0x0201_4B50)
      append16(&cd, entry.versionMadeBy)
      append16(&cd, 20)  // version needed
      append16(&cd, 0)  // flags
      append16(&cd, 0)  // method
      append16(&cd, 0)  // mod time
      append16(&cd, 0)  // mod date
      append32(&cd, 0)  // crc32
      append32(&cd, entry.compressedSize)
      append32(&cd, entry.uncompressedSize)
      let nameBytes = Array(entry.name.utf8)
      append16(&cd, UInt16(nameBytes.count))
      append16(&cd, 0)  // extra length
      append16(&cd, 0)  // comment length
      append16(&cd, 0)  // disk number
      append16(&cd, 0)  // internal attributes
      append32(&cd, entry.externalAttributes)
      append32(&cd, 0)  // local header offset
      cd.append(contentsOf: nameBytes)
    }

    var out = cd
    append32(&out, 0x0605_4B50)
    append16(&out, 0)  // disk number
    append16(&out, 0)  // cd start disk
    let count = UInt16(min(entries.count, 0xFFFF))
    append16(&out, count)
    append16(&out, count)
    append32(&out, UInt32(cd.count))
    append32(&out, 0)  // cd offset (cd is at file start)
    append16(&out, 0)  // comment length
    return out
  }

  static func write(entries: [Entry], suffix: String) throws -> String {
    let path = NSTemporaryDirectory() + "zip_fixture_\(suffix)_\(UUID().uuidString).pptx"
    try make(entries: entries).write(to: URL(fileURLWithPath: path))
    return path
  }

  private static func append16(_ data: inout Data, _ value: UInt16) {
    data.append(UInt8(value & 0xFF))
    data.append(UInt8((value >> 8) & 0xFF))
  }

  private static func append32(_ data: inout Data, _ value: UInt32) {
    data.append(UInt8(value & 0xFF))
    data.append(UInt8((value >> 8) & 0xFF))
    data.append(UInt8((value >> 16) & 0xFF))
    data.append(UInt8((value >> 24) & 0xFF))
  }
}

// MARK: - Shell helpers for tamper tests

private func runZipTool(_ executable: String, _ arguments: [String], cwd: String? = nil) throws {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  if let cwd = cwd {
    process.currentDirectoryURL = URL(fileURLWithPath: cwd)
  }
  process.standardOutput = Pipe()
  process.standardError = Pipe()
  try process.run()
  process.waitUntilExit()
}

// MARK: - Archive Safety

@Suite("Archive Safety")
struct ArchiveSafetyTests {

  @Test("Path traversal entry is rejected before extraction")
  func traversalEntryRejected() throws {
    let path = try ZipFixture.write(
      entries: [
        ZipFixture.Entry(name: "ppt/presentation.xml"),
        ZipFixture.Entry(name: "../../../../tmp/evil.xml"),
      ], suffix: "traversal")
    defer { try? FileManager.default.removeItem(atPath: path) }

    do {
      _ = try PPTXReader.read(from: path)
      Issue.record("Expected traversal archive to be rejected")
    } catch {
      #expect("\(error)".contains("escapes extraction root"))
    }
  }

  @Test("Absolute entry path is rejected")
  func absoluteEntryRejected() throws {
    let path = try ZipFixture.write(
      entries: [ZipFixture.Entry(name: "/etc/evil.xml")], suffix: "absolute")
    defer { try? FileManager.default.removeItem(atPath: path) }

    do {
      _ = try PPTXReader.read(from: path)
      Issue.record("Expected absolute-path archive to be rejected")
    } catch {
      #expect("\(error)".contains("escapes extraction root"))
    }
  }

  @Test("High-ratio zip bomb with modest compressed size is rejected")
  func zipBombRejected() throws {
    // 4 entries, each claiming 100 MB uncompressed from 256 KB compressed:
    // ratio 400:1 at a modest ~1 MB archive size.
    let entries = (1...4).map { i in
      ZipFixture.Entry(
        name: "ppt/media/image\(i).png",
        compressedSize: 256 * 1024,
        uncompressedSize: 100 * 1024 * 1024)
    }
    let path = try ZipFixture.write(entries: entries, suffix: "bomb")
    defer { try? FileManager.default.removeItem(atPath: path) }

    do {
      _ = try PPTXReader.read(from: path)
      Issue.record("Expected zip bomb to be rejected")
    } catch {
      #expect("\(error)".contains("compression ratio"))
    }
  }

  @Test("Total uncompressed size above limit is rejected")
  func totalSizeRejected() throws {
    let entries = (1...80).map { i in
      ZipFixture.Entry(
        name: "ppt/media/big\(i).bin",
        compressedSize: 90 * 1024 * 1024,
        uncompressedSize: 100 * 1024 * 1024)
    }
    let path = try ZipFixture.write(entries: entries, suffix: "toobig")
    defer { try? FileManager.default.removeItem(atPath: path) }

    do {
      _ = try PPTXReader.read(from: path)
      Issue.record("Expected oversized archive to be rejected")
    } catch {
      #expect("\(error)".contains("exceeds limit"))
    }
  }

  @Test("Huge entry count is rejected")
  func hugeEntryCountRejected() throws {
    let entries = (1...10_001).map { i in
      ZipFixture.Entry(name: "e\(i)", compressedSize: 1, uncompressedSize: 1)
    }
    let path = try ZipFixture.write(entries: entries, suffix: "manyentries")
    defer { try? FileManager.default.removeItem(atPath: path) }

    do {
      _ = try PPTXReader.read(from: path)
      Issue.record("Expected archive with too many entries to be rejected")
    } catch {
      #expect("\(error)".contains("too many entries"))
    }
  }

  @Test("Symlink entry is rejected")
  func symlinkEntryRejected() throws {
    let path = try ZipFixture.write(
      entries: [
        ZipFixture.Entry(name: "ppt/link", externalAttributes: 0xA1FF << 16)
      ], suffix: "symlink")
    defer { try? FileManager.default.removeItem(atPath: path) }

    do {
      _ = try PPTXReader.read(from: path)
      Issue.record("Expected symlink archive to be rejected")
    } catch {
      #expect("\(error)".contains("symlink"))
    }
  }

  @Test("Non-zip file is rejected as invalid archive")
  func garbageRejected() throws {
    let path = NSTemporaryDirectory() + "not_a_zip_\(UUID().uuidString).pptx"
    try Data("this is not a zip".utf8).write(to: URL(fileURLWithPath: path))
    defer { try? FileManager.default.removeItem(atPath: path) }

    #expect(throws: (any Error).self) {
      _ = try PPTXReader.read(from: path)
    }
  }

  @Test("Valid archive produced by the writer still validates")
  func validArchivePasses() throws {
    let pres = Presentation(title: "Valid")
    pres.slides.append(Slide())
    let path = NSTemporaryDirectory() + "valid_\(UUID().uuidString).pptx"
    defer { try? FileManager.default.removeItem(atPath: path) }
    try PPTXWriter.write(presentation: pres, to: path)

    let entries = try ZipArchiveGuard.validate(archiveAt: path)
    #expect(!entries.isEmpty)
    let read = try PPTXReader.read(from: path)
    #expect(read.title == "Valid")
  }
}

// MARK: - Relationship Target Containment

@Suite("Relationship Target Containment")
struct RelationshipTargetTests {

  @Test("Relative and package-absolute targets resolve inside the root")
  func safeTargetsResolve() throws {
    let root = NSTemporaryDirectory() + "pkg_\(UUID().uuidString)"
    try FileManager.default.createDirectory(
      atPath: root + "/ppt/slides", withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: root) }

    let relative = try PPTXReader.resolveRelationshipTarget(
      "slides/slide1.xml", baseDir: "\(root)/ppt", packageRoot: root)
    #expect(relative.hasSuffix("/ppt/slides/slide1.xml"))

    let absolute = try PPTXReader.resolveRelationshipTarget(
      "/ppt/slides/slide1.xml", baseDir: "\(root)/ppt", packageRoot: root)
    #expect(absolute.hasSuffix("/ppt/slides/slide1.xml"))
  }

  @Test("Escaping targets are rejected")
  func escapingTargetsRejected() throws {
    let root = NSTemporaryDirectory() + "pkg_\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: root) }

    for target in ["../../../../etc/hosts", "/../outside.xml", "slides/../../../../etc/hosts"] {
      do {
        _ = try PPTXReader.resolveRelationshipTarget(
          target, baseDir: "\(root)/ppt", packageRoot: root)
        Issue.record("Expected target to be rejected: \(target)")
      } catch {
        #expect("\(error)".contains("escapes package"))
      }
    }
  }

  @Test("Tampered rels file with escaping slide target fails the read")
  func tamperedRelsRejected() throws {
    // Build a valid deck, then rewrite its presentation rels so the slide
    // target points outside the package.
    let pres = Presentation(title: "Tamper")
    pres.slides.append(Slide())
    let originalPath = NSTemporaryDirectory() + "tamper_src_\(UUID().uuidString).pptx"
    let workDir = NSTemporaryDirectory() + "tamper_work_\(UUID().uuidString)"
    let tamperedPath = NSTemporaryDirectory() + "tampered_\(UUID().uuidString).pptx"
    defer {
      try? FileManager.default.removeItem(atPath: originalPath)
      try? FileManager.default.removeItem(atPath: workDir)
      try? FileManager.default.removeItem(atPath: tamperedPath)
    }
    try PPTXWriter.write(presentation: pres, to: originalPath)

    try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
    try runZipTool("/usr/bin/unzip", ["-q", "-o", originalPath, "-d", workDir])

    let relsPath = "\(workDir)/ppt/_rels/presentation.xml.rels"
    var rels = try String(contentsOfFile: relsPath, encoding: .utf8)
    rels = rels.replacingOccurrences(
      of: "slides/slide1.xml", with: "../../../../../../etc/hosts")
    try rels.write(toFile: relsPath, atomically: true, encoding: .utf8)
    try runZipTool("/usr/bin/zip", ["-r", "-q", tamperedPath, "."], cwd: workDir)

    do {
      _ = try PPTXReader.read(from: tamperedPath)
      Issue.record("Expected tampered rels to be rejected")
    } catch {
      #expect("\(error)".contains("escapes package"))
    }
  }
}

// MARK: - Canonical Path Containment

@Suite("Canonical Path Containment")
struct CanonicalPathTests {

  @Test("Symlink inside the working directory cannot escape it")
  func symlinkEscapeBlocked() throws {
    let base = NSTemporaryDirectory() + "canon_\(UUID().uuidString)"
    let workDir = base + "/proj"
    let outside = base + "/outside"
    try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(atPath: outside, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      atPath: workDir + "/link", withDestinationPath: outside)
    defer { try? FileManager.default.removeItem(atPath: base) }

    let result = validatePath("link/escape.pptx", workingDirectory: workDir)
    if case .failure(let msg) = result {
      #expect(msg.contains("outside"))
    } else {
      Issue.record("Symlinked path escaping the working directory must be rejected")
    }
  }

  @Test("Sibling directory sharing the working-directory prefix is rejected")
  func siblingPrefixBlocked() {
    let result = validatePath(
      "/Users/test/project-evil/file.pptx", workingDirectory: "/Users/test/project")
    if case .failure(let msg) = result {
      #expect(msg.contains("outside"))
    } else {
      Issue.record("Sibling prefix path must be rejected")
    }
  }
}

// MARK: - Atomic Write

@Suite("Atomic Write")
struct AtomicWriteTests {

  private func presentationWithSlide(title: String) -> Presentation {
    let pres = Presentation(title: title)
    pres.slides.append(Slide())
    return pres
  }

  @Test("Writing to a path that is an existing directory fails and preserves it")
  func destinationDirectoryPreserved() throws {
    let dir = NSTemporaryDirectory() + "precious_dir_\(UUID().uuidString)"
    let innerFile = dir + "/precious.txt"
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try "do not lose me".write(toFile: innerFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: dir) }

    #expect(throws: (any Error).self) {
      try PPTXWriter.write(presentation: presentationWithSlide(title: "X"), to: dir)
    }

    var isDir: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: dir, isDirectory: &isDir))
    #expect(isDir.boolValue)
    #expect(try String(contentsOfFile: innerFile, encoding: .utf8) == "do not lose me")
  }

  @Test("A failing write leaves the prior file untouched")
  func failedWritePreservesPriorFile() throws {
    let path = NSTemporaryDirectory() + "atomic_\(UUID().uuidString).pptx"
    defer { try? FileManager.default.removeItem(atPath: path) }
    let priorBytes = Data("prior pptx bytes".utf8)
    try priorBytes.write(to: URL(fileURLWithPath: path))

    // A chart with a non-finite value makes the writer fail before packaging.
    let pres = presentationWithSlide(title: "Broken")
    let chart = ChartElement(
      chartType: .bar,
      position: ElementPosition(x: 1, y: 1, width: 8, height: 5),
      series: [ChartSeries(name: "S", values: [1, Double.nan, 3], color: nil)],
      categories: ["A", "B", "C"]
    )
    pres.slides[0].elements.append(chart)

    do {
      try PPTXWriter.write(presentation: pres, to: path)
      Issue.record("Expected write with non-finite chart value to fail")
    } catch {
      #expect("\(error)".contains("Invalid value"))
    }

    #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == priorBytes)
  }

  @Test("A successful write atomically replaces the prior file")
  func successfulWriteReplaces() throws {
    let path = NSTemporaryDirectory() + "atomic_ok_\(UUID().uuidString).pptx"
    defer { try? FileManager.default.removeItem(atPath: path) }

    try PPTXWriter.write(presentation: presentationWithSlide(title: "First"), to: path)
    try PPTXWriter.write(presentation: presentationWithSlide(title: "Second"), to: path)

    let read = try PPTXReader.read(from: path)
    #expect(read.title == "Second")
  }
}

// MARK: - Skipped Images

@Suite("Skipped Images")
struct SkippedImageTests {

  @Test("Missing image source is dropped and reported, no dangling relationship")
  func missingImageReported() throws {
    let missingPath = "/nonexistent/\(UUID().uuidString)/image.png"
    let pres = Presentation(title: "Images")
    let slide = Slide()
    slide.elements.append(
      ImageElement(
        sourcePath: missingPath,
        position: ElementPosition(x: 1, y: 1, width: 4, height: 3),
        imageExtension: "png"
      ))
    pres.slides.append(slide)

    let path = NSTemporaryDirectory() + "skipimg_\(UUID().uuidString).pptx"
    let workDir = NSTemporaryDirectory() + "skipimg_work_\(UUID().uuidString)"
    defer {
      try? FileManager.default.removeItem(atPath: path)
      try? FileManager.default.removeItem(atPath: workDir)
    }

    let result = try PPTXWriter.write(presentation: pres, to: path)
    #expect(result.skippedImages == [missingPath])

    // The written package must not carry a dangling image relationship.
    try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
    try runZipTool("/usr/bin/unzip", ["-q", "-o", path, "-d", workDir])
    let rels = try String(
      contentsOfFile: "\(workDir)/ppt/slides/_rels/slide1.xml.rels", encoding: .utf8)
    #expect(!rels.contains("media/"))
    let slideXML = try String(
      contentsOfFile: "\(workDir)/ppt/slides/slide1.xml", encoding: .utf8)
    #expect(!slideXML.contains("<p:pic>"))
  }

  @Test("save_presentation reports skipped images in the tool result")
  func saveToolReportsSkipped() throws {
    var presentations: [String: Presentation] = [:]

    // Create the deck and register an image whose file disappears before save.
    let imagePath = NSTemporaryDirectory() + "vanishing_\(UUID().uuidString).png"
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: URL(fileURLWithPath: imagePath))

    let createResult = CreatePresentationTool().run(
      args: "{\"title\": \"Deck\"}", presentations: &presentations)
    let presId = presentations.keys.first!
    #expect(createResult.contains("presentation_id"))
    _ = AddSlideTool().run(
      args: "{\"presentation_id\": \"\(presId)\"}", presentations: &presentations)
    let addResult = AddImageTool().run(
      args: "{\"presentation_id\": \"\(presId)\", \"slide_number\": 1, \"path\": \"\(imagePath)\"}",
      presentations: &presentations)
    #expect(addResult.contains("\"element_type\": \"image\""))

    try FileManager.default.removeItem(atPath: imagePath)

    let savePath = NSTemporaryDirectory() + "skiptool_\(UUID().uuidString).pptx"
    defer { try? FileManager.default.removeItem(atPath: savePath) }
    let saveResult = SavePresentationTool().run(
      args: "{\"presentation_id\": \"\(presId)\", \"path\": \"\(savePath)\"}",
      presentations: &presentations)

    #expect(saveResult.contains("skipped_images"))
    #expect(saveResult.contains(jsonEscape(imagePath)))
  }
}

// MARK: - Numeric Input Validation

@Suite("Numeric Input Validation")
struct NumericValidationTests {

  private func setup(_ presentations: inout [String: Presentation]) -> String {
    _ = CreatePresentationTool().run(args: "{\"title\": \"T\"}", presentations: &presentations)
    let presId = presentations.keys.first!
    _ = AddSlideTool().run(
      args: "{\"presentation_id\": \"\(presId)\"}", presentations: &presentations)
    return presId
  }

  @Test("add_text rejects huge coordinates that would trap in EMU conversion")
  func addTextHugeCoordinate() {
    var presentations: [String: Presentation] = [:]
    let presId = setup(&presentations)
    let result = AddTextTool().run(
      args: "{\"presentation_id\": \"\(presId)\", \"slide_number\": 1, \"text\": \"t\", \"x\": 1e300}",
      presentations: &presentations)
    #expect(result.contains("\"kind\":\"invalid_args\""))
  }

  @Test("add_text rejects zero/negative font size")
  func addTextBadFontSize() {
    var presentations: [String: Presentation] = [:]
    let presId = setup(&presentations)
    let result = AddTextTool().run(
      args:
        "{\"presentation_id\": \"\(presId)\", \"slide_number\": 1, \"text\": \"t\", \"font_size\": 0}",
      presentations: &presentations)
    #expect(result.contains("\"kind\":\"invalid_args\""))
  }

  @Test("add_chart rejects out-of-range series values")
  func addChartHugeValue() {
    var presentations: [String: Presentation] = [:]
    let presId = setup(&presentations)
    let result = AddChartTool().run(
      args: """
        {"presentation_id": "\(presId)", "slide_number": 1, "chart_type": "bar",
         "categories": ["A"], "series": [{"name": "S", "values": [1e300]}]}
        """,
      presentations: &presentations)
    #expect(result.contains("\"kind\":\"invalid_args\""))
  }

  @Test("create_presentation rejects unknown size and theme")
  func createPresentationBadEnums() {
    var presentations: [String: Presentation] = [:]
    let badSize = CreatePresentationTool().run(
      args: "{\"title\": \"T\", \"size\": \"bogus\"}", presentations: &presentations)
    #expect(badSize.contains("\"kind\":\"invalid_args\""))

    let badTheme = CreatePresentationTool().run(
      args: "{\"title\": \"T\", \"theme\": \"bogus\"}", presentations: &presentations)
    #expect(badTheme.contains("\"kind\":\"invalid_args\""))
  }

  @Test("add_slide rejects unknown layout")
  func addSlideBadLayout() {
    var presentations: [String: Presentation] = [:]
    _ = CreatePresentationTool().run(args: "{\"title\": \"T\"}", presentations: &presentations)
    let presId = presentations.keys.first!
    let result = AddSlideTool().run(
      args: "{\"presentation_id\": \"\(presId)\", \"layout\": \"bogus\"}",
      presentations: &presentations)
    #expect(result.contains("\"kind\":\"invalid_args\""))
  }

  @Test("set_slide_background rejects non-sane gradient angle")
  func backgroundBadAngle() {
    var presentations: [String: Presentation] = [:]
    let presId = setup(&presentations)
    let result = SetSlideBackgroundTool().run(
      args: """
        {"presentation_id": "\(presId)", "slide_number": 1,
         "gradient_color1": "FF0000", "gradient_color2": "0000FF", "gradient_angle": 1e300}
        """,
      presentations: &presentations)
    #expect(result.contains("\"kind\":\"invalid_args\""))
  }
}

// MARK: - Manifest Version

@Suite("Manifest Version")
struct ManifestVersionTests {
  @Test("Embedded manifest version matches the released version")
  func versionMatchesRelease() throws {
    let data = pptxManifestJSON.data(using: .utf8)!
    let manifest = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(manifest["version"] as? String == "1.1.0")
  }
}
