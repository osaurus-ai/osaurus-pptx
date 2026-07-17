import Foundation
import OsaurusPluginABI
import OsaurusPluginTestSupport
import Testing

@testable import osaurus_pptx

// MARK: - SDK Conformance

@Suite("SDK Conformance")
struct SDKConformanceTests {

  @Test("Manifest passes registry conformance")
  func manifestConformant() throws {
    try ManifestConformance.assertConformant(pptxManifestJSON)
  }

  @Test("v2 entry point returns a conformant plugin API table")
  func entryV2Conformant() throws {
    try ABIConformance.assertEntryConformance(
      osaurus_plugin_entry_v2(nil), manifestJSON: pptxManifestJSON)
  }

  @Test("v1 entry point returns the same conformant table")
  func entryV1Conformant() throws {
    try ABIConformance.assertEntryConformance(
      osaurus_plugin_entry(), manifestJSON: pptxManifestJSON)
  }

  @Test("Tool failures render the canonical failure envelope")
  func canonicalFailure() throws {
    var presentations: [String: Presentation] = [:]
    let invalidArgs = CreatePresentationTool().run(args: "{}", presentations: &presentations)
    try assertCanonicalFailure(invalidArgs, kind: .invalidArgs)

    let notFound = AddSlideTool().run(
      args: "{\"presentation_id\": \"missing\"}", presentations: &presentations)
    try assertCanonicalFailure(notFound, kind: .notFound)
  }
}
