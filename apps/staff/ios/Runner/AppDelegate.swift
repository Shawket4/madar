import CoreLocation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// On-shift tracking that outlives the app (CL-4): see [DawamTracker].
  private let tracker = DawamTracker()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Relaunched by iOS for a significant location change while on shift
    // (or a cold start on shift): monitoring goes on, and the app's own
    // start picks the pings up from there.
    tracker.resumeIfOn()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DawamTracking") {
      tracker.attach(messenger: registrar.messenger())
    }
  }
}

/// On shift, iOS keeps the app's location going in the background while it
/// runs (the position stream with the blue indicator). When the app is
/// closed or the phone restarts, significant-change monitoring is what
/// brings it back: iOS relaunches the app in the background on the next
/// significant move, the app restores its session and pings again (CL-4).
/// The fix that woke it is handed to the app over the tracking channel.
/// Started at clock-in and stopped at clock-out by the app (CL-17); the
/// on/off state is kept so a relaunch resumes it.
final class DawamTracker: NSObject, CLLocationManagerDelegate {
  private static let onKey = "dawam.tracking.on"
  private let manager = CLLocationManager()
  private var channel: FlutterMethodChannel?

  override init() {
    super.init()
    manager.delegate = self
  }

  func attach(messenger: FlutterBinaryMessenger) {
    let c = FlutterMethodChannel(name: "com.madar.dawam/tracking", binaryMessenger: messenger)
    c.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "start":
        self?.start()
        result(nil)
      case "stop":
        self?.stop()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel = c
  }

  func resumeIfOn() {
    if UserDefaults.standard.bool(forKey: Self.onKey) {
      monitor()
    }
  }

  private func start() {
    UserDefaults.standard.set(true, forKey: Self.onKey)
    monitor()
  }

  private func stop() {
    UserDefaults.standard.set(false, forKey: Self.onKey)
    manager.stopMonitoringSignificantLocationChanges()
  }

  private func monitor() {
    guard CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
    // Info.plist declares the `location` background mode.
    manager.allowsBackgroundLocationUpdates = true
    manager.pausesLocationUpdatesAutomatically = false
    manager.startMonitoringSignificantLocationChanges()
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let l = locations.last, let channel = channel else { return }
    var args: [String: Any] = [
      "latitude": l.coordinate.latitude,
      "longitude": l.coordinate.longitude,
      "accuracy": l.horizontalAccuracy,
    ]
    // CL-9: the OS's own mock marker. The fix's timestamp is the phone's
    // clock on iOS, so it is never sent as GPS time (CL-11).
    if #available(iOS 15.0, *) {
      args["mock"] = l.sourceInformation?.isSimulatedBySoftware ?? false
    }
    channel.invokeMethod("fix", arguments: args)
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
