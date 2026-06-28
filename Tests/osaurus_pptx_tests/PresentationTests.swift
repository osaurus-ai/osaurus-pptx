import Foundation
import Testing

@testable import osaurus_pptx

// MARK: - Unit Conversion & Helpers

@Suite("Unit Conversion & Helpers")
struct UnitConversionTests {

  @Test("inchesToEMU: 1 inch = 914400")
  func inchesToEMU() {
    #expect(Units.inchesToEMU(1.0) == 914400)
    #expect(Units.inchesToEMU(2.5) == 2_286_000)
    #expect(Units.inchesToEMU(0.0) == 0)
  }

  @Test("pointsToEMU: 1pt = 12700")
  func pointsToEMU() {
    #expect(Units.pointsToEMU(1.0) == 12700)
    #expect(Units.pointsToEMU(10.0) == 127000)
  }

  @Test("pointsToHundredths: 18pt = 1800")
  func pointsToHundredths() {
    #expect(Units.pointsToHundredths(18.0) == 1800)
    #expect(Units.pointsToHundredths(12.0) == 1200)
  }

  @Test("xmlEscape handles special characters")
  func xmlEscapeTest() {
    #expect(xmlEscape("&") == "&amp;")
    #expect(xmlEscape("<") == "&lt;")
    #expect(xmlEscape(">") == "&gt;")
    #expect(xmlEscape("\"") == "&quot;")
    #expect(xmlEscape("'") == "&apos;")
    #expect(
      xmlEscape("a & b < c > d \"e\" 'f'") == "a &amp; b &lt; c &gt; d &quot;e&quot; &apos;f&apos;")
  }

  @Test("jsonEscape handles special characters")
  func jsonEscapeTest() {
    #expect(jsonEscape("\\") == "\\\\")
    #expect(jsonEscape("\"") == "\\\"")
    #expect(jsonEscape("\n") == "\\n")
    #expect(jsonEscape("\r") == "\\r")
    #expect(jsonEscape("\t") == "\\t")
    #expect(jsonEscape("line1\nline2") == "line1\\nline2")
  }

  @Test("parseHexColor handles various formats")
  func parseHexColorTest() {
    #expect(parseHexColor("FF0000") == "FF0000")
    #expect(parseHexColor("#FF0000") == "FF0000")
    #expect(parseHexColor("abc") == "AABBCC")
    #expect(parseHexColor("#abc") == "AABBCC")
    #expect(parseHexColor("invalid") == "000000")
    #expect(parseHexColor("") == "000000")
  }

  @Test("jsonSuccess produces valid JSON")
  func jsonSuccessTest() {
    let result = jsonSuccess(["key": "value", "num": 42])
    #expect(result.contains("\"key\": \"value\""))
    #expect(result.contains("\"num\": 42"))
    #expect(result.hasPrefix("{"))
    #expect(result.hasSuffix("}"))
  }

  @Test("jsonError produces valid error JSON")
  func jsonErrorTest() {
    let result = jsonError("something went wrong")
    #expect(result == "{\"error\": \"something went wrong\"}")
  }
}

// MARK: - Model Construction

@Suite("Model Construction")
struct ModelTests {

  @Test("Presentation init with widescreen")
  func presentationWidescreen() {
    let p = Presentation(title: "Test", layout: .widescreen)
    #expect(p.title == "Test")
    #expect(p.slideWidth == SlideDimensions.wideWidth)
    #expect(p.slideHeight == SlideDimensions.wideHeight)
    #expect(p.slides.isEmpty)
    // Verify exact standard 16:9 dimensions (13+1/3 inches x 7.5 inches)
    #expect(SlideDimensions.wideWidth == 12_192_000)
    #expect(SlideDimensions.wideHeight == 6_858_000)
  }

  @Test("Presentation init with standard")
  func presentationStandard() {
    let p = Presentation(title: "Standard", layout: .standard)
    #expect(p.slideWidth == SlideDimensions.standardWidth)
    #expect(p.slideHeight == SlideDimensions.standardHeight)
  }

  @Test("Presentation init with custom size")
  func presentationCustom() {
    let p = Presentation(title: "Custom", layout: .custom(width: 10.0, height: 5.0))
    #expect(p.slideWidth == Units.inchesToEMU(10.0))
    #expect(p.slideHeight == Units.inchesToEMU(5.0))
  }

  @Test("Slide defaults to blank layout")
  func slideDefaults() {
    let s = Slide()
    #expect(s.layoutType == .blank)
    #expect(s.elements.isEmpty)
    #expect(s.background == nil)
  }

  @Test("TextElement stores all formatting properties")
  func textElementFormatting() {
    let pos = ElementPosition(x: 1.0, y: 2.0, width: 8.0, height: 1.5)
    let t = TextElement(
      text: "Hello",
      position: pos,
      fontSize: 24,
      fontFace: "Arial",
      fontColor: "FF0000",
      bold: true,
      italic: true,
      underline: true,
      alignment: .center,
      verticalAlignment: .middle,
      lineSpacing: 28.0,
      bullets: true,
      wordWrap: false,
      rotation: 45.0
    )
    #expect(t.text == "Hello")
    #expect(t.fontSize == 24)
    #expect(t.fontFace == "Arial")
    #expect(t.fontColor == "FF0000")
    #expect(t.bold == true)
    #expect(t.italic == true)
    #expect(t.underline == true)
    #expect(t.alignment == .center)
    #expect(t.verticalAlignment == .middle)
    #expect(t.lineSpacing == 28.0)
    #expect(t.bullets == true)
    #expect(t.wordWrap == false)
    #expect(t.rotation == 45.0)
  }

  @Test("ShapeType.ooxmlPreset mapping")
  func shapeTypePresets() {
    #expect(ShapeType.rect.ooxmlPreset == "rect")
    #expect(ShapeType.roundRect.ooxmlPreset == "roundRect")
    #expect(ShapeType.ellipse.ooxmlPreset == "ellipse")
    #expect(ShapeType.lightning.ooxmlPreset == "lightningBolt")
    #expect(ShapeType.rightArrow.ooxmlPreset == "rightArrow")
    #expect(ShapeType.heart.ooxmlPreset == "heart")
  }

  @Test("ThemePresets.named resolves correctly")
  func themePresetsNamed() {
    #expect(ThemePresets.named("corporate").name == "Corporate")
    #expect(ThemePresets.named("creative").name == "Creative")
    #expect(ThemePresets.named("minimal").name == "Minimal")
    #expect(ThemePresets.named("dark").name == "Dark")
    #expect(ThemePresets.named("unknown").name == "Modern")
    #expect(ThemePresets.named("CORPORATE").name == "Corporate")
  }

  @Test("ElementPosition EMU computed properties")
  func elementPositionEMU() {
    let pos = ElementPosition(x: 1.0, y: 2.0, width: 3.0, height: 4.0)
    #expect(pos.xEMU == 914400)
    #expect(pos.yEMU == 1_828_800)
    #expect(pos.widthEMU == 2_743_200)
    #expect(pos.heightEMU == 3_657_600)
  }
}

// MARK: - Path Validation

@Suite("Path Validation")
struct PathValidationTests {

  @Test("Absolute path with no working directory is allowed")
  func absoluteNoWorkDir() {
    let result = validatePath("/tmp/test.pptx", workingDirectory: nil)
    if case .success(let p) = result {
      #expect(p == "/tmp/test.pptx")
    } else {
      Issue.record("Expected success")
    }
  }

  @Test("Relative path with no working directory is error")
  func relativeNoWorkDir() {
    let result = validatePath("test.pptx", workingDirectory: nil)
    if case .failure(let msg) = result {
      #expect(msg.contains("No working directory"))
    } else {
      Issue.record("Expected failure")
    }
  }

  @Test("Relative path resolved within working directory")
  func relativeWithWorkDir() {
    let result = validatePath("output/test.pptx", workingDirectory: "/Users/test/project")
    if case .success(let p) = result {
      #expect(p.hasPrefix("/Users/test/project"))
      #expect(p.contains("output/test.pptx"))
    } else {
      Issue.record("Expected success")
    }
  }

  @Test("Path traversal is blocked")
  func pathTraversalBlocked() {
    let result = validatePath("../../../etc/passwd", workingDirectory: "/Users/test/project")
    if case .failure(let msg) = result {
      #expect(msg.contains("outside"))
    } else {
      Issue.record("Expected failure for path traversal")
    }
  }

  @Test("Absolute path outside working directory is blocked")
  func absoluteOutsideWorkDir() {
    let result = validatePath("/etc/passwd", workingDirectory: "/Users/test/project")
    if case .failure(let msg) = result {
      #expect(msg.contains("outside"))
    } else {
      Issue.record("Expected failure for path outside workdir")
    }
  }
}

// MARK: - Tool Execution

@Suite("Tool Execution")
struct ToolExecutionTests {

  // Helper to run a tool and parse result
  private func parseJSON(_ json: String) -> [String: Any]? {
    guard let data = json.data(using: .utf8),
      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }
    return obj
  }

  @Test("create_presentation returns valid JSON with presentation_id")
  func createPresentation() {
    var presentations: [String: Presentation] = [:]
    let tool = CreatePresentationTool()
    let result = tool.run(args: "{\"title\": \"Test Deck\"}", presentations: &presentations)
    let json = parseJSON(result)
    #expect(json?["presentation_id"] != nil)
    #expect(json?["title"] as? String == "Test Deck")
    #expect(json?["error"] == nil)
    #expect(presentations.count == 1)
  }

  @Test("create_presentation with custom layout and theme")
  func createPresentationCustom() {
    var presentations: [String: Presentation] = [:]
    let tool = CreatePresentationTool()
    let result = tool.run(
      args: "{\"title\": \"Custom\", \"size\": \"4:3\", \"theme\": \"dark\"}",
      presentations: &presentations)
    let json = parseJSON(result)
    #expect(json?["theme"] as? String == "Dark")
    let pres = presentations.values.first!
    #expect(pres.slideWidth == SlideDimensions.standardWidth)
  }

  @Test("add_slide returns slide_number=1 with valid layout")
  func addSlide() {
    var presentations: [String: Presentation] = [:]
    let createTool = CreatePresentationTool()
    let createResult = createTool.run(args: "{\"title\": \"Test\"}", presentations: &presentations)
    let presId = parseJSON(createResult)?["presentation_id"] as! String

    let slideTool = AddSlideTool()
    let result = slideTool.run(
      args: "{\"presentation_id\": \"\(presId)\", \"layout\": \"title\"}",
      presentations: &presentations)
    let json = parseJSON(result)
    #expect(json?["slide_number"] as? Int == 1)
    #expect(json?["layout"] as? String == "title")
  }

  @Test("add_slide with invalid presentation_id returns error")
  func addSlideInvalidId() {
    var presentations: [String: Presentation] = [:]
    let tool = AddSlideTool()
    let result = tool.run(
      args: "{\"presentation_id\": \"nonexistent\"}", presentations: &presentations)
    let json = parseJSON(result)
    #expect(json?["ok"] as? Bool == false)
    #expect(json?["kind"] as? String == "not_found")
    #expect(json?["error"] == nil)
  }

  @Test("add_text with all formatting options")
  func addTextFormatted() {
    var presentations: [String: Presentation] = [:]
    let (presId, _) = createPresentationWithSlide(&presentations)

    let tool = AddTextTool()
    let args = """
      {"presentation_id": "\(presId)", "slide_number": 1, "text": "Hello World",
       "x": 2.0, "y": 1.5, "width": 6.0, "height": 2.0,
       "font_size": 24, "font_face": "Arial", "font_color": "FF0000",
       "bold": true, "italic": true, "underline": true,
       "alignment": "center", "vertical_alignment": "middle",
       "line_spacing": 28, "bullets": true, "word_wrap": false, "rotation": 45}
      """
    let result = tool.run(args: args, presentations: &presentations)
    let json = parseJSON(result)
    #expect(json?["element_id"] != nil)
    #expect(json?["element_type"] as? String == "text")

    let slide = presentations[presId]!.slides[0]
    let textEl = slide.elements[0] as! TextElement
    #expect(textEl.text == "Hello World")
    #expect(textEl.bold == true)
    #expect(textEl.fontSize == 24)
    #expect(textEl.alignment == .center)
  }

  @Test("add_text with invalid slide number returns error")
  func addTextInvalidSlide() {
    var presentations: [String: Presentation] = [:]
    let (presId, _) = createPresentationWithSlide(&presentations)

    let tool = AddTextTool()
    let result = tool.run(
      args: "{\"presentation_id\": \"\(presId)\", \"slide_number\": 99, \"text\": \"test\"}",
      presentations: &presentations)
    let json = parseJSON(result)
    #expect(json?["ok"] as? Bool == false)
    #expect(json?["kind"] as? String == "invalid_args")
  }

  @Test("add_shape with various shape types")
  func addShape() {
    var presentations: [String: Presentation] = [:]
    let (presId, _) = createPresentationWithSlide(&presentations)

    let tool = AddShapeTool()
    let result = tool.run(
      args: """
        {"presentation_id": "\(presId)", "slide_number": 1, "shape_type": "ellipse",
         "fill_color": "4472C4", "border_color": "333333", "text": "Inside shape"}
        """, presentations: &presentations)
    let json = parseJSON(result)
    #expect(json?["element_type"] as? String == "shape")
    #expect(json?["shape_type"] as? String == "ellipse")

    let slide = presentations[presId]!.slides[0]
    let shape = slide.elements[0] as! ShapeElement
    #expect(shape.shapeType == .ellipse)
    #expect(shape.fillColor == "4472C4")
    #expect(shape.text == "Inside shape")
  }

  @Test("add_shape with invalid type returns error")
  func addShapeInvalidType() {
    var presentations: [String: Presentation] = [:]
    let (presId, _) = createPresentationWithSlide(&presentations)

    let tool = AddShapeTool()
    let result = tool.run(
      args:
        "{\"presentation_id\": \"\(presId)\", \"slide_number\": 1, \"shape_type\": \"nonexistent\"}",
      presentations: &presentations)
    let json = parseJSON(result)
    #expect(json?["ok"] as? Bool == false)
    #expect(json?["kind"] as? String == "invalid_args")
    #expect((json?["message"] as? String)?.contains("Invalid shape type") == true)
  }

  @Test("add_table with header and data rows")
  func addTable() {
    var presentations: [String: Presentation] = [:]
    let (presId, _) = createPresentationWithSlide(&presentations)

    let tool = AddTableTool()
    let result = tool.run(
      args: """
        {"presentation_id": "\(presId)", "slide_number": 1,
         "rows": [["Name", "Age"], ["Alice", "30"], ["Bob", "25"]],
         "has_header": true}
        """, presentations: &presentations)
    let json = parseJSON(result)
    #expect(json?["element_type"] as? String == "table")
    #expect(json?["row_count"] as? Int == 3)
    #expect(json?["column_count"] as? Int == 2)
  }

  @Test("add_chart with bar chart data")
  func addChart() {
    var presentations: [String: Presentation] = [:]
    let (presId, _) = createPresentationWithSlide(&presentations)

    let tool = AddChartTool()
    let result = tool.run(
      args: """
        {"presentation_id": "\(presId)", "slide_number": 1,
         "chart_type": "bar", "categories": ["Q1", "Q2", "Q3"],
         "series": [{"name": "Revenue", "values": [100, 200, 300]}],
         "title": "Sales"}
        """, presentations: &presentations)
    let json = parseJSON(result)
    #expect(json?["element_type"] as? String == "chart")
    #expect(json?["chart_type"] as? String == "bar")
  }

  @Test("set_slide_background solid and gradient")
  func setSlideBackground() {
    var presentations: [String: Presentation] = [:]
    let (presId, _) = createPresentationWithSlide(&presentations)

    let tool = SetSlideBackgroundTool()

    // Solid
    let solidResult = tool.run(
      args: "{\"presentation_id\": \"\(presId)\", \"slide_number\": 1, \"color\": \"1F3864\"}",
      presentations: &presentations)
    let solidJSON = parseJSON(solidResult)
    #expect(solidJSON?["error"] == nil)
    let slide = presentations[presId]!.slides[0]
    if case .solid(let c) = slide.background!.type {
      #expect(c == "1F3864")
    } else {
      Issue.record("Expected solid background")
    }

    // Gradient
    let gradResult = tool.run(
      args: """
        {"presentation_id": "\(presId)", "slide_number": 1,
         "gradient_color1": "FF0000", "gradient_color2": "0000FF", "gradient_angle": 90}
        """, presentations: &presentations)
    let gradJSON = parseJSON(gradResult)
    #expect(gradJSON?["error"] == nil)
    if case .gradient(let c1, let c2, let angle) = slide.background!.type {
      #expect(c1 == "FF0000")
      #expect(c2 == "0000FF")
      #expect(angle == 90.0)
    } else {
      Issue.record("Expected gradient background")
    }
  }

  @Test("delete_slide removes slide and returns remaining count")
  func deleteSlide() {
    var presentations: [String: Presentation] = [:]
    let (presId, _) = createPresentationWithSlide(&presentations)

    // Add a second slide
    let slideTool = AddSlideTool()
    _ = slideTool.run(args: "{\"presentation_id\": \"\(presId)\"}", presentations: &presentations)
    #expect(presentations[presId]!.slides.count == 2)

    let tool = DeleteSlideTool()
    let result = tool.run(
      args: "{\"presentation_id\": \"\(presId)\", \"slide_number\": 1}",
      presentations: &presentations)
    let json = parseJSON(result)
    #expect(json?["remaining_slides"] as? Int == 1)
    #expect(presentations[presId]!.slides.count == 1)
  }

  @Test("get_presentation_info basic and detailed modes")
  func getPresentationInfo() {
    var presentations: [String: Presentation] = [:]
    let (presId, _) = createPresentationWithSlide(&presentations)

    // Add text to slide
    let textTool = AddTextTool()
    _ = textTool.run(
      args: "{\"presentation_id\": \"\(presId)\", \"slide_number\": 1, \"text\": \"Hello\"}",
      presentations: &presentations)

    let tool = GetPresentationInfoTool()

    // Basic
    let basicResult = tool.run(
      args: "{\"presentation_id\": \"\(presId)\"}", presentations: &presentations)
    let basicJSON = parseJSON(basicResult)
    #expect(basicJSON?["slide_count"] as? Int == 1)
    #expect(basicJSON?["title"] != nil)

    // Detailed
    let detailResult = tool.run(
      args: "{\"presentation_id\": \"\(presId)\", \"include_details\": true}",
      presentations: &presentations)
    let detailJSON = parseJSON(detailResult)
    #expect(detailJSON?["slide_count"] as? Int == 1)
    // The detailed response includes slides array with element info
    #expect(detailJSON?["slides"] != nil)
  }

  @Test("Full workflow: create → add_slide → add_text → add_shape → get_info")
  func fullWorkflow() {
    var presentations: [String: Presentation] = [:]

    // Create
    let createTool = CreatePresentationTool()
    let createResult = createTool.run(
      args: "{\"title\": \"Workflow Test\", \"theme\": \"corporate\"}",
      presentations: &presentations)
    let presId = parseJSON(createResult)?["presentation_id"] as! String

    // Add slide
    let slideTool = AddSlideTool()
    _ = slideTool.run(
      args: "{\"presentation_id\": \"\(presId)\", \"layout\": \"title_content\"}",
      presentations: &presentations)

    // Add text
    let textTool = AddTextTool()
    _ = textTool.run(
      args:
        "{\"presentation_id\": \"\(presId)\", \"slide_number\": 1, \"text\": \"Title Text\", \"bold\": true, \"font_size\": 36}",
      presentations: &presentations)

    // Add shape
    let shapeTool = AddShapeTool()
    _ = shapeTool.run(
      args:
        "{\"presentation_id\": \"\(presId)\", \"slide_number\": 1, \"shape_type\": \"rect\", \"fill_color\": \"4472C4\"}",
      presentations: &presentations)

    // Verify
    let pres = presentations[presId]!
    #expect(pres.slides.count == 1)
    #expect(pres.slides[0].elements.count == 2)
    #expect(pres.theme.name == "Corporate")

    let infoTool = GetPresentationInfoTool()
    let info = infoTool.run(
      args: "{\"presentation_id\": \"\(presId)\", \"include_details\": true}",
      presentations: &presentations)
    let infoJSON = parseJSON(info)
    #expect(infoJSON?["slide_count"] as? Int == 1)
    #expect(infoJSON?["theme"] as? String == "Corporate")
  }

  // Helper
  private func createPresentationWithSlide(_ presentations: inout [String: Presentation]) -> (
    String, String
  ) {
    let createTool = CreatePresentationTool()
    let result = createTool.run(args: "{\"title\": \"Test\"}", presentations: &presentations)
    let json = parseJSON(result)!
    let presId = json["presentation_id"] as! String

    let slideTool = AddSlideTool()
    let slideResult = slideTool.run(
      args: "{\"presentation_id\": \"\(presId)\"}", presentations: &presentations)
    let slideJSON = parseJSON(slideResult)!
    let slideId = slideJSON["slide_id"] as! String

    return (presId, slideId)
  }
}

// MARK: - XML Generation

@Suite("XML Generation")
struct XMLGenerationTests {

  @Test("ThemeXMLGenerator contains correct namespace and color values")
  func themeXML() {
    let theme = ThemePresets.corporate
    let xml = ThemeXMLGenerator.generateThemeXML(theme: theme)
    #expect(xml.contains("xmlns:a=\"\(OOXML.nsA)\""))
    #expect(xml.contains("name=\"Corporate\""))
    #expect(xml.contains(parseHexColor(theme.primaryColor)))
    #expect(xml.contains(parseHexColor(theme.secondaryColor)))
    #expect(xml.contains(theme.fontHeading))
    #expect(xml.contains(theme.fontBody))
  }

  @Test("SlideXMLGenerator generates empty slide")
  func emptySlideXML() {
    let slide = Slide()
    let pres = Presentation(title: "Test")
    let xml = SlideXMLGenerator.generateSlideXML(slide: slide, presentation: pres)
    #expect(xml.contains("xmlns:p=\"\(OOXML.nsP)\""))
    #expect(xml.contains("<p:spTree>"))
    #expect(xml.contains("</p:sld>"))
  }

  @Test("generateTextBoxXML contains text content and font settings")
  func textBoxXML() {
    let pos = ElementPosition(x: 1.0, y: 1.0, width: 8.0, height: 1.5)
    let text = TextElement(
      text: "Sample Text", position: pos, fontSize: 24, fontFace: "Arial", fontColor: "FF0000",
      bold: true)
    let xml = SlideXMLGenerator.generateTextBoxXML(text, shapeId: 3)
    #expect(xml.contains("Sample Text"))
    #expect(xml.contains("sz=\"2400\""))  // 24 * 100
    #expect(xml.contains("typeface=\"Arial\""))
    #expect(xml.contains("val=\"FF0000\""))
    #expect(xml.contains("b=\"1\""))
    #expect(xml.contains("txBox=\"1\""))
  }

  @Test("generateShapeXML contains shape preset and fill")
  func shapeXML() {
    let pos = ElementPosition(x: 2.0, y: 2.0, width: 3.0, height: 2.0)
    let shape = ShapeElement(
      shapeType: .roundRect, position: pos, fillColor: "4472C4", text: "Click Me",
      textColor: "FFFFFF")
    let xml = SlideXMLGenerator.generateShapeXML(shape, shapeId: 4)
    #expect(xml.contains("prst=\"roundRect\""))
    #expect(xml.contains("val=\"4472C4\""))
    #expect(xml.contains("Click Me"))
    #expect(xml.contains("val=\"FFFFFF\""))
  }

  @Test("ChartXMLGenerator generates bar chart with correct series data")
  func barChartXML() {
    let pos = ElementPosition(x: 1.0, y: 1.0, width: 8.0, height: 5.0)
    let chart = ChartElement(
      chartType: .bar,
      position: pos,
      chartTitle: "Sales Data",
      series: [ChartSeries(name: "Revenue", values: [100, 200, 300], color: "4472C4")],
      categories: ["Q1", "Q2", "Q3"]
    )
    let xml = ChartXMLGenerator.generateChartXML(chart: chart)
    #expect(xml.contains("xmlns:c=\"\(OOXML.nsChart)\""))
    #expect(xml.contains("Sales Data"))
    #expect(xml.contains("Revenue"))
    #expect(xml.contains("<c:v>100.0</c:v>"))
    #expect(xml.contains("<c:v>200.0</c:v>"))
    #expect(xml.contains("<c:v>300.0</c:v>"))
    #expect(xml.contains("barDir"))
    #expect(xml.contains("Q1"))
    #expect(xml.contains("Q2"))
  }

  @Test("Column chart uses c:barChart element, not c:colChart")
  func columnChartUsesBarChartElement() {
    let pos = ElementPosition(x: 1.0, y: 1.0, width: 8.0, height: 5.0)
    let chart = ChartElement(
      chartType: .column,
      position: pos,
      chartTitle: "Column Data",
      series: [ChartSeries(name: "Sales", values: [10, 20, 30], color: nil)],
      categories: ["A", "B", "C"]
    )
    let xml = ChartXMLGenerator.generateChartXML(chart: chart)
    #expect(xml.contains("<c:barChart>"))
    #expect(xml.contains("</c:barChart>"))
    #expect(xml.contains("<c:barDir val=\"col\"/>"))
    #expect(!xml.contains("<c:colChart>"))
    #expect(!xml.contains("</c:colChart>"))
  }

  @Test("Chart without title emits exactly one autoTitleDeleted element")
  func chartWithoutTitleNoDuplicate() {
    let pos = ElementPosition(x: 1.0, y: 1.0, width: 8.0, height: 5.0)
    let chart = ChartElement(
      chartType: .bar,
      position: pos,
      chartTitle: nil,
      series: [ChartSeries(name: "Data", values: [1, 2], color: nil)],
      categories: ["X", "Y"]
    )
    let xml = ChartXMLGenerator.generateChartXML(chart: chart)
    let count = xml.components(separatedBy: "autoTitleDeleted").count - 1
    #expect(count == 1)
    #expect(xml.contains("<c:autoTitleDeleted val=\"1\"/>"))
    #expect(!xml.contains("<c:title>"))
  }

  @Test("generateBackgroundXML for solid and gradient")
  func backgroundXML() {
    // Solid
    let solidBg = SlideBackground(type: .solid(color: "1F3864"))
    let solidXML = SlideXMLGenerator.generateBackgroundXML(solidBg)
    #expect(solidXML.contains("solidFill"))
    #expect(solidXML.contains("1F3864"))

    // Gradient
    let gradBg = SlideBackground(type: .gradient(color1: "FF0000", color2: "0000FF", angle: 270))
    let gradXML = SlideXMLGenerator.generateBackgroundXML(gradBg)
    #expect(gradXML.contains("gradFill"))
    #expect(gradXML.contains("FF0000"))
    #expect(gradXML.contains("0000FF"))

    // None
    let noneXML = SlideXMLGenerator.generateBackgroundXML(nil)
    #expect(noneXML.isEmpty)
  }
}

// MARK: - PPTX Write & Read Round-Trip

@Suite("PPTX Round-Trip")
struct PPTXRoundTripTests {

  private func tempPath() -> String {
    NSTemporaryDirectory() + "osaurus_test_\(UUID().uuidString).pptx"
  }

  @Test("Write empty presentation creates valid ZIP file")
  func writeEmptyPresentation() throws {
    let pres = Presentation(title: "Empty Test")
    pres.slides.append(Slide())  // Need at least one slide for valid PPTX
    let path = tempPath()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try PPTXWriter.write(presentation: pres, to: path)
    #expect(FileManager.default.fileExists(atPath: path))

    // Verify it's a valid ZIP by checking file header
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    #expect(data.count > 0)
    // ZIP files start with PK (0x50 0x4B)
    #expect(data[0] == 0x50)
    #expect(data[1] == 0x4B)
  }

  @Test("Write presentation with text creates file")
  func writeWithText() throws {
    let pres = Presentation(title: "Text Test")
    let slide = Slide()
    let pos = ElementPosition(x: 1.0, y: 1.0, width: 8.0, height: 1.5)
    let text = TextElement(text: "Hello World", position: pos, fontSize: 24, bold: true)
    slide.elements.append(text)
    pres.slides.append(slide)

    let path = tempPath()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try PPTXWriter.write(presentation: pres, to: path)
    #expect(FileManager.default.fileExists(atPath: path))
  }

  @Test("Write then read back preserves title, slide count, and text content")
  func writeReadRoundTrip() throws {
    let pres = Presentation(title: "Round Trip Test")
    let slide = Slide()
    let pos = ElementPosition(x: 1.0, y: 1.0, width: 8.0, height: 1.5)
    let text = TextElement(
      text: "Preserved Text", position: pos, fontSize: 20, fontFace: "Calibri", fontColor: "333333",
      bold: true)
    slide.elements.append(text)
    pres.slides.append(slide)

    let path = tempPath()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try PPTXWriter.write(presentation: pres, to: path)

    let readPres = try PPTXReader.read(from: path)
    #expect(readPres.title == "Round Trip Test")
    #expect(readPres.slides.count == 1)

    // Check text was preserved
    let readSlide = readPres.slides[0]
    let textElements = readSlide.elements.compactMap { $0 as? TextElement }
    #expect(textElements.count >= 1)
    #expect(textElements.first?.text == "Preserved Text")
    #expect(textElements.first?.bold == true)
    #expect(textElements.first?.fontSize == 20)
  }

  @Test("Write with multiple element types and read back")
  func writeMultipleElements() throws {
    let pres = Presentation(title: "Multi Element Test")
    let slide = Slide()

    // Add text
    let textPos = ElementPosition(x: 1.0, y: 0.5, width: 8.0, height: 1.0)
    let text = TextElement(text: "Title Here", position: textPos, fontSize: 32, bold: true)
    slide.elements.append(text)

    // Add shape (shapes are written as sp, so reader can parse them)
    let shapePos = ElementPosition(x: 2.0, y: 2.0, width: 3.0, height: 2.0)
    let shape = ShapeElement(
      shapeType: .rect, position: shapePos, fillColor: "4472C4", text: "Box Text")
    slide.elements.append(shape)

    // Add table
    let tablePos = ElementPosition(x: 1.0, y: 5.0, width: 10.0, height: 2.0)
    let table = TableElement(rows: [["Header1", "Header2"], ["A", "B"]], position: tablePos)
    slide.elements.append(table)

    pres.slides.append(slide)

    let path = tempPath()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try PPTXWriter.write(presentation: pres, to: path)
    #expect(FileManager.default.fileExists(atPath: path))

    let readPres = try PPTXReader.read(from: path)
    #expect(readPres.slides.count == 1)

    // Reader parses text from sp elements (both text boxes and shapes with text)
    let readSlide = readPres.slides[0]
    let textElements = readSlide.elements.compactMap { $0 as? TextElement }
    let allTexts = textElements.map { $0.text }
    #expect(allTexts.contains("Title Here"))
    #expect(allTexts.contains("Box Text"))
  }
}
