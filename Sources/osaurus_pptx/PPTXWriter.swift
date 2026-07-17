import Foundation
import OsaurusPluginKit

// MARK: - PPTX Writer

/// Outcome of a successful write, including images that had to be dropped
/// because their source data was missing or unreadable.
struct PPTXWriteResult {
  var skippedImages: [String] = []
}

enum PPTXWriter {

  /// Write a presentation to a .pptx file at the given path
  @discardableResult
  static func write(presentation: Presentation, to outputPath: String) throws -> PPTXWriteResult {
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: outputPath, isDirectory: &isDirectory),
      isDirectory.boolValue
    {
      throw PPTXError.invalidDestination("Destination is an existing directory: \(outputPath)")
    }

    try validateNumericValues(presentation: presentation)

    let tempDir = NSTemporaryDirectory() + "osaurus_pptx_\(UUID().uuidString)"
    let outputDir = (outputPath as NSString).deletingLastPathComponent
    let packagePath = "\(outputDir)/.osaurus-pptx-\(UUID().uuidString).tmp"
    defer {
      try? FileManager.default.removeItem(atPath: tempDir)
      try? FileManager.default.removeItem(atPath: packagePath)
    }

    // Create directory structure
    try createDirectoryIfNeeded(tempDir)
    try createDirectoryIfNeeded("\(tempDir)/ppt")
    try createDirectoryIfNeeded("\(tempDir)/ppt/slides")
    try createDirectoryIfNeeded("\(tempDir)/ppt/slides/_rels")
    try createDirectoryIfNeeded("\(tempDir)/ppt/slideMasters")
    try createDirectoryIfNeeded("\(tempDir)/ppt/slideMasters/_rels")
    try createDirectoryIfNeeded("\(tempDir)/ppt/slideLayouts")
    try createDirectoryIfNeeded("\(tempDir)/ppt/slideLayouts/_rels")
    try createDirectoryIfNeeded("\(tempDir)/ppt/theme")
    try createDirectoryIfNeeded("\(tempDir)/ppt/_rels")
    try createDirectoryIfNeeded("\(tempDir)/_rels")
    try createDirectoryIfNeeded("\(tempDir)/docProps")

    // Collect media and chart info
    var imageFiles: [(data: Data, targetName: String, ext: String)] = []
    var chartFiles: [(chartIndex: Int, xml: String)] = []
    var globalImageIndex = 0
    var globalChartIndex = 0
    var result = PPTXWriteResult()

    // Pre-process slides to assign relationship IDs and collect media.
    // Images whose source data is missing or unreadable are dropped (no
    // dangling relationship is written) and reported in the result.
    for slide in presentation.slides {
      var imageCount = 0
      var chartCount = 0
      for element in slide.elements {
        if let image = element as? ImageElement {
          guard image.sourcePath.hasPrefix("/"),
            let data = FileManager.default.contents(atPath: image.sourcePath)
          else {
            image.rId = nil
            result.skippedImages.append(image.sourcePath)
            continue
          }
          globalImageIndex += 1
          imageCount += 1
          let ext = image.imageExtension
          let mediaName = "image\(globalImageIndex).\(ext)"
          image.rId = "rIdImg\(imageCount)"
          imageFiles.append((data: data, targetName: mediaName, ext: ext))
        } else if let chart = element as? ChartElement {
          globalChartIndex += 1
          chartCount += 1
          chart.chartIndex = globalChartIndex
          chart.rId = "rIdChart\(chartCount)"
          let chartXML = ChartXMLGenerator.generateChartXML(chart: chart)
          chartFiles.append((chartIndex: globalChartIndex, xml: chartXML))
        }
      }
    }

    // Create media directory if needed
    if !imageFiles.isEmpty {
      try createDirectoryIfNeeded("\(tempDir)/ppt/media")
    }

    // Create charts directory if needed
    if !chartFiles.isEmpty {
      try createDirectoryIfNeeded("\(tempDir)/ppt/charts")
      try createDirectoryIfNeeded("\(tempDir)/ppt/charts/_rels")
    }

    // Copy image files
    for imageFile in imageFiles {
      let destPath = "\(tempDir)/ppt/media/\(imageFile.targetName)"
      try writeData(imageFile.data, to: destPath)
    }

    // Write chart XML files
    for chartFile in chartFiles {
      try writeFile(chartFile.xml, to: "\(tempDir)/ppt/charts/chart\(chartFile.chartIndex).xml")
      try writeFile(
        ChartXMLGenerator.generateChartRels(),
        to: "\(tempDir)/ppt/charts/_rels/chart\(chartFile.chartIndex).xml.rels")
    }

    // Write theme
    try writeFile(
      ThemeXMLGenerator.generateThemeXML(theme: presentation.theme),
      to: "\(tempDir)/ppt/theme/theme1.xml")

    // Write slide master
    try writeFile(
      ThemeXMLGenerator.generateSlideMasterXML(theme: presentation.theme),
      to: "\(tempDir)/ppt/slideMasters/slideMaster1.xml")
    try writeFile(
      ThemeXMLGenerator.generateSlideMasterRels(),
      to: "\(tempDir)/ppt/slideMasters/_rels/slideMaster1.xml.rels")

    // Write slide layout
    try writeFile(
      ThemeXMLGenerator.generateSlideLayoutXML(layoutType: .blank),
      to: "\(tempDir)/ppt/slideLayouts/slideLayout1.xml")
    try writeFile(
      ThemeXMLGenerator.generateSlideLayoutRels(),
      to: "\(tempDir)/ppt/slideLayouts/_rels/slideLayout1.xml.rels")

    // Write slides
    var imageFileIndex = 0
    for (slideIdx, slide) in presentation.slides.enumerated() {
      let slideNum = slideIdx + 1
      var slideRels: [SlideRelationship] = [
        SlideRelationship(
          rId: "rId1", type: OOXML.relTypeSlideLayout, target: "../slideLayouts/slideLayout1.xml")
      ]

      // Build image relationships for this slide (skipped images have no rId
      // and get no relationship)
      var slideImageIdx = 0
      var slideChartIdx = 0
      for element in slide.elements {
        if let image = element as? ImageElement, image.rId != nil {
          slideImageIdx += 1
          let mediaName = imageFiles[imageFileIndex].targetName
          slideRels.append(
            SlideRelationship(
              rId: "rIdImg\(slideImageIdx)",
              type: OOXML.relTypeImage,
              target: "../media/\(mediaName)"
            ))
          imageFileIndex += 1
        } else if let chart = element as? ChartElement {
          slideChartIdx += 1
          slideRels.append(
            SlideRelationship(
              rId: "rIdChart\(slideChartIdx)",
              type: OOXML.relTypeChart,
              target: "../charts/chart\(chart.chartIndex).xml"
            ))
        }
      }

      let slideXML = SlideXMLGenerator.generateSlideXML(
        slide: slide,
        presentation: presentation
      )
      try writeFile(slideXML, to: "\(tempDir)/ppt/slides/slide\(slideNum).xml")

      // Write slide rels
      let slideRelsXML = generateSlideRelsXML(relationships: slideRels)
      try writeFile(slideRelsXML, to: "\(tempDir)/ppt/slides/_rels/slide\(slideNum).xml.rels")
    }

    // Write presentation.xml
    try writeFile(
      generatePresentationXML(presentation: presentation), to: "\(tempDir)/ppt/presentation.xml")

    // Write presentation.xml.rels
    try writeFile(
      generatePresentationRelsXML(presentation: presentation),
      to: "\(tempDir)/ppt/_rels/presentation.xml.rels")

    // Write [Content_Types].xml
    try writeFile(
      generateContentTypesXML(
        presentation: presentation, imageFiles: imageFiles, chartCount: chartFiles.count),
      to: "\(tempDir)/[Content_Types].xml")

    // Write _rels/.rels
    try writeFile(generateRootRelsXML(), to: "\(tempDir)/_rels/.rels")

    // Write docProps/core.xml
    try writeFile(
      generateCorePropsXML(presentation: presentation), to: "\(tempDir)/docProps/core.xml")

    // Package as ZIP into a temp file next to the destination, then replace
    // atomically. The prior file is never removed before the new package is
    // fully produced.
    let zipResult = try runProcess(
      "/usr/bin/zip", arguments: ["-r", "-q", packagePath, "."], currentDirectory: tempDir)
    if zipResult.exitCode != 0 {
      throw PPTXError.zipFailed(zipResult.output)
    }

    try PathSafety.atomicReplace(at: outputPath, withItemAt: packagePath)

    return result
  }

  // MARK: - Numeric Validation

  /// Reject non-finite or absurdly large numeric inputs before they reach
  /// EMU conversion (Int(Double) traps on NaN/infinity/overflow).
  private static func validateNumericValues(presentation: Presentation) throws {
    func check(_ value: Double?, _ name: String, limit: Double = 1e6) throws {
      guard let v = value else { return }
      guard v.isFinite, abs(v) <= limit else {
        throw PPTXError.invalidValue("\(name) is not a finite value in a sane range: \(String(describing: value))")
      }
    }
    func checkPosition(_ position: ElementPosition, _ what: String) throws {
      try check(position.x, "\(what) x")
      try check(position.y, "\(what) y")
      try check(position.width, "\(what) width")
      try check(position.height, "\(what) height")
    }

    for slide in presentation.slides {
      if let bg = slide.background, case .gradient(_, _, let angle) = bg.type {
        try check(angle, "background gradient angle")
      }
      for element in slide.elements {
        if let text = element as? TextElement {
          try checkPosition(text.position, "text")
          try check(text.fontSize, "text font_size")
          try check(text.lineSpacing, "text line_spacing")
          try check(text.rotation, "text rotation")
        } else if let image = element as? ImageElement {
          try checkPosition(image.position, "image")
        } else if let shape = element as? ShapeElement {
          try checkPosition(shape.position, "shape")
          try check(shape.borderWidth, "shape border_width")
          try check(shape.textSize, "shape text_size")
          try check(shape.rotation, "shape rotation")
        } else if let table = element as? TableElement {
          try checkPosition(table.position, "table")
          try check(table.fontSize, "table font_size")
          for width in table.columnWidths ?? [] {
            try check(width, "table column width")
          }
        } else if let chart = element as? ChartElement {
          try checkPosition(chart.position, "chart")
          for series in chart.series {
            for value in series.values {
              guard value.isFinite else {
                throw PPTXError.invalidValue(
                  "chart series \"\(series.name)\" contains a non-finite value")
              }
            }
          }
        }
      }
    }
  }

  // MARK: - Presentation XML

  private static func generatePresentationXML(presentation: Presentation) -> String {
    var slideListXML = ""
    for (idx, _) in presentation.slides.enumerated() {
      let slideNum = idx + 1
      slideListXML += "    <p:sldId id=\"\(255 + slideNum)\" r:id=\"rIdSlide\(slideNum)\"/>\n"
    }

    return """
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <p:presentation xmlns:a="\(OOXML.nsA)" xmlns:r="\(OOXML.nsR)" xmlns:p="\(OOXML.nsP)" saveSubsetFonts="1">
        <p:sldMasterIdLst>
          <p:sldMasterId id="2147483648" r:id="rIdMaster1"/>
        </p:sldMasterIdLst>
        <p:sldIdLst>
      \(slideListXML)  </p:sldIdLst>
        <p:sldSz cx="\(presentation.slideWidth)" cy="\(presentation.slideHeight)" type="custom"/>
        <p:notesSz cx="\(presentation.slideHeight)" cy="\(presentation.slideWidth)"/>
      </p:presentation>
      """
  }

  // MARK: - Presentation Relationships

  private static func generatePresentationRelsXML(presentation: Presentation) -> String {
    var rels = ""
    rels +=
      "  <Relationship Id=\"rIdMaster1\" Type=\"\(OOXML.relTypeSlideMaster)\" Target=\"slideMasters/slideMaster1.xml\"/>\n"
    rels +=
      "  <Relationship Id=\"rIdTheme1\" Type=\"\(OOXML.relTypeTheme)\" Target=\"theme/theme1.xml\"/>\n"

    for (slideIdx, _) in presentation.slides.enumerated() {
      let num = slideIdx + 1
      rels +=
        "  <Relationship Id=\"rIdSlide\(num)\" Type=\"\(OOXML.relTypeSlide)\" Target=\"slides/slide\(num).xml\"/>\n"
    }

    return """
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="\(OOXML.nsRelationships)">
      \(rels)</Relationships>
      """
  }

  // MARK: - Content Types

  private static func generateContentTypesXML(
    presentation: Presentation, imageFiles: [(data: Data, targetName: String, ext: String)],
    chartCount: Int
  ) -> String {
    var overrides = ""
    overrides +=
      "  <Override PartName=\"/ppt/presentation.xml\" ContentType=\"\(OOXML.contentTypePresentationML)\"/>\n"
    overrides +=
      "  <Override PartName=\"/ppt/slideMasters/slideMaster1.xml\" ContentType=\"\(OOXML.contentTypeSlideMaster)\"/>\n"
    overrides +=
      "  <Override PartName=\"/ppt/slideLayouts/slideLayout1.xml\" ContentType=\"\(OOXML.contentTypeSlideLayout)\"/>\n"
    overrides +=
      "  <Override PartName=\"/ppt/theme/theme1.xml\" ContentType=\"\(OOXML.contentTypeTheme)\"/>\n"
    overrides +=
      "  <Override PartName=\"/docProps/core.xml\" ContentType=\"\(OOXML.contentTypeCoreProps)\"/>\n"

    for (slideIdx, _) in presentation.slides.enumerated() {
      let num = slideIdx + 1
      overrides +=
        "  <Override PartName=\"/ppt/slides/slide\(num).xml\" ContentType=\"\(OOXML.contentTypeSlide)\"/>\n"
    }

    if chartCount > 0 {
      for i in 1...chartCount {
        overrides +=
          "  <Override PartName=\"/ppt/charts/chart\(i).xml\" ContentType=\"\(OOXML.contentTypeChart)\"/>\n"
      }
    }

    // Collect unique image extensions
    var imageDefaults = ""
    var seenExts: Set<String> = []
    for img in imageFiles {
      let ext = img.ext.lowercased()
      if !seenExts.contains(ext) {
        seenExts.insert(ext)
        imageDefaults +=
          "  <Default Extension=\"\(ext)\" ContentType=\"\(imageContentType(for: ext))\"/>\n"
      }
    }

    return """
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Types xmlns="\(OOXML.nsContentTypes)">
        <Default Extension="rels" ContentType="\(OOXML.contentTypeRels)"/>
        <Default Extension="xml" ContentType="\(OOXML.contentTypeXML)"/>
      \(imageDefaults)\(overrides)</Types>
      """
  }

  // MARK: - Root Relationships

  private static func generateRootRelsXML() -> String {
    """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="\(OOXML.nsRelationships)">
      <Relationship Id="rId1" Type="\(OOXML.relTypeOfficeDoc)" Target="ppt/presentation.xml"/>
      <Relationship Id="rId2" Type="\(OOXML.relTypeCoreProps)" Target="docProps/core.xml"/>
    </Relationships>
    """
  }

  // MARK: - Core Properties

  private static func generateCorePropsXML(presentation: Presentation) -> String {
    let dateStr = ISO8601DateFormatter().string(from: Date())
    return """
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <cp:coreProperties xmlns:cp="\(OOXML.nsCoreProps)" xmlns:dc="\(OOXML.nsDC)" xmlns:dcterms="\(OOXML.nsDCTerms)" xmlns:xsi="\(OOXML.nsXSI)">
        <dc:title>\(xmlEscape(presentation.title))</dc:title>
        <dc:creator>Osaurus Presentation Plugin</dc:creator>
        <dcterms:created xsi:type="dcterms:W3CDTF">\(dateStr)</dcterms:created>
        <dcterms:modified xsi:type="dcterms:W3CDTF">\(dateStr)</dcterms:modified>
      </cp:coreProperties>
      """
  }

  // MARK: - Slide Relationships XML

  private static func generateSlideRelsXML(relationships: [SlideRelationship]) -> String {
    var rels = ""
    for rel in relationships {
      rels += "  <Relationship Id=\"\(rel.rId)\" Type=\"\(rel.type)\" Target=\"\(rel.target)\"/>\n"
    }
    return """
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="\(OOXML.nsRelationships)">
      \(rels)</Relationships>
      """
  }
}

// MARK: - Errors

enum PPTXError: Error, CustomStringConvertible {
  case zipFailed(String)
  case unzipFailed(String)
  case invalidFile(String)
  case invalidDestination(String)
  case invalidValue(String)

  var description: String {
    switch self {
    case .zipFailed(let msg): return "ZIP packaging failed: \(msg)"
    case .unzipFailed(let msg): return "Unzip failed: \(msg)"
    case .invalidFile(let msg): return "Invalid PPTX file: \(msg)"
    case .invalidDestination(let msg): return "Invalid destination: \(msg)"
    case .invalidValue(let msg): return "Invalid value: \(msg)"
    }
  }
}
