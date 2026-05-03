import Foundation

struct PPTXSlideReference {
  let number: Int
  let relationshipId: String
  let target: String
  let path: String
}

struct PPTXPackageInspection {
  let slideCount: Int
  let widthEMU: Int
  let heightEMU: Int
  let slidesJSON: String
  let warnings: [String]
}

struct PPTXMutationReport {
  let outputPath: String
  let changedCount: Int
  let warnings: [String]
}

enum PPTXPackage {
  static func inspect(filePath: String) throws -> PPTXPackageInspection {
    let tempDir = NSTemporaryDirectory() + "osaurus_pptx_inspect_\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: tempDir) }
    try ArchiveHelper.extractZipSafely(filePath, to: tempDir)

    let presPath = "\(tempDir)/ppt/presentation.xml"
    guard FileManager.default.fileExists(atPath: presPath) else {
      throw PPTXError.invalidFile("Missing ppt/presentation.xml")
    }

    let presDoc = try xmlDocument(at: presPath)
    let dimensions = slideDimensions(from: presDoc)
    let slideRefs = try slideReferences(in: tempDir, presentationDocument: presDoc)
    var warnings: [String] = []
    if !FileManager.default.fileExists(atPath: "\(tempDir)/[Content_Types].xml") {
      warnings.append("Missing [Content_Types].xml")
    }

    var slides: [String] = []
    for slideRef in slideRefs {
      let slideDoc = try xmlDocument(at: slideRef.path)
      let textCount = textShapeNodes(in: slideDoc).count
      let imageCount = (try? slideDoc.nodes(forXPath: "//*[local-name()='pic']").count) ?? 0
      let tableCount = (try? slideDoc.nodes(forXPath: "//*[local-name()='tbl']").count) ?? 0
      let chartCount = chartRelationshipCount(for: slideRef, tempDir: tempDir)
      let notesPresent = notesRelationshipPresent(for: slideRef, tempDir: tempDir)
      slides.append(
        """
        {"number": \(slideRef.number), "relationship_id": "\(jsonEscape(slideRef.relationshipId))", "target": "\(jsonEscape(slideRef.target))", "text_elements": \(textCount), "images": \(imageCount), "tables": \(tableCount), "charts": \(chartCount), "notes_present": \(notesPresent ? "true" : "false")}
        """)
    }

    return PPTXPackageInspection(
      slideCount: slideRefs.count,
      widthEMU: dimensions.width,
      heightEMU: dimensions.height,
      slidesJSON: "[\(slides.joined(separator: ","))]",
      warnings: warnings)
  }

  static func updateText(
    inputPath: String,
    outputPath: String,
    slideNumber: Int,
    elementId: String?,
    matchText: String?,
    replacementText: String
  ) throws -> PPTXMutationReport {
    let tempDir = try extractForMutation(inputPath)
    defer { try? FileManager.default.removeItem(atPath: tempDir) }

    let slideRef = try slideReference(number: slideNumber, in: tempDir)
    let doc = try xmlDocument(at: slideRef.path)
    let textNodes = textShapeNodes(in: doc)
    var changed = 0

    for (index, node) in textNodes.enumerated() {
      guard let shape = node as? XMLElement else { continue }
      let stableId = "slide\(slideNumber)-sp\(index + 1)"
      if let elementId, elementId != stableId { continue }

      let textLeaves = textLeafNodes(in: shape)
      let originalText = textLeaves.map { $0.stringValue ?? "" }.joined()
      if let matchText, !originalText.contains(matchText) { continue }

      let newText =
        matchText.map { originalText.replacingOccurrences(of: $0, with: replacementText) }
        ?? replacementText
      guard !textLeaves.isEmpty else { continue }
      textLeaves[0].stringValue = newText
      for leaf in textLeaves.dropFirst() {
        leaf.stringValue = ""
      }
      changed += 1
    }

    try writeXMLDocument(doc, to: slideRef.path)
    try ArchiveHelper.zipDirectory(tempDir, to: outputPath)

    return PPTXMutationReport(outputPath: outputPath, changedCount: changed, warnings: [])
  }

  static func moveResizeElement(
    inputPath: String,
    outputPath: String,
    slideNumber: Int,
    elementId: String,
    x: Double?,
    y: Double?,
    width: Double?,
    height: Double?
  ) throws -> PPTXMutationReport {
    let tempDir = try extractForMutation(inputPath)
    defer { try? FileManager.default.removeItem(atPath: tempDir) }

    let slideRef = try slideReference(number: slideNumber, in: tempDir)
    let doc = try xmlDocument(at: slideRef.path)
    guard let element = elementNode(in: doc, slideNumber: slideNumber, elementId: elementId) else {
      throw PPTXError.invalidFile("Element not found: \(elementId)")
    }
    guard let xfrm = try? element.nodes(forXPath: ".//*[local-name()='xfrm']").first as? XMLElement
    else {
      throw PPTXError.invalidFile("Element has no transform: \(elementId)")
    }

    let off = firstChild(named: "off", in: xfrm) ?? XMLElement(name: "a:off")
    let ext = firstChild(named: "ext", in: xfrm) ?? XMLElement(name: "a:ext")
    if off.parent == nil { xfrm.addChild(off) }
    if ext.parent == nil { xfrm.addChild(ext) }

    if let x { setAttribute("x", value: "\(Units.inchesToEMU(x))", on: off) }
    if let y { setAttribute("y", value: "\(Units.inchesToEMU(y))", on: off) }
    if let width { setAttribute("cx", value: "\(Units.inchesToEMU(width))", on: ext) }
    if let height { setAttribute("cy", value: "\(Units.inchesToEMU(height))", on: ext) }

    try writeXMLDocument(doc, to: slideRef.path)
    try ArchiveHelper.zipDirectory(tempDir, to: outputPath)
    return PPTXMutationReport(outputPath: outputPath, changedCount: 1, warnings: [])
  }

  static func replaceImage(
    inputPath: String,
    outputPath: String,
    slideNumber: Int,
    elementId: String,
    imagePath: String
  ) throws -> PPTXMutationReport {
    let tempDir = try extractForMutation(inputPath)
    defer { try? FileManager.default.removeItem(atPath: tempDir) }

    let slideRef = try slideReference(number: slideNumber, in: tempDir)
    let doc = try xmlDocument(at: slideRef.path)
    guard let picture = elementNode(in: doc, slideNumber: slideNumber, elementId: elementId) else {
      throw PPTXError.invalidFile("Image element not found: \(elementId)")
    }
    guard let blip = try? picture.nodes(forXPath: ".//*[local-name()='blip']").first as? XMLElement
    else {
      throw PPTXError.invalidFile("Image element has no embedded relationship: \(elementId)")
    }
    let relationshipId =
      blip.attribute(forLocalName: "embed", uri: OOXML.nsR)?.stringValue
      ?? blip.attribute(forName: "r:embed")?.stringValue
    guard let relationshipId else {
      throw PPTXError.invalidFile("Image element has no r:embed: \(elementId)")
    }

    let relsPath = slideRelsPath(for: slideRef)
    let (relsDoc, relationshipElements) = try relationshipElementsById(at: relsPath)
    let relationships = try relationshipsById(at: relsPath)
    guard let relationship = relationships[relationshipId] else {
      throw PPTXError.invalidFile("Missing image relationship \(relationshipId)")
    }

    let mediaPath = try packagePath(
      tempDir: tempDir,
      baseDirectory: (slideRef.path as NSString).deletingLastPathComponent,
      target: relationship.target)
    let replacementExt = normalizedImageExtension((imagePath as NSString).pathExtension)
    let supported = ["png", "jpg", "gif", "bmp", "tiff", "tif", "svg"]
    guard supported.contains(replacementExt) else {
      throw PPTXError.invalidFile(
        "Unsupported replacement image extension: \(replacementExt). Supported: \(supported.joined(separator: ", "))")
    }

    let targetPath: String
    if normalizedImageExtension((mediaPath as NSString).pathExtension) == replacementExt {
      targetPath = mediaPath
    } else {
      let baseName = ((mediaPath as NSString).lastPathComponent as NSString).deletingPathExtension
      let mediaDir = (mediaPath as NSString).deletingLastPathComponent
      targetPath = "\(mediaDir)/\(baseName).\(replacementExt)"

      let oldTarget = relationship.target
      let newTarget =
        ((oldTarget as NSString).deletingLastPathComponent as NSString)
        .appendingPathComponent("\(baseName).\(replacementExt)")

      guard let relationshipElement = relationshipElements[relationshipId] else {
        throw PPTXError.invalidFile("Missing image relationship element \(relationshipId)")
      }
      setAttribute("Target", value: newTarget, on: relationshipElement)
      try writeXMLDocument(relsDoc, to: relsPath)
      try addContentTypeDefault(
        tempDir: tempDir,
        extension: replacementExt,
        contentType: imageContentType(for: replacementExt))
    }

    if FileManager.default.fileExists(atPath: targetPath) {
      try FileManager.default.removeItem(atPath: targetPath)
    }
    try FileManager.default.copyItem(atPath: imagePath, toPath: targetPath)
    if targetPath != mediaPath && FileManager.default.fileExists(atPath: mediaPath) {
      try? FileManager.default.removeItem(atPath: mediaPath)
    }
    try ArchiveHelper.zipDirectory(tempDir, to: outputPath)
    return PPTXMutationReport(outputPath: outputPath, changedCount: 1, warnings: [])
  }

  static func setSpeakerNotes(
    inputPath: String,
    outputPath: String,
    slideNumber: Int,
    notes: String
  ) throws -> PPTXMutationReport {
    let tempDir = try extractForMutation(inputPath)
    defer { try? FileManager.default.removeItem(atPath: tempDir) }

    let slideRef = try slideReference(number: slideNumber, in: tempDir)
    try ensureNotesMaster(in: tempDir)

    let slideRels = slideRelsPath(for: slideRef)
    try createEmptyRelationshipsFileIfMissing(at: slideRels)
    let (slideRelsDoc, slideRelElements) = try relationshipElementsById(at: slideRels)
    let slideRelationships = try relationshipsById(at: slideRels)

    let notesRelationship = slideRelationships.values.first { $0.type == OOXML.relTypeNotesSlide }
    let notesPath: String
    let notesFileName: String
    if let notesRelationship {
      notesPath = try packagePath(
        tempDir: tempDir,
        baseDirectory: (slideRef.path as NSString).deletingLastPathComponent,
        target: notesRelationship.target)
      notesFileName = (notesPath as NSString).lastPathComponent
    } else {
      let nextNumber = try nextAvailableFileNumber(
        in: "\(tempDir)/ppt/notesSlides",
        prefix: "notesSlide",
        suffix: ".xml")
      notesFileName = "notesSlide\(nextNumber).xml"
      notesPath = "\(tempDir)/ppt/notesSlides/\(notesFileName)"

      try createDirectoryIfNeeded("\(tempDir)/ppt/notesSlides")
      try createDirectoryIfNeeded("\(tempDir)/ppt/notesSlides/_rels")
      let existingIds = Set(slideRelElements.keys)
      let relationshipId = uniqueRelationshipId(preferred: "rIdNotes\(nextNumber)", existing: existingIds)
      let rel = XMLElement(name: "Relationship")
      setAttribute("Id", value: relationshipId, on: rel)
      setAttribute("Type", value: OOXML.relTypeNotesSlide, on: rel)
      setAttribute("Target", value: "../notesSlides/\(notesFileName)", on: rel)
      slideRelsDoc.rootElement()?.addChild(rel)
      try writeXMLDocument(slideRelsDoc, to: slideRels)
      try addContentTypeOverride(
        tempDir: tempDir,
        partName: "/ppt/notesSlides/\(notesFileName)",
        contentType: OOXML.contentTypeNotesSlide)
    }

    try createDirectoryIfNeeded((notesPath as NSString).deletingLastPathComponent)
    try writeFile(generateNotesSlideXML(notes: notes), to: notesPath)

    let notesRelsPath =
      "\((notesPath as NSString).deletingLastPathComponent)/_rels/\(notesFileName).rels"
    try createDirectoryIfNeeded((notesRelsPath as NSString).deletingLastPathComponent)
    try writeFile(
      generateNotesSlideRelsXML(slideFileName: (slideRef.path as NSString).lastPathComponent),
      to: notesRelsPath)

    try ArchiveHelper.zipDirectory(tempDir, to: outputPath)
    return PPTXMutationReport(outputPath: outputPath, changedCount: 1, warnings: [])
  }

  static func duplicateSlide(
    inputPath: String,
    outputPath: String,
    slideNumber: Int
  ) throws -> PPTXMutationReport {
    let tempDir = try extractForMutation(inputPath)
    defer { try? FileManager.default.removeItem(atPath: tempDir) }

    let presPath = "\(tempDir)/ppt/presentation.xml"
    let relsPath = "\(tempDir)/ppt/_rels/presentation.xml.rels"
    let presDoc = try xmlDocument(at: presPath)
    let slideRefs = try slideReferences(in: tempDir, presentationDocument: presDoc)
    guard let sourceRef = slideRefs.first(where: { $0.number == slideNumber }) else {
      throw PPTXError.invalidFile("Invalid slide number: \(slideNumber)")
    }

    let nextNumber = try nextAvailableSlideFileNumber(in: "\(tempDir)/ppt/slides")
    let newSlideName = "slide\(nextNumber).xml"
    let newSlidePath = "\(tempDir)/ppt/slides/\(newSlideName)"
    try FileManager.default.copyItem(atPath: sourceRef.path, toPath: newSlidePath)

    let sourceRelsPath = slideRelsPath(for: sourceRef)
    if FileManager.default.fileExists(atPath: sourceRelsPath) {
      try createDirectoryIfNeeded("\(tempDir)/ppt/slides/_rels")
      try FileManager.default.copyItem(
        atPath: sourceRelsPath,
        toPath: "\(tempDir)/ppt/slides/_rels/\(newSlideName).rels")
    }

    let relsDoc = try xmlDocument(at: relsPath)
    let newRelationshipId = uniqueRelationshipId(
      preferred: "rIdSlide\(nextNumber)",
      existing: Set(try relationshipsById(at: relsPath).keys))
    let rel = XMLElement(name: "Relationship")
    setAttribute("Id", value: newRelationshipId, on: rel)
    setAttribute("Type", value: OOXML.relTypeSlide, on: rel)
    setAttribute("Target", value: "slides/\(newSlideName)", on: rel)
    relsDoc.rootElement()?.addChild(rel)
    try writeXMLDocument(relsDoc, to: relsPath)

    guard let slideList = try? presDoc.nodes(forXPath: "//*[local-name()='sldIdLst']").first
      as? XMLElement
    else {
      throw PPTXError.invalidFile("Missing slide list")
    }
    let newSlideId = maxSlideId(in: presDoc) + 1
    let slideNode = XMLElement(name: "p:sldId")
    setAttribute("id", value: "\(newSlideId)", on: slideNode)
    setAttribute("r:id", value: newRelationshipId, on: slideNode)
    slideList.addChild(slideNode)
    try writeXMLDocument(presDoc, to: presPath)

    try addContentTypeOverride(
      tempDir: tempDir,
      partName: "/ppt/slides/\(newSlideName)",
      contentType: OOXML.contentTypeSlide)

    try ArchiveHelper.zipDirectory(tempDir, to: outputPath)
    return PPTXMutationReport(
      outputPath: outputPath,
      changedCount: 1,
      warnings: ["Duplicated slide is appended to the deck. Reorder afterward if needed."])
  }

  static func reorderSlides(
    inputPath: String,
    outputPath: String,
    slideOrder: [Int]
  ) throws -> PPTXMutationReport {
    let tempDir = try extractForMutation(inputPath)
    defer { try? FileManager.default.removeItem(atPath: tempDir) }

    let presPath = "\(tempDir)/ppt/presentation.xml"
    let presDoc = try xmlDocument(at: presPath)
    guard let slideList = try? presDoc.nodes(forXPath: "//*[local-name()='sldIdLst']").first
      as? XMLElement,
      let children = slideList.children
    else {
      throw PPTXError.invalidFile("Missing slide list")
    }

    let slideNodes = children.filter { ($0 as? XMLElement)?.localName == "sldId" }
    let expected = Set(1...slideNodes.count)
    guard Set(slideOrder) == expected && slideOrder.count == slideNodes.count else {
      throw PPTXError.invalidFile(
        "slide_order must be a permutation of 1...\(slideNodes.count)")
    }

    let reordered = slideOrder.map { slideNodes[$0 - 1].copy() as! XMLNode }
    slideList.setChildren(reordered)
    try writeXMLDocument(presDoc, to: presPath)
    try ArchiveHelper.zipDirectory(tempDir, to: outputPath)
    return PPTXMutationReport(outputPath: outputPath, changedCount: slideOrder.count, warnings: [])
  }

  static func slideReferences(
    in tempDir: String,
    presentationDocument presDoc: XMLDocument? = nil
  ) throws -> [PPTXSlideReference] {
    let presDoc = try presDoc ?? xmlDocument(at: "\(tempDir)/ppt/presentation.xml")
    let rels = try relationshipsById(at: "\(tempDir)/ppt/_rels/presentation.xml.rels")
    let sldIdNodes = try presDoc.nodes(forXPath: "//*[local-name()='sldId']")

    var refs: [PPTXSlideReference] = []
    for node in sldIdNodes {
      guard let el = node as? XMLElement else { continue }
      let relationshipId =
        el.attribute(forLocalName: "id", uri: OOXML.nsR)?.stringValue
        ?? el.attribute(forName: "r:id")?.stringValue
      guard let relationshipId, let relationship = rels[relationshipId],
        relationship.type == OOXML.relTypeSlide
      else { continue }

      let path = try packagePath(
        tempDir: tempDir,
        baseDirectory: "\(tempDir)/ppt",
        target: relationship.target)
      refs.append(
        PPTXSlideReference(
          number: refs.count + 1,
          relationshipId: relationshipId,
          target: relationship.target,
          path: path))
    }
    return refs
  }

  // MARK: - Helpers

  private struct Relationship {
    let id: String
    let type: String
    let target: String
  }

  private static func extractForMutation(_ inputPath: String) throws -> String {
    let tempDir = NSTemporaryDirectory() + "osaurus_pptx_patch_\(UUID().uuidString)"
    try ArchiveHelper.extractZipSafely(inputPath, to: tempDir)
    return tempDir
  }

  private static func slideReference(number: Int, in tempDir: String) throws -> PPTXSlideReference {
    let refs = try slideReferences(in: tempDir)
    guard number >= 1 && number <= refs.count else {
      throw PPTXError.invalidFile("Invalid slide number: \(number). Presentation has \(refs.count) slides.")
    }
    return refs[number - 1]
  }

  private static func xmlDocument(at path: String) throws -> XMLDocument {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try XMLDocument(data: data, options: [])
  }

  private static func writeXMLDocument(_ document: XMLDocument, to path: String) throws {
    try document.xmlData(options: .nodePrettyPrint)
      .write(to: URL(fileURLWithPath: path), options: .atomic)
  }

  private static func slideDimensions(from doc: XMLDocument) -> (width: Int, height: Int) {
    guard let sldSz = try? doc.nodes(forXPath: "//*[local-name()='sldSz']").first as? XMLElement
    else {
      return (SlideDimensions.wideWidth, SlideDimensions.wideHeight)
    }
    let width = Int(sldSz.attribute(forName: "cx")?.stringValue ?? "") ?? SlideDimensions.wideWidth
    let height =
      Int(sldSz.attribute(forName: "cy")?.stringValue ?? "") ?? SlideDimensions.wideHeight
    return (width, height)
  }

  private static func textShapeNodes(in doc: XMLDocument) -> [XMLNode] {
    ((try? doc.nodes(forXPath: "//*[local-name()='sp'][.//*[local-name()='txBody']]")) ?? [])
      .filter { node in
        guard let el = node as? XMLElement else { return false }
        return !textLeafNodes(in: el).map { $0.stringValue ?? "" }.joined()
          .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
  }

  private static func textLeafNodes(in element: XMLElement) -> [XMLNode] {
    (try? element.nodes(forXPath: ".//*[local-name()='txBody']//*[local-name()='t']")) ?? []
  }

  private static func elementNode(
    in doc: XMLDocument,
    slideNumber: Int,
    elementId: String
  ) -> XMLElement? {
    if let index = elementIndex(in: elementId, slideNumber: slideNumber, marker: "sp") {
      let nodes = (try? doc.nodes(forXPath: "//*[local-name()='sp']")) ?? []
      return nodes.indices.contains(index - 1) ? nodes[index - 1] as? XMLElement : nil
    }

    if let index = elementIndex(in: elementId, slideNumber: slideNumber, marker: "pic") {
      let nodes = (try? doc.nodes(forXPath: "//*[local-name()='pic']")) ?? []
      return nodes.indices.contains(index - 1) ? nodes[index - 1] as? XMLElement : nil
    }

    return nil
  }

  private static func elementIndex(
    in elementId: String,
    slideNumber: Int,
    marker: String
  ) -> Int? {
    let prefix = "slide\(slideNumber)-\(marker)"
    guard elementId.hasPrefix(prefix) else { return nil }
    return Int(elementId.dropFirst(prefix.count))
  }

  private static func firstChild(named localName: String, in element: XMLElement) -> XMLElement? {
    element.children?.compactMap { $0 as? XMLElement }.first { $0.localName == localName }
  }

  private static func setAttribute(_ name: String, value: String, on element: XMLElement) {
    if let attribute = element.attribute(forName: name) {
      attribute.stringValue = value
    } else {
      element.addAttribute(XMLNode.attribute(withName: name, stringValue: value) as! XMLNode)
    }
  }

  private static func relationshipsById(at path: String) throws -> [String: Relationship] {
    let doc = try xmlDocument(at: path)
    let relNodes = try doc.nodes(forXPath: "//*[local-name()='Relationship']")
    var result: [String: Relationship] = [:]
    for node in relNodes {
      guard let el = node as? XMLElement,
        let id = el.attribute(forName: "Id")?.stringValue,
        let type = el.attribute(forName: "Type")?.stringValue,
        let target = el.attribute(forName: "Target")?.stringValue
      else { continue }
      result[id] = Relationship(id: id, type: type, target: target)
    }
    return result
  }

  private static func relationshipElementsById(at path: String) throws -> (
    XMLDocument, [String: XMLElement]
  ) {
    let doc = try xmlDocument(at: path)
    let relNodes = try doc.nodes(forXPath: "//*[local-name()='Relationship']")
    var result: [String: XMLElement] = [:]
    for node in relNodes {
      guard let el = node as? XMLElement,
        let id = el.attribute(forName: "Id")?.stringValue
      else { continue }
      result[id] = el
    }
    return (doc, result)
  }

  private static func createEmptyRelationshipsFileIfMissing(at path: String) throws {
    guard !FileManager.default.fileExists(atPath: path) else { return }
    try createDirectoryIfNeeded((path as NSString).deletingLastPathComponent)
    try writeFile(
      """
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="\(OOXML.nsRelationships)">
      </Relationships>
      """,
      to: path)
  }

  private static func packagePath(
    tempDir: String,
    baseDirectory: String,
    target: String
  ) throws -> String {
    let root = URL(fileURLWithPath: tempDir).standardized.path
    let url: URL
    if target.hasPrefix("/") {
      url = URL(fileURLWithPath: root).appendingPathComponent(String(target.dropFirst()))
    } else {
      url = URL(fileURLWithPath: baseDirectory).appendingPathComponent(target)
    }

    let resolved = url.standardized.path
    guard resolved == root || resolved.hasPrefix(root + "/") else {
      throw PPTXError.invalidFile("Relationship target escapes package: \(target)")
    }
    return resolved
  }

  private static func slideRelsPath(for slideRef: PPTXSlideReference) -> String {
    let name = (slideRef.path as NSString).lastPathComponent
    let dir = (slideRef.path as NSString).deletingLastPathComponent
    return "\(dir)/_rels/\(name).rels"
  }

  private static func chartRelationshipCount(for slideRef: PPTXSlideReference, tempDir: String)
    -> Int
  {
    guard let relationships = try? relationshipsById(at: slideRelsPath(for: slideRef)) else {
      return 0
    }
    return relationships.values.filter { $0.type == OOXML.relTypeChart }.count
  }

  private static func notesRelationshipPresent(for slideRef: PPTXSlideReference, tempDir: String)
    -> Bool
  {
    guard let relationships = try? relationshipsById(at: slideRelsPath(for: slideRef)) else {
      return false
    }
    return relationships.values.contains { $0.type.contains("/notesSlide") }
  }

  private static func normalizedImageExtension(_ ext: String) -> String {
    ext.lowercased() == "jpeg" ? "jpg" : ext.lowercased()
  }

  private static func nextAvailableFileNumber(in directory: String, prefix: String, suffix: String)
    throws -> Int
  {
    guard FileManager.default.fileExists(atPath: directory) else { return 1 }
    let entries = try FileManager.default.contentsOfDirectory(atPath: directory)
    let numbers = entries.compactMap { entry -> Int? in
      guard entry.hasPrefix(prefix), entry.hasSuffix(suffix) else { return nil }
      let start = entry.index(entry.startIndex, offsetBy: prefix.count)
      let end = entry.index(entry.endIndex, offsetBy: -suffix.count)
      return Int(entry[start..<end])
    }
    return (numbers.max() ?? 0) + 1
  }

  private static func nextAvailableSlideFileNumber(in slidesDir: String) throws -> Int {
    let entries = try FileManager.default.contentsOfDirectory(atPath: slidesDir)
    let numbers = entries.compactMap { entry -> Int? in
      guard entry.hasPrefix("slide"), entry.hasSuffix(".xml") else { return nil }
      let start = entry.index(entry.startIndex, offsetBy: 5)
      let end = entry.index(entry.endIndex, offsetBy: -4)
      return Int(entry[start..<end])
    }
    return (numbers.max() ?? 0) + 1
  }

  private static func uniqueRelationshipId(preferred: String, existing: Set<String>) -> String {
    if !existing.contains(preferred) { return preferred }
    var index = 1
    while existing.contains("\(preferred)_\(index)") {
      index += 1
    }
    return "\(preferred)_\(index)"
  }

  private static func maxSlideId(in doc: XMLDocument) -> Int {
    let nodes = (try? doc.nodes(forXPath: "//*[local-name()='sldId']")) ?? []
    return nodes.compactMap { ($0 as? XMLElement)?.attribute(forName: "id")?.stringValue }
      .compactMap(Int.init)
      .max() ?? 255
  }

  private static func addContentTypeOverride(
    tempDir: String,
    partName: String,
    contentType: String
  ) throws {
    let path = "\(tempDir)/[Content_Types].xml"
    let doc = try xmlDocument(at: path)
    let existing = (try? doc.nodes(forXPath: "//*[local-name()='Override']")).orEmpty
    for node in existing {
      if let el = node as? XMLElement,
        el.attribute(forName: "PartName")?.stringValue == partName
      {
        return
      }
    }

    let override = XMLElement(name: "Override")
    setAttribute("PartName", value: partName, on: override)
    setAttribute("ContentType", value: contentType, on: override)
    doc.rootElement()?.addChild(override)
    try writeXMLDocument(doc, to: path)
  }

  private static func addContentTypeDefault(
    tempDir: String,
    extension ext: String,
    contentType: String
  ) throws {
    let path = "\(tempDir)/[Content_Types].xml"
    let doc = try xmlDocument(at: path)
    let existing = (try? doc.nodes(forXPath: "//*[local-name()='Default']")).orEmpty
    for node in existing {
      if let el = node as? XMLElement,
        el.attribute(forName: "Extension")?.stringValue?.lowercased() == ext.lowercased()
      {
        return
      }
    }

    let defaultNode = XMLElement(name: "Default")
    setAttribute("Extension", value: ext.lowercased(), on: defaultNode)
    setAttribute("ContentType", value: contentType, on: defaultNode)
    doc.rootElement()?.addChild(defaultNode)
    try writeXMLDocument(doc, to: path)
  }

  private static func ensureNotesMaster(in tempDir: String) throws {
    let notesMasterDir = "\(tempDir)/ppt/notesMasters"
    let notesMasterPath = "\(notesMasterDir)/notesMaster1.xml"
    try createDirectoryIfNeeded(notesMasterDir)
    try createDirectoryIfNeeded("\(notesMasterDir)/_rels")
    if !FileManager.default.fileExists(atPath: notesMasterPath) {
      try writeFile(generateNotesMasterXML(), to: notesMasterPath)
      try writeFile(
        generateNotesMasterRelsXML(),
        to: "\(notesMasterDir)/_rels/notesMaster1.xml.rels")
      try addContentTypeOverride(
        tempDir: tempDir,
        partName: "/ppt/notesMasters/notesMaster1.xml",
        contentType: OOXML.contentTypeNotesMaster)
    }

    let presRelsPath = "\(tempDir)/ppt/_rels/presentation.xml.rels"
    let (relsDoc, relElements) = try relationshipElementsById(at: presRelsPath)
    let relationships = try relationshipsById(at: presRelsPath)
    if !relationships.values.contains(where: { $0.type == OOXML.relTypeNotesMaster }) {
      let relationshipId = uniqueRelationshipId(
        preferred: "rIdNotesMaster1",
        existing: Set(relElements.keys))
      let rel = XMLElement(name: "Relationship")
      setAttribute("Id", value: relationshipId, on: rel)
      setAttribute("Type", value: OOXML.relTypeNotesMaster, on: rel)
      setAttribute("Target", value: "notesMasters/notesMaster1.xml", on: rel)
      relsDoc.rootElement()?.addChild(rel)
      try writeXMLDocument(relsDoc, to: presRelsPath)

      let presPath = "\(tempDir)/ppt/presentation.xml"
      let presDoc = try xmlDocument(at: presPath)
      if !(try presDoc.nodes(forXPath: "//*[local-name()='notesMasterIdLst']").isEmpty) {
        return
      }
      let notesMasterList = XMLElement(name: "p:notesMasterIdLst")
      let notesMasterId = XMLElement(name: "p:notesMasterId")
      setAttribute("r:id", value: relationshipId, on: notesMasterId)
      notesMasterList.addChild(notesMasterId)
      presDoc.rootElement()?.addChild(notesMasterList)
      try writeXMLDocument(presDoc, to: presPath)
    }
  }

  private static func generateNotesSlideXML(notes: String) -> String {
    """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <p:notes xmlns:a="\(OOXML.nsA)" xmlns:r="\(OOXML.nsR)" xmlns:p="\(OOXML.nsP)">
      <p:cSld>
        <p:spTree>
          <p:nvGrpSpPr>
            <p:cNvPr id="1" name=""/>
            <p:cNvGrpSpPr/>
            <p:nvPr/>
          </p:nvGrpSpPr>
          <p:grpSpPr>
            <a:xfrm>
              <a:off x="0" y="0"/>
              <a:ext cx="0" cy="0"/>
              <a:chOff x="0" y="0"/>
              <a:chExt cx="0" cy="0"/>
            </a:xfrm>
          </p:grpSpPr>
          <p:sp>
            <p:nvSpPr>
              <p:cNvPr id="2" name="Notes Placeholder 1"/>
              <p:cNvSpPr txBox="1"/>
              <p:nvPr><p:ph type="body" idx="1"/></p:nvPr>
            </p:nvSpPr>
            <p:spPr>
              <a:xfrm>
                <a:off x="685800" y="914400"/>
                <a:ext cx="5486400" cy="4114800"/>
              </a:xfrm>
              <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
              <a:noFill/>
            </p:spPr>
            <p:txBody>
              <a:bodyPr/>
              <a:lstStyle/>
              <a:p><a:r><a:rPr lang="en-US" sz="1200"/><a:t>\(xmlEscape(notes))</a:t></a:r><a:endParaRPr lang="en-US" sz="1200"/></a:p>
            </p:txBody>
          </p:sp>
        </p:spTree>
      </p:cSld>
      <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
    </p:notes>
    """
  }

  private static func generateNotesSlideRelsXML(slideFileName: String) -> String {
    """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="\(OOXML.nsRelationships)">
      <Relationship Id="rId1" Type="\(OOXML.relTypeSlide)" Target="../slides/\(xmlEscape(slideFileName))"/>
      <Relationship Id="rId2" Type="\(OOXML.relTypeNotesMaster)" Target="../notesMasters/notesMaster1.xml"/>
    </Relationships>
    """
  }

  private static func generateNotesMasterXML() -> String {
    """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <p:notesMaster xmlns:a="\(OOXML.nsA)" xmlns:r="\(OOXML.nsR)" xmlns:p="\(OOXML.nsP)">
      <p:cSld>
        <p:bg><p:bgPr><a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>
        <p:spTree>
          <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
          <p:grpSpPr>
            <a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm>
          </p:grpSpPr>
        </p:spTree>
      </p:cSld>
      <p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>
    </p:notesMaster>
    """
  }

  private static func generateNotesMasterRelsXML() -> String {
    """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="\(OOXML.nsRelationships)">
    </Relationships>
    """
  }
}

private extension Optional where Wrapped == [XMLNode] {
  var orEmpty: [XMLNode] { self ?? [] }
}
