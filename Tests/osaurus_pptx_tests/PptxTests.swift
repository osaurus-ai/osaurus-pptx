import Foundation
import Testing

@testable import osaurus_pptx

// MARK: - Manifest Contract

@Suite("Manifest Contract")
struct ManifestContractTests {

  private func parsedManifest() -> [String: Any] {
    let data = pptxManifestJSON.data(using: .utf8)!
    return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
  }

  @Test("Manifest is valid JSON with expected identity")
  func manifestIdentity() {
    let manifest = parsedManifest()
    #expect(manifest["plugin_id"] as? String == "osaurus.pptx")
    #expect(manifest["name"] as? String == "PPTX")
  }

  @Test("Every tool has a non-empty id and description")
  func toolsHaveIdAndDescription() {
    let manifest = parsedManifest()
    let capabilities = manifest["capabilities"] as? [String: Any]
    let tools = capabilities?["tools"] as? [[String: Any]]
    #expect(tools != nil)
    #expect(tools?.count == 12)

    var ids: [String] = []
    for tool in tools ?? [] {
      let id = tool["id"] as? String
      let description = tool["description"] as? String
      #expect(id != nil)
      #expect(id?.isEmpty == false)
      #expect(description != nil)
      #expect(description?.isEmpty == false)
      if let id = id { ids.append(id) }
    }

    let expected = [
      "create_presentation", "add_slide", "add_text", "add_image", "add_shape", "add_table",
      "add_chart", "set_slide_background", "delete_slide", "read_presentation",
      "get_presentation_info", "save_presentation",
    ]
    #expect(Set(ids) == Set(expected))
  }
}

// MARK: - Envelope

@Suite("Envelope")
struct EnvelopeTests {

  private func parse(_ json: String) -> [String: Any]? {
    guard let data = json.data(using: .utf8),
      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return obj
  }

  @Test("failure round-trips to canonical shape with default retryable")
  func failureRoundTrip() {
    let kinds: [(Envelope.Kind, Bool)] = [
      (.invalidArgs, true),
      (.executionError, true),
      (.unavailable, true),
      (.notFound, false),
    ]

    for (kind, expectedRetryable) in kinds {
      let json = Envelope.failure(kind, "boom")
      let obj = parse(json)
      #expect(obj?["ok"] as? Bool == false)
      #expect(obj?["kind"] as? String == kind.rawValue)
      #expect(obj?["message"] as? String == "boom")
      #expect(obj?["retryable"] as? Bool == expectedRetryable)
    }
  }

  @Test("failure honors explicit retryable override")
  func failureExplicitRetryable() {
    let obj = parse(Envelope.failure(.notFound, "missing", retryable: true))
    #expect(obj?["retryable"] as? Bool == true)
  }

  @Test("failure escapes special characters in message")
  func failureEscapesMessage() {
    let json = Envelope.failure(.executionError, "line1\nline2 \"quoted\" \\slash\t tab")
    let obj = parse(json)
    #expect(obj?["message"] as? String == "line1\nline2 \"quoted\" \\slash\t tab")
  }

  @Test("successRaw wraps payload as canonical success")
  func successRawWraps() {
    let obj = parse(Envelope.successRaw("{\"value\":1}"))
    #expect(obj?["ok"] as? Bool == true)
    #expect((obj?["result"] as? [String: Any])?["value"] as? Int == 1)
  }
}
