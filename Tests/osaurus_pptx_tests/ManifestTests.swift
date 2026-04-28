import Foundation
import Testing

@testable import osaurus_pptx

@Suite("Plugin Manifest")
struct ManifestTests {

  private enum ManifestError: Error {
    case entryPointFailed
    case nilManifest
    case invalidJSON
  }

  private func loadManifest() throws -> [String: Any] {
    guard let apiPtr = osaurus_plugin_entry() else {
      throw ManifestError.entryPointFailed
    }

    let fnPtrSize = MemoryLayout<UnsafeRawPointer?>.stride
    let initPtr = apiPtr.load(
      fromByteOffset: fnPtrSize,
      as: (@convention(c) () -> UnsafeMutableRawPointer?).self)
    let ctx = initPtr()

    let getManifestPtr = apiPtr.load(
      fromByteOffset: fnPtrSize * 3,
      as: (@convention(c) (UnsafeMutableRawPointer?) -> UnsafePointer<CChar>?).self)
    guard let cStr = getManifestPtr(ctx) else {
      throw ManifestError.nilManifest
    }
    let jsonString = String(cString: cStr)

    let freeStringPtr = apiPtr.load(
      fromByteOffset: 0,
      as: (@convention(c) (UnsafePointer<CChar>?) -> Void).self)
    freeStringPtr(cStr)

    let destroyPtr = apiPtr.load(
      fromByteOffset: fnPtrSize * 2,
      as: (@convention(c) (UnsafeMutableRawPointer?) -> Void).self)
    destroyPtr(ctx)

    guard let data = jsonString.data(using: .utf8),
      let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw ManifestError.invalidJSON
    }
    return manifest
  }

  private func toolMap(from manifest: [String: Any]) -> [String: [String: Any]] {
    let capabilities = manifest["capabilities"] as? [String: Any]
    let tools = capabilities?["tools"] as? [[String: Any]] ?? []
    return Dictionary(
      uniqueKeysWithValues: tools.compactMap { tool -> (String, [String: Any])? in
        guard let id = tool["id"] as? String else { return nil }
        return (id, tool)
      })
  }

  @Test("manifest has correct plugin identity")
  func pluginIdentity() throws {
    let manifest = try loadManifest()
    #expect(manifest["plugin_id"] as? String == "osaurus.pptx")
    #expect(manifest["name"] as? String == "Osaurus PPTX")
  }

  @Test("manifest declares expected presentation tools")
  func toolIDs() throws {
    let map = try toolMap(from: loadManifest())
    #expect(
      Set(map.keys) == [
        "create_presentation", "add_slide", "add_text", "add_image", "add_shape", "add_table",
        "add_chart", "set_slide_background", "delete_slide", "read_presentation",
        "get_presentation_info", "save_presentation",
      ])
  }

  @Test("file and destructive tools require approval")
  func permissionPolicies() throws {
    let map = try toolMap(from: loadManifest())
    for id in ["add_image", "delete_slide", "read_presentation", "save_presentation"] {
      #expect(map[id]?["permission_policy"] as? String == "ask", "Tool '\(id)' should ask")
    }

    for id in [
      "create_presentation", "add_slide", "add_text", "add_shape", "add_table", "add_chart",
      "set_slide_background", "get_presentation_info",
    ] {
      #expect(map[id]?["permission_policy"] as? String == "auto", "Tool '\(id)' should be auto")
    }
  }

  @Test("save_presentation advertises dry-run and overwrite controls")
  func savePresentationControls() throws {
    let map = try toolMap(from: loadManifest())
    let save = try #require(map["save_presentation"])
    let params = save["parameters"] as? [String: Any]
    let properties = params?["properties"] as? [String: Any]
    let required = Set(params?["required"] as? [String] ?? [])

    #expect(required == ["presentation_id", "path"])
    #expect(properties?["overwrite"] != nil)
    #expect(properties?["dry_run"] != nil)
    #expect((save["description"] as? String ?? "").lowercased().contains("pptx"))
  }

  @Test("content creation tools declare required identifiers")
  func requiredParameters() throws {
    let map = try toolMap(from: loadManifest())

    let addTextParams = map["add_text"]?["parameters"] as? [String: Any]
    let addTextRequired = Set(addTextParams?["required"] as? [String] ?? [])
    #expect(addTextRequired == ["presentation_id", "slide_number", "text"])

    let chartParams = map["add_chart"]?["parameters"] as? [String: Any]
    let chartRequired = Set(chartParams?["required"] as? [String] ?? [])
    #expect(
      chartRequired == [
        "presentation_id",
        "slide_number",
        "chart_type",
        "categories",
        "series",
      ])
  }
}
