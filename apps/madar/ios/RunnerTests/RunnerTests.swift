import Flutter
import UIKit
import UserNotifications
import XCTest

class RunnerTests: XCTestCase {

  /// E2E posnotif: nobody owned the notification center, so iOS never showed
  /// the till's own banners (a live order, a push while open) and a tap on
  /// one never reached the app. The app delegate owns it; Flutter hands the
  /// calls on to every plugin that asked (local notifications, messaging).
  func testTheAppDelegateOwnsTheNotificationCenter() {
    let center = UNUserNotificationCenter.current().delegate
    XCTAssertNotNil(center)
    XCTAssertTrue(center === UIApplication.shared.delegate)
  }

}
