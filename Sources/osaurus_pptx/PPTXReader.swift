import Foundation

// MARK: - PPTX Reader

enum PPTXReader {

  /// Read a PPTX file into a Presentation model
  static func read(from filePath: String) throws -> Presentation {
    let tempDir = NSTemporaryDirectory() + "osaurus_pptx_read_\(UUID().uuidString)"
    defer {
      try? FileManager.default.removeItem(atPath: tempDir)
    }

    try createDirectoryIfNeeded(tempDir)

    // Validate the untrusted archive (entry count, size, ratio, entry paths,
    // symlinks) before extracting anything.
    try ZipArchiveGuard.validate(archiveAt: filePath)

    // Unzip
    let result = try runProcess("/usr/bin/unzip", arguments: ["-q", "-o", filePath, "-d", tempDir])
    if result.exitCode != 0 {
      throw PPTXError.unzipFailed(result.output)
    }

    // Parse presentation.xml to get slide list
    let presPath = "\(tempDir)/ppt/presentation.xml"
    guard FileManager.default.fileExists(atPath: presPath) else {
      throw PPTXError.invalidFile("Missing presentation.xml")
    }

    let presData = try Data(contentsOf: URL(fileURLWithPath: presPath))
    let presDoc = try XMLDocument(data: presData, options: [])

    // Get slide dimensions
    let slideWidth: Int
    let slideHeight: Int
    if let sldSzNodes = try? presDoc.nodes(forXPath: "//*[local-name()='sldSz']"),
      let sldSz = sldSzNodes.first as? XMLElement
    {
      slideWidth = Int(sldSz.attribute(forName: "cx")?.stringValue ?? "12192000") ?? 12_192_000
      slideHeight = Int(sldSz.attribute(forName: "cy")?.stringValue ?? "6858000") ?? 6_858_000
    } else {
      slideWidth = SlideDimensions.wideWidth
      slideHeight = SlideDimensions.wideHeight
    }

    // Get title from core properties
    var title = "Untitled"
    let corePath = "\(tempDir)/docProps/core.xml"
    if FileManager.default.fileExists(atPath: corePath),
      let coreData = try? Data(contentsOf: URL(fileURLWithPath: corePath)),
      let coreDoc = try? XMLDocument(data: coreData, options: [])
    {
      if let titleNodes = try? coreDoc.nodes(forXPath: "//*[local-name()='title']"),
        let titleNode = titleNodes.first
      {
        title = titleNode.stringValue ?? "Untitled"
      }
    }

    let presentation = Presentation(id: UUID().uuidString, title: title)
    presentation.slideWidth = slideWidth
    presentation.slideHeight = slideHeight
    presentation.sourcePath = filePath

    // Parse presentation.xml.rels to map rIds to slide files
    let presRelsPath = "\(tempDir)/ppt/_rels/presentation.xml.rels"
    var slideRIdMap: [(rId: String, target: String)] = []

    if FileManager.default.fileExists(atPath: presRelsPath),
      let relsData = try? Data(contentsOf: URL(fileURLWithPath: presRelsPath)),
      let relsDoc = try? XMLDocument(data: relsData, options: [])
    {
      if let relNodes = try? relsDoc.nodes(forXPath: "//*[local-name()='Relationship']") {
        for node in relNodes {
          guard let el = node as? XMLElement,
            let type = el.attribute(forName: "Type")?.stringValue,
            let rId = el.attribute(forName: "Id")?.stringValue,
            let target = el.attribute(forName: "Target")?.stringValue
          else { continue }
          if type.contains("slide") && !type.contains("Master") && !type.contains("Layout") {
            slideRIdMap.append((rId: rId, target: target))
          }
        }
      }
    }

    // Get ordered slide rIds from presentation.xml
    var orderedSlideRIds: [String] = []
    if let sldIdNodes = try? presDoc.nodes(forXPath: "//*[local-name()='sldId']") {
      for node in sldIdNodes {
        if let el = node as? XMLElement,
          let rId = el.attribute(forLocalName: "id", uri: OOXML.nsR)?.stringValue
            ?? el.attribute(forName: "r:id")?.stringValue
        {
          orderedSlideRIds.append(rId)
        }
      }
    }

    // If no ordered list found, use the rels order
    let slideOrder = orderedSlideRIds.isEmpty ? slideRIdMap.map { $0.rId } : orderedSlideRIds

    // Parse each slide
    for rId in slideOrder {
      guard let slideInfo = slideRIdMap.first(where: { $0.rId == rId }) else { continue }
      let slidePath = try resolveRelationshipTarget(
        slideInfo.target, baseDir: "\(tempDir)/ppt", packageRoot: tempDir)

      guard FileManager.default.fileExists(atPath: slidePath) else { continue }

      let slide = try parseSlide(at: slidePath, tempDir: tempDir)
      presentation.slides.append(slide)
    }

    return presentation
  }

  // MARK: - Relationship Target Resolution

  /// Resolve an OOXML relationship target against its base part directory and
  /// prove the result stays inside the extraction root before filesystem use.
  static func resolveRelationshipTarget(
    _ target: String, baseDir: String, packageRoot: String
  ) throws -> String {
    let combined: String
    if target.hasPrefix("/") {
      // Package-absolute target, resolved from the package root.
      combined = packageRoot + target
    } else {
      combined = "\(baseDir)/\(target)"
    }
    let resolved = canonicalizePath(combined)
    guard isContained(resolved, in: packageRoot) else {
      throw PPTXError.invalidFile("Relationship target escapes package: \(target)")
    }
    return resolved
  }

  // MARK: - Slide Parsing

  private static func parseSlide(at path: String, tempDir: String) throws -> Slide {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let doc = try XMLDocument(data: data, options: [])

    let slide = Slide()

    // Parse text boxes (sp elements with txBody)
    if let spNodes = try? doc.nodes(forXPath: "//*[local-name()='sp']") {
      for node in spNodes {
        guard let el = node as? XMLElement else { continue }
        if let textEl = parseTextElement(el) {
          slide.elements.append(textEl)
        }
      }
    }

    // Parse background
    if let bgNodes = try? doc.nodes(forXPath: "//*[local-name()='bg']/*[local-name()='bgPr']"),
      let bgPr = bgNodes.first as? XMLElement
    {
      slide.background = parseBackground(bgPr)
    }

    return slide
  }

  // MARK: - Text Element Parsing

  private static func parseTextElement(_ sp: XMLElement) -> TextElement? {
    // Get position
    guard let xfrmNodes = try? sp.nodes(forXPath: ".//*[local-name()='xfrm']"),
      let xfrm = xfrmNodes.first as? XMLElement
    else { return nil }

    let offNodes = try? xfrm.nodes(forXPath: "./*[local-name()='off']")
    let extNodes = try? xfrm.nodes(forXPath: "./*[local-name()='ext']")

    guard let off = offNodes?.first as? XMLElement,
      let ext = extNodes?.first as? XMLElement
    else { return nil }

    let x = Double(off.attribute(forName: "x")?.stringValue ?? "0") ?? 0
    let y = Double(off.attribute(forName: "y")?.stringValue ?? "0") ?? 0
    let cx = Double(ext.attribute(forName: "cx")?.stringValue ?? "0") ?? 0
    let cy = Double(ext.attribute(forName: "cy")?.stringValue ?? "0") ?? 0

    let position = ElementPosition(
      x: x / Double(Units.emuPerInch),
      y: y / Double(Units.emuPerInch),
      width: cx / Double(Units.emuPerInch),
      height: cy / Double(Units.emuPerInch)
    )

    // Get text content
    guard let txBodyNodes = try? sp.nodes(forXPath: ".//*[local-name()='txBody']"),
      let txBody = txBodyNodes.first as? XMLElement
    else { return nil }

    var paragraphs: [String] = []
    if let pNodes = try? txBody.nodes(forXPath: "./*[local-name()='p']") {
      for pNode in pNodes {
        guard let pEl = pNode as? XMLElement else { continue }
        var paraText = ""
        if let rNodes = try? pEl.nodes(forXPath: "./*[local-name()='r']") {
          for rNode in rNodes {
            if let tNodes = try? rNode.nodes(forXPath: "./*[local-name()='t']"),
              let tNode = tNodes.first
            {
              paraText += tNode.stringValue ?? ""
            }
          }
        }
        paragraphs.append(paraText)
      }
    }

    let fullText = paragraphs.joined(separator: "\n")
    guard !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

    // Parse formatting from first run
    var fontSize: Double = 18
    var fontFace = "Calibri"
    var fontColor = "000000"
    var bold = false
    var italic = false
    var underline = false

    if let rPrNodes = try? txBody.nodes(forXPath: ".//*[local-name()='rPr']"),
      let rPr = rPrNodes.first as? XMLElement
    {
      if let sz = rPr.attribute(forName: "sz")?.stringValue, let szVal = Double(sz) {
        fontSize = szVal / 100.0
      }
      bold = rPr.attribute(forName: "b")?.stringValue == "1"
      italic = rPr.attribute(forName: "i")?.stringValue == "1"
      underline = rPr.attribute(forName: "u")?.stringValue == "sng"

      if let colorNodes = try? rPr.nodes(forXPath: ".//*[local-name()='srgbClr']"),
        let colorEl = colorNodes.first as? XMLElement,
        let colorVal = colorEl.attribute(forName: "val")?.stringValue
      {
        fontColor = colorVal
      }

      if let latinNodes = try? rPr.nodes(forXPath: "./*[local-name()='latin']"),
        let latin = latinNodes.first as? XMLElement,
        let tf = latin.attribute(forName: "typeface")?.stringValue
      {
        fontFace = tf
      }
    }

    // Parse alignment
    var alignment = TextAlignment.left
    if let pPrNodes = try? txBody.nodes(forXPath: "./*[local-name()='p']/*[local-name()='pPr']"),
      let pPr = pPrNodes.first as? XMLElement,
      let algn = pPr.attribute(forName: "algn")?.stringValue
    {
      alignment = TextAlignment(from: algn)
    }

    return TextElement(
      text: fullText,
      position: position,
      fontSize: fontSize,
      fontFace: fontFace,
      fontColor: fontColor,
      bold: bold,
      italic: italic,
      underline: underline,
      alignment: alignment
    )
  }

  // MARK: - Background Parsing

  private static func parseBackground(_ bgPr: XMLElement) -> SlideBackground? {
    if let solidNodes = try? bgPr.nodes(
      forXPath: "./*[local-name()='solidFill']/*[local-name()='srgbClr']"),
      let solidEl = solidNodes.first as? XMLElement,
      let colorVal = solidEl.attribute(forName: "val")?.stringValue
    {
      return SlideBackground(type: .solid(color: colorVal))
    }

    if let gradNodes = try? bgPr.nodes(forXPath: "./*[local-name()='gradFill']"),
      let gradEl = gradNodes.first as? XMLElement
    {
      var colors: [String] = []
      if let gsNodes = try? gradEl.nodes(forXPath: ".//*[local-name()='srgbClr']") {
        for gsNode in gsNodes {
          if let gsEl = gsNode as? XMLElement,
            let val = gsEl.attribute(forName: "val")?.stringValue
          {
            colors.append(val)
          }
        }
      }
      if colors.count >= 2 {
        return SlideBackground(type: .gradient(color1: colors[0], color2: colors[1], angle: 270))
      }
    }

    return nil
  }
}
