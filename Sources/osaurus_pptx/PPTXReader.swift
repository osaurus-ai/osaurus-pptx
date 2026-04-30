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

    try ArchiveHelper.extractZipSafely(filePath, to: tempDir)

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
    presentation.fidelityWarnings = [
      "Existing-deck read mode exposes stable IDs for targeted tools, but the in-memory writer is simplified. Use update_text, replace_image, move_resize_element, duplicate_slide, reorder_slides, or export_presentation with an output_path to patch the original package where possible.",
      "Charts, tables, masters, layouts, animations, embedded media, and custom effects are preserved by package patch tools but are not fully represented in the in-memory model.",
    ]

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
    for (slideIndex, rId) in slideOrder.enumerated() {
      guard let slideInfo = slideRIdMap.first(where: { $0.rId == rId }) else { continue }
      let slidePath = "\(tempDir)/ppt/\(slideInfo.target)"

      guard FileManager.default.fileExists(atPath: slidePath) else { continue }

      let slide = try parseSlide(at: slidePath, tempDir: tempDir, slideNumber: slideIndex + 1)
      presentation.slides.append(slide)
    }

    return presentation
  }

  // MARK: - Slide Parsing

  private static func parseSlide(at path: String, tempDir: String, slideNumber: Int) throws -> Slide {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let doc = try XMLDocument(data: data, options: [])

    let slide = Slide(id: "slide\(slideNumber)")
    let relationships = loadSlideRelationships(forSlidePath: path, tempDir: tempDir)

    // Parse text boxes (sp elements with txBody)
    if let spNodes = try? doc.nodes(forXPath: "//*[local-name()='sp']") {
      for (index, node) in spNodes.enumerated() {
        guard let el = node as? XMLElement else { continue }
        if let textEl = parseTextElement(el, elementId: "slide\(slideNumber)-sp\(index + 1)") {
          slide.elements.append(textEl)
        }
      }
    }

    if let picNodes = try? doc.nodes(forXPath: "//*[local-name()='pic']") {
      for (index, node) in picNodes.enumerated() {
        guard let el = node as? XMLElement else { continue }
        if let imageEl = parseImageElement(
          el,
          elementId: "slide\(slideNumber)-pic\(index + 1)",
          relationships: relationships,
          slidePath: path)
        {
          slide.elements.append(imageEl)
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

  private static func parseTextElement(_ sp: XMLElement, elementId: String) -> TextElement? {
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
      elementId: elementId,
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

  private static func parseImageElement(
    _ pic: XMLElement,
    elementId: String,
    relationships: [String: String],
    slidePath: String
  ) -> ImageElement? {
    guard let position = parsePosition(in: pic) else { return nil }

    let blipNodes = try? pic.nodes(forXPath: ".//*[local-name()='blip']")
    guard let blip = blipNodes?.first as? XMLElement else { return nil }
    let rId =
      blip.attribute(forLocalName: "embed", uri: OOXML.nsR)?.stringValue
      ?? blip.attribute(forName: "r:embed")?.stringValue
    guard let rId, let target = relationships[rId] else { return nil }

    let slideDirectory = (slidePath as NSString).deletingLastPathComponent
    let targetPath = URL(fileURLWithPath: slideDirectory)
      .appendingPathComponent(target)
      .standardized.path
    let ext = (targetPath as NSString).pathExtension.lowercased()

    return ImageElement(
      elementId: elementId,
      sourcePath: targetPath,
      position: position,
      imageExtension: ext.isEmpty ? "png" : ext)
  }

  private static func parsePosition(in element: XMLElement) -> ElementPosition? {
    guard let xfrmNodes = try? element.nodes(forXPath: ".//*[local-name()='xfrm']"),
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

    return ElementPosition(
      x: x / Double(Units.emuPerInch),
      y: y / Double(Units.emuPerInch),
      width: cx / Double(Units.emuPerInch),
      height: cy / Double(Units.emuPerInch)
    )
  }

  private static func loadSlideRelationships(forSlidePath path: String, tempDir: String) -> [String:
    String]
  {
    let slideFileName = (path as NSString).lastPathComponent
    let relsPath = "\(tempDir)/ppt/slides/_rels/\(slideFileName).rels"
    guard FileManager.default.fileExists(atPath: relsPath),
      let relsData = try? Data(contentsOf: URL(fileURLWithPath: relsPath)),
      let relsDoc = try? XMLDocument(data: relsData, options: []),
      let relNodes = try? relsDoc.nodes(forXPath: "//*[local-name()='Relationship']")
    else {
      return [:]
    }

    var relationships: [String: String] = [:]
    for node in relNodes {
      guard let el = node as? XMLElement,
        let id = el.attribute(forName: "Id")?.stringValue,
        let target = el.attribute(forName: "Target")?.stringValue
      else { continue }
      relationships[id] = target
    }
    return relationships
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
