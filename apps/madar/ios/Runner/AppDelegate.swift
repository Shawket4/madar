import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Own the notification center before any plugin starts: iOS shows a
    // banner with the till open, and delivers a tap, only through it, and
    // Flutter passes both on to every plugin that asked (the live alerts'
    // local notifications and Firebase messaging). Without it the till's
    // banners never showed and a tapped one never reached the Queue.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Everything the till is told while it is open (a live order, a booking,
  // a push) shows as a banner, stays in the list and plays its sound. The
  // plugins still see each one first (firebase_messaging hands a push to
  // Dart's onMessage), but their answers are not the till's: Flutter asks
  // them all and iOS takes the first, and firebase_messaging, asked before
  // the local notifications, answers every notification with its own
  // foreground options (no banner, or nothing at all before Firebase has
  // started), which hid the live alerts' banners (E2E B-POS-4b).
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    super.userNotificationCenter(center, willPresent: notification) { _ in }
    completionHandler([.banner, .list, .sound, .badge])
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
