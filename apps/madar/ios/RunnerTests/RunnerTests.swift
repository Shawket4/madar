import Flutter
import UIKit
import UserNotifications
import XCTest

/// Archived under UNNotification's keys, then decoded as one.
@objc(RunnerTestsArchivedNotification)
private final class Archived: NSObject, NSCoding {
  let request: UNNotificationRequest
  init(_ request: UNNotificationRequest) { self.request = request }
  required init?(coder: NSCoder) { nil }
  func encode(with coder: NSCoder) {
    coder.encode(request, forKey: "request")
    coder.encode(Date(), forKey: "date")
  }
}

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

  /// E2E posnotif B-POS-4b: with the till open, neither a live alert (a local
  /// notification) nor a push showed a banner. Flutter asks every plugin, and
  /// firebase_messaging, asked first, answered for all of them with its own
  /// foreground options: sound and badge but no banner, and nothing at all
  /// before Firebase starts. iOS takes the first answer. The till answers.
  func testANotificationWithTheTillOpenShowsAsABanner() throws {
    let content = UNMutableNotificationContent()
    content.title = "New booking"
    let notification = try Self.notification(
      UNNotificationRequest(identifier: "e2e-banner", content: content, trigger: nil))
    let delegate = try XCTUnwrap(UNUserNotificationCenter.current().delegate)
    var answers: [UNNotificationPresentationOptions] = []
    delegate.userNotificationCenter?(
      UNUserNotificationCenter.current(), willPresent: notification
    ) { answers.append($0) }
    let first = try XCTUnwrap(answers.first, "nobody answered")
    XCTAssertTrue(first.contains(.banner), "no banner: \(first.rawValue)")
    XCTAssertTrue(first.contains(.list), "not kept in the list: \(first.rawValue)")
    XCTAssertTrue(first.contains(.sound), "no sound: \(first.rawValue)")
  }

  /// A delivered notification carrying `request`: UNNotification has no
  /// public initializer, so one is decoded from an archive with its keys.
  private static func notification(_ request: UNNotificationRequest) throws -> UNNotification {
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: Archived(request), requiringSecureCoding: false)
    let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
    unarchiver.requiresSecureCoding = false
    unarchiver.setClass(UNNotification.self, forClassName: NSStringFromClass(Archived.self))
    return try XCTUnwrap(
      unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? UNNotification)
  }

}
