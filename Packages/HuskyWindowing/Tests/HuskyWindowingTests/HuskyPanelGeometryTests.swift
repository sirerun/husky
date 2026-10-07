import CoreGraphics
import XCTest

@testable import HuskyWindowing

final class HuskyPanelGeometryTests: XCTestCase {
  func testInitialFrameUsesBottomLeftOfVisibleFrameWithInset() {
    let visibleFrame = CGRect(x: 100, y: 40, width: 1_000, height: 800)

    let frame = HuskyPanelGeometry.initialFrame(in: visibleFrame)

    XCTAssertEqual(frame, CGRect(x: 124, y: 64, width: 448, height: 544))
  }

  func testLegacyDefaultFramesNormalizeAndPreserveOrigin() {
    for height in [CGFloat(660), CGFloat(680)] {
      let saved = CGRect(x: 135, y: 74, width: 560, height: height)

      XCTAssertEqual(
        HuskyPanelGeometry.resizeLegacyDefaultFrame(saved),
        CGRect(x: 135, y: 74, width: HuskyPanelLayout.width, height: HuskyPanelLayout.height)
      )
    }
  }

  func testCustomFramePassesThroughLegacyMigration() {
    let custom = CGRect(x: 135, y: 74, width: 600, height: 700)

    XCTAssertEqual(HuskyPanelGeometry.resizeLegacyDefaultFrame(custom), custom)
  }

  func testRestoreKeepsSavedPositionWhenFullyVisible() throws {
    let saved = CGRect(x: 320, y: 210, width: 448, height: 544)
    let screen = area(frame: CGRect(x: 0, y: 0, width: 1_440, height: 900))

    let restoration = try XCTUnwrap(
      HuskyPanelGeometry.restore(savedFrame: saved, screens: [screen], activeScreenIndex: 0))

    XCTAssertEqual(restoration.frame, saved)
    XCTAssertEqual(restoration.screenIndex, 0)
    XCTAssertFalse(restoration.usedFallbackScreen)
  }

  func testRestoreClampsSavedFrameToDockAdjustedVisibleFrame() throws {
    let screen = HuskyPanelScreenArea(
      frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
      visibleFrame: CGRect(x: 0, y: 70, width: 1_440, height: 800)
    )
    let saved = CGRect(x: 0, y: 0, width: 448, height: 544)

    let restoration = try XCTUnwrap(
      HuskyPanelGeometry.restore(savedFrame: saved, screens: [screen], activeScreenIndex: 0))

    XCTAssertEqual(restoration.frame, CGRect(x: 24, y: 94, width: 448, height: 544))
    XCTAssertTrue(screen.visibleFrame.insetBy(dx: 24, dy: 24).contains(restoration.frame))
  }

  func testDisconnectedDisplayFallsBackToActiveDisplayBottomLeft() throws {
    let remainingScreen = area(
      frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
      visibleFrame: CGRect(x: 0, y: 40, width: 1_440, height: 830)
    )
    let disconnectedSavedFrame = CGRect(x: 2_000, y: 200, width: 448, height: 544)

    let restoration = try XCTUnwrap(
      HuskyPanelGeometry.restore(
        savedFrame: disconnectedSavedFrame,
        screens: [remainingScreen],
        activeScreenIndex: 0
      ))

    XCTAssertEqual(restoration.frame, CGRect(x: 24, y: 64, width: 448, height: 544))
    XCTAssertEqual(restoration.screenIndex, 0)
    XCTAssertTrue(restoration.usedFallbackScreen)
  }

  func testDisconnectedDisplayWithoutActiveFallbackCannotRestore() {
    let screen = area(frame: CGRect(x: 0, y: 0, width: 1_440, height: 900))

    XCTAssertNil(
      HuskyPanelGeometry.restore(
        savedFrame: CGRect(x: 2_000, y: 200, width: 448, height: 544),
        screens: [screen],
        activeScreenIndex: nil
      ))
  }

  func testSavedFramePrefersDisplayWithLargestOverlap() throws {
    let first = area(frame: CGRect(x: 0, y: 0, width: 1_000, height: 800))
    let second = area(frame: CGRect(x: 900, y: 0, width: 1_000, height: 800))
    let saved = CGRect(x: 950, y: 100, width: 448, height: 544)

    let restoration = try XCTUnwrap(
      HuskyPanelGeometry.restore(savedFrame: saved, screens: [first, second], activeScreenIndex: 0))

    XCTAssertEqual(restoration.screenIndex, 1)
    XCTAssertFalse(restoration.usedFallbackScreen)
  }

  func testInitialFrameFitsVerySmallVisibleArea() {
    let visibleFrame = CGRect(x: 0, y: 0, width: 300, height: 240)

    let frame = HuskyPanelGeometry.initialFrame(in: visibleFrame)

    XCTAssertEqual(frame.size, CGSize(width: 252, height: 192))
    XCTAssertTrue(visibleFrame.contains(frame))
  }

  private func area(frame: CGRect, visibleFrame: CGRect? = nil) -> HuskyPanelScreenArea {
    HuskyPanelScreenArea(frame: frame, visibleFrame: visibleFrame ?? frame)
  }
}
