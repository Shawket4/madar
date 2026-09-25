import CoreLocation
import Flutter
import UIKit
import flutter_secure_storage_darwin
import shared_preferences_foundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// On-shift tracking that outlives the app (CL-4): see [DawamTracker].
  private let tracker = DawamTracker()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // A cold start on shift, or a relaunch by iOS for a location event (the
    // branch's fence crossed, a significant move): tracking is armed again
    // before iOS hands the event to the tracker, which keeps the reading
    // until the app's Dart side asks for it.
    tracker.resumeIfOn()
    // Launched for that event with no screen: the app's engine may never
    // run, so the tracker's headless one boots while iOS gets the reading.
    if launchOptions?[.location] != nil { tracker.wokenForLocation() }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DawamTracking") {
      // The engine keeps its registrar: when the engine goes (its scene
      // disconnected), so does the registrar, and readings go headless.
      tracker.attach(messenger: registrar.messenger(), owner: registrar)
    }
  }
}

// MARK: - On-shift tracking (CL-4)

/// The branch's fence the tracker watches on shift: the core's
/// `tracking_fence`, handed over with "start" and kept for a relaunch.
struct DawamFence: Equatable {
  let latitude: Double
  let longitude: Double
  let radius: Double

  /// iOS reports crossings of a smaller region late or not at all.
  static let smallestRegion: CLLocationDistance = 100

  init(latitude: Double, longitude: Double, radius: Double) {
    self.latitude = latitude
    self.longitude = longitude
    self.radius = radius
  }

  /// From the channel's, or the saved, `{latitude, longitude, radius}`.
  init?(_ value: Any?) {
    guard let m = value as? [String: Any],
      let lat = (m["latitude"] as? NSNumber)?.doubleValue,
      let lng = (m["longitude"] as? NSNumber)?.doubleValue,
      CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lng))
    else { return nil }
    let radius = (m["radius"] as? NSNumber)?.doubleValue ?? 0
    self.init(latitude: lat, longitude: lng, radius: max(0, radius))
  }

  var saved: [String: Double] {
    ["latitude": latitude, "longitude": longitude, "radius": radius]
  }

  /// The region iOS watches: the fence, widened to what iOS reports well and
  /// no wider than it can monitor. Leaving and entering both wake the app.
  func region(maximum: CLLocationDistance) -> CLCircularRegion {
    var r = max(radius, Self.smallestRegion)
    if maximum > 0 { r = min(r, maximum) }
    let region = CLCircularRegion(
      center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
      radius: r,
      identifier: DawamTracker.regionId)
    region.notifyOnExit = true
    region.notifyOnEntry = true
    return region
  }
}

/// Readings waiting for the app's Dart side, oldest first. Kept in
/// UserDefaults, so a reading taken on a relaunch that iOS suspends before
/// the app has booted is not lost; at most [cap], the oldest going first.
final class DawamFixQueue {
  static let key = "dawam.tracking.queue"
  static let cap = 20

  private let defaults: UserDefaults

  init(defaults: UserDefaults) {
    self.defaults = defaults
  }

  var items: [[String: Any]] {
    defaults.array(forKey: Self.key) as? [[String: Any]] ?? []
  }

  /// Keep one reading and why it was taken; returns its id.
  @discardableResult
  func push(_ l: CLLocation, wake: String) -> String {
    let id = UUID().uuidString
    var fix: [String: Any] = [
      "id": id,
      "latitude": l.coordinate.latitude,
      "longitude": l.coordinate.longitude,
      "wake": wake,
      // The phone's clock (never sent as GPS time, CL-11): it only ages the
      // reading, so the app does not send an old one as where they are now.
      "at": l.timestamp.timeIntervalSince1970,
    ]
    if l.horizontalAccuracy >= 0 { fix["accuracy"] = l.horizontalAccuracy }
    // CL-9: the OS's own mock marker.
    if let source = l.sourceInformation { fix["mock"] = source.isSimulatedBySoftware }
    var all = items
    all.append(fix)
    if all.count > Self.cap { all.removeFirst(all.count - Self.cap) }
    defaults.set(all, forKey: Self.key)
    return id
  }

  func remove(id: String) {
    defaults.set(items.filter { $0["id"] as? String != id }, forKey: Self.key)
  }

  /// What the Dart side is handed: the reading, with its age in seconds in
  /// place of the phone-clock time.
  static func message(_ fix: [String: Any], now: Date) -> [String: Any] {
    var m = fix
    let at = (fix["at"] as? NSNumber)?.doubleValue ?? now.timeIntervalSince1970
    m.removeValue(forKey: "at")
    m["age_s"] = Int(max(0, now.timeIntervalSince1970 - at).rounded())
    return m
  }
}

/// When a reading goes to the app (CL-4). A crossing of the branch's fence
/// goes at once; anything else at most once per 14 minutes, like Android's
/// service (`PING_EVERY_MS`): the server wants one per 15 and reads about 45
/// minutes of silence as "tracking off".
struct DawamCadence {
  static let every: TimeInterval = 14 * 60
  /// A reading asked for that never came is asked for again this soon.
  static let retry: TimeInterval = 2 * 60

  private(set) var last: Date?

  func due(_ wake: String, at now: Date) -> Bool {
    if wake.hasPrefix("region_") { return true }
    guard let last else { return true }
    return now.timeIntervalSince(last) >= Self.every
  }

  mutating func took(at now: Date) {
    last = now
  }

  /// How long until the next reading is due (0: now).
  func wait(at now: Date) -> TimeInterval {
    guard let last else { return 0 }
    return max(0, Self.every - now.timeIntervalSince(last))
  }
}

/// Which Dart side a reading goes to (CL-4). One reading is in flight to one
/// engine at a time, and leaves the queue on that engine's answer, so two
/// isolates never ping the same fix.
enum DawamRoute: Equatable {
  /// The app's engine: its Dart side listens (it asked for the flush), or
  /// it is up and is tried ("not implemented" keeps the reading).
  case app
  /// The headless engine running `dawamTrackingMain`, ready.
  case headless
  /// No app engine and no screen: start the headless engine; the reading
  /// goes when it says ready.
  case startHeadless
  /// An engine is coming: the headless one is booting, or a screen is
  /// connected and its engine is on its way.
  case wait

  static func route(
    appListening: Bool, appAttached: Bool, headless: DawamHeadlessState, sceneless: Bool
  ) -> DawamRoute {
    if appListening { return .app }
    switch headless {
    case .ready: return .headless
    case .starting: return .wait
    case .none: break
    }
    if appAttached { return .app }
    return sceneless ? .startHeadless : .wait
  }
}

enum DawamHeadlessState: Equatable { case none, starting, ready }

/// A Dart side with no UI (a seam for RunnerTests).
protocol DawamHeadlessEngine: AnyObject {
  var messenger: FlutterBinaryMessenger { get }
  func destroy()
}

/// `dawamTrackingMain` (lib/background.dart) in a headless FlutterEngine, as
/// Android's DawamTrackingService runs it: the same core, through the same
/// store, pings and says whether the shift is still on.
final class DawamHeadlessFlutter: DawamHeadlessEngine {
  static let entrypoint = "dawamTrackingMain"
  static let library = "package:madar_staff/background.dart"

  private let engine: FlutterEngine
  var messenger: FlutterBinaryMessenger { engine.binaryMessenger }

  init?() {
    engine = FlutterEngine(name: "dawam.tracking", project: nil, allowHeadlessExecution: true)
    guard engine.run(withEntrypoint: Self.entrypoint, libraryURI: Self.library) else { return nil }
    // Only the plugins the entry point uses: its prefs and the device token
    // in the Keychain (path_provider and the core are FFI). Never the whole
    // GeneratedPluginRegistrant: firebase_messaging keeps ONE shared
    // instance, and registering it here would move its channel off the
    // app's engine, so pushes and taps went nowhere once this one is gone.
    if let r = engine.registrar(forPlugin: "SharedPreferencesPlugin") {
      SharedPreferencesPlugin.register(with: r)
    }
    if let r = engine.registrar(forPlugin: "FlutterSecureStorageDarwinPlugin") {
      FlutterSecureStorageDarwinPlugin.register(with: r)
    }
  }

  func destroy() {
    engine.destroyContext()
  }
}

/// Background time for a reading and its ping (a seam for RunnerTests).
protocol DawamBackgroundTime {
  func begin(expired: @escaping () -> Void) -> UIBackgroundTaskIdentifier
  func end(_ task: UIBackgroundTaskIdentifier)
}

struct AppBackgroundTime: DawamBackgroundTime {
  func begin(expired: @escaping () -> Void) -> UIBackgroundTaskIdentifier {
    UIApplication.shared.beginBackgroundTask(withName: "dawam.tracking", expirationHandler: expired)
  }

  func end(_ task: UIBackgroundTaskIdentifier) {
    UIApplication.shared.endBackgroundTask(task)
  }
}

/// On-shift tracking that outlives the app (CL-4). Started at clock-in and
/// stopped at clock-out by the app (CL-17); the on/off state and the
/// branch's fence are kept, so a relaunch resumes them.
///
/// - While the app runs, in the background too: standard location updates
///   (100 m, with the location indicator) keep it running, as Android's
///   foreground service does, and a reading goes to the app every 14
///   minutes: a fresh one is asked for when nobody moved.
/// - Once iOS or the person has closed it: the branch's region and
///   significant-change monitoring relaunch it. Leaving or re-entering the
///   branch takes one reading at once; a significant move is its own
///   reading. The relaunch starts the updates again.
///
/// Every reading waits in [queue] until a Dart side answers that the core
/// has it (the ping), so one taken while the app boots is not lost, and the
/// app is held awake for the ping. That Dart side is the app's engine when
/// it listens; with no screen (iOS woke the closed app for a location event,
/// or it runs in the background with no scene), a headless engine runs
/// `dawamTrackingMain` as Android's service does, and is torn down once its
/// pings are answered. See [DawamRoute].
final class DawamTracker: NSObject, CLLocationManagerDelegate {
  static let onKey = "dawam.tracking.on"
  static let fenceKey = "dawam.tracking.fence"
  static let regionId = "dawam.branch"
  static let channelName = "com.madar.dawam/tracking"
  /// The headless engine's channel (lib/background.dart, as on Android).
  static let headlessChannelName = "com.madar.dawam/tracking.background"
  /// How long a reading and its ping may hold the app awake (iOS gives ~30 s).
  static let awakeFor: TimeInterval = 25

  let defaults: UserDefaults
  let queue: DawamFixQueue
  /// Significant changes and the branch's region: what relaunches a closed app.
  let watch: CLLocationManager
  /// Standard updates on shift: the app keeps running in the background.
  let live: CLLocationManager
  /// One reading on demand: after a fence crossing, or when 14 minutes are up.
  let oneShot: CLLocationManager
  private let backgroundTime: DawamBackgroundTime
  private let makeHeadless: () -> DawamHeadlessEngine?
  private let sceneless: () -> Bool
  private let battery: () -> Int?

  private(set) var cadence = DawamCadence()
  /// Why the one reading asked for is wanted.
  private(set) var pendingWake: String?
  /// The app's engine: its channel, the object whose life is the engine's,
  /// and whether its Dart side listens.
  private var appChannel: FlutterMethodChannel?
  private weak var appOwner: AnyObject?
  private var appOwned = false
  private var appListening = false
  private(set) var headless: DawamHeadlessEngine?
  private var headlessChannel: FlutterMethodChannel?
  private var headlessReady = false
  /// Launched for a location event whose reading has not come yet.
  private var expectingWake = false
  private var inFlight: (id: String, route: DawamRoute)?
  private var generation = 0
  private var intervalTimer: Timer?
  private var awake: UIBackgroundTaskIdentifier = .invalid
  private var awakeDeadline: DispatchWorkItem?

  init(
    defaults: UserDefaults = .standard,
    watch: CLLocationManager = CLLocationManager(),
    live: CLLocationManager = CLLocationManager(),
    oneShot: CLLocationManager = CLLocationManager(),
    backgroundTime: DawamBackgroundTime = AppBackgroundTime(),
    makeHeadless: @escaping () -> DawamHeadlessEngine? = { DawamHeadlessFlutter() },
    sceneless: @escaping () -> Bool = { UIApplication.shared.connectedScenes.isEmpty },
    battery: @escaping () -> Int? = DawamTracker.deviceBattery
  ) {
    self.defaults = defaults
    self.queue = DawamFixQueue(defaults: defaults)
    self.watch = watch
    self.live = live
    self.oneShot = oneShot
    self.backgroundTime = backgroundTime
    self.makeHeadless = makeHeadless
    self.sceneless = sceneless
    self.battery = battery
    super.init()
    for m in [watch, live, oneShot] { m.delegate = self }
  }

  var isOn: Bool { defaults.bool(forKey: Self.onKey) }
  var fence: DawamFence? { DawamFence(defaults.dictionary(forKey: Self.fenceKey)) }
  var isHoldingAwake: Bool { awake != .invalid }

  var headlessState: DawamHeadlessState {
    headless == nil ? .none : headlessReady ? .ready : .starting
  }

  /// The app's engine is still there (its owner, weakly held, is alive).
  private var appAlive: Bool {
    appChannel != nil && (!appOwned || appOwner != nil)
  }

  /// The phone's battery for a headless ping (the app's Dart side reads its own).
  static func deviceBattery() -> Int? {
    UIDevice.current.isBatteryMonitoringEnabled = true
    let level = UIDevice.current.batteryLevel
    return level < 0 ? nil : Int((level * 100).rounded())
  }

  /// [owner]: an object that lives exactly as long as the app's engine.
  func attach(messenger: FlutterBinaryMessenger, owner: AnyObject? = nil) {
    let c = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    c.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      switch call.method {
      case "start":
        self.start(fence: DawamFence((call.arguments as? [String: Any])?["fence"]))
        result(nil)
      case "stop":
        self.stop()
        result(nil)
      case "requestAlways":
        self.requestAlways(result)
      case "flush":
        result(nil)
        self.appListens()
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    appChannel = c
    appOwner = owner
    appOwned = owner != nil
    appListening = false
    // A relaunch's reading may be waiting already. A Dart side not listening
    // yet answers "not implemented" and the reading stays for its flush.
    flush()
  }

  /// The app's Dart side listens (it asked for the flush): readings go to it
  /// from now on. One sent to it before it listened is sent again (it knows
  /// a repeat by its id); one in flight to the headless engine finishes
  /// there, never sent to both. The headless engine then goes.
  func appListens() {
    appListening = true
    if inFlight?.route == .app {
      generation += 1
      inFlight = nil
    }
    flush()
    retireHeadlessIfIdle()
  }

  /// iOS launched the app for a location event (a fence crossing or a
  /// significant move while it was closed). With no screen, the app's
  /// engine may never run: the headless one boots now, while iOS gets the
  /// reading, and the app stays awake for it.
  func wokenForLocation() {
    guard isOn else { return }
    expectingWake = true
    holdAwake()
    if !appAlive { startHeadless() }
  }

  /// Clock-in, and whenever the fence moves: everything on.
  func start(fence: DawamFence?) {
    defaults.set(true, forKey: Self.onKey)
    if let fence {
      defaults.set(fence.saved, forKey: Self.fenceKey)
    } else {
      defaults.removeObject(forKey: Self.fenceKey)
    }
    arm()
  }

  /// Clock-out: everything off. Readings already taken still go to the app
  /// (the core records none off shift).
  func stop() {
    defaults.set(false, forKey: Self.onKey)
    defaults.removeObject(forKey: Self.fenceKey)
    watch.stopMonitoringSignificantLocationChanges()
    watchRegion(nil)
    live.stopUpdatingLocation()
    intervalTimer?.invalidate()
    intervalTimer = nil
    pendingWake = nil
    expectingWake = false
    cadence = DawamCadence()
    releaseIfIdle()
  }

  /// A cold start or a relaunch while on shift: everything on again. Off,
  /// nothing is touched.
  func resumeIfOn() {
    if isOn { arm() }
  }

  private func arm() {
    if type(of: watch).significantLocationChangeMonitoringAvailable() {
      watch.startMonitoringSignificantLocationChanges()
    }
    watchRegion(fence)
    // Info.plist declares the `location` background mode. The indicator
    // tells the person, as the on-shift notification does on Android.
    live.desiredAccuracy = kCLLocationAccuracyHundredMeters
    live.distanceFilter = 100
    live.pausesLocationUpdatesAutomatically = false
    live.allowsBackgroundLocationUpdates = true
    live.showsBackgroundLocationIndicator = true
    live.startUpdatingLocation()
    scheduleInterval(after: cadence.last == nil ? DawamCadence.retry : cadence.wait(at: Date()))
  }

  /// Watch [fence]'s region, and nothing else under our id. The same region
  /// already watched is left alone: restarting it on the relaunch it caused
  /// could lose the crossing iOS is about to deliver.
  private func watchRegion(_ fence: DawamFence?) {
    let want = fence?.region(maximum: watch.maximumRegionMonitoringDistance)
    let have = watch.monitoredRegions.first { $0.identifier == Self.regionId }
    if let want, let have = have as? CLCircularRegion,
      abs(have.center.latitude - want.center.latitude) < 1e-7,
      abs(have.center.longitude - want.center.longitude) < 1e-7,
      abs(have.radius - want.radius) < 0.5
    {
      return
    }
    if let have { watch.stopMonitoring(for: have) }
    if let want, type(of: watch).isMonitoringAvailable(for: CLCircularRegion.self) {
      watch.startMonitoring(for: want)
    }
  }

  // MARK: readings

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let l = locations.last else { return }
    if manager === oneShot {
      let wake = pendingWake ?? "interval"
      pendingWake = nil
      take(l, wake: wake)
    } else if manager === watch {
      take(l, wake: "significant_change")
    } else if manager === live {
      take(l, wake: "interval")
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    guard manager === oneShot else { return }
    // No reading to be had: the interval timer asks again.
    pendingWake = nil
    releaseIfIdle()
  }

  // Region events may reach every location manager's delegate: whichever
  // brings it first asks for the reading, and a repeat is ignored.
  func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
    crossed(region, wake: "region_exit")
  }

  func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
    crossed(region, wake: "region_entry")
  }

  private func crossed(_ region: CLRegion, wake: String) {
    guard region.identifier == Self.regionId, isOn, pendingWake != wake else { return }
    ask(wake)
  }

  /// One fresh reading, for [wake]. A fence crossing outranks the interval.
  private func ask(_ wake: String) {
    if wake.hasPrefix("region_") || pendingWake == nil { pendingWake = wake }
    holdAwake()
    oneShot.desiredAccuracy = kCLLocationAccuracyHundredMeters
    oneShot.requestLocation()
  }

  /// A reading: kept for the app when it is due (a fence crossing always,
  /// anything else once per 14 minutes), and handed over.
  func take(_ l: CLLocation, wake: String, now: Date = Date()) {
    expectingWake = false
    guard isOn, cadence.due(wake, at: now) else { return }
    cadence.took(at: now)
    queue.push(l, wake: wake)
    scheduleInterval(after: DawamCadence.every)
    // Awake for the ping, and on a relaunch for the engine to boot first.
    holdAwake()
    flush(now: now)
  }

  /// The 14-minute reading when nobody moves: on shift the app runs in the
  /// background (the updates), so a timer asks for a fresh one when due.
  private func scheduleInterval(after wait: TimeInterval) {
    intervalTimer?.invalidate()
    intervalTimer = nil
    guard isOn else { return }
    let t = Timer(timeInterval: max(wait, 1), repeats: false) { [weak self] _ in
      self?.intervalDue()
    }
    t.tolerance = 30
    RunLoop.main.add(t, forMode: .common)
    intervalTimer = t
  }

  private func intervalDue() {
    guard isOn else { return }
    let now = Date()
    if cadence.due("interval", at: now) {
      ask("interval")
      scheduleInterval(after: DawamCadence.retry)
    } else {
      scheduleInterval(after: cadence.wait(at: now))
    }
  }

  // MARK: handing over

  /// Hands the kept readings to a Dart side, oldest first, one at a time;
  /// each leaves the queue only when that side answers that the core has it
  /// ([DawamRoute] picks the side). The app's Dart side not listening yet (a
  /// relaunch still booting) answers "not implemented": the reading stays
  /// for the flush it asks for once it listens.
  func flush(now: Date = Date()) {
    if appListening, !appAlive {
      // The app's engine is gone (its scene disconnected): headless now.
      appListening = false
      appChannel = nil
      if inFlight?.route == .app {
        generation += 1
        inFlight = nil
      }
    }
    guard inFlight == nil else { return }
    guard let next = queue.items.first, let id = next["id"] as? String else {
      retireHeadlessIfIdle()
      releaseIfIdle()
      return
    }
    let route = DawamRoute.route(
      appListening: appListening, appAttached: appAlive, headless: headlessState,
      sceneless: sceneless())
    switch route {
    case .wait:
      holdAwake()
    case .startHeadless:
      holdAwake()
      startHeadless()
    case .app:
      if let channel = appChannel {
        retireHeadlessIfIdle()
        send(next, id: id, over: channel, route: .app, now: now)
      }
    case .headless:
      if let channel = headlessChannel {
        send(next, id: id, over: channel, route: .headless, now: now)
      }
    }
  }

  private func send(
    _ fix: [String: Any], id: String, over channel: FlutterMethodChannel, route: DawamRoute,
    now: Date
  ) {
    holdAwake()
    inFlight = (id, route)
    let sent = generation
    var message = DawamFixQueue.message(fix, now: now)
    if route == .headless, let b = battery() { message["battery"] = b }
    channel.invokeMethod("fix", arguments: message) { [weak self] reply in
      guard let self, self.generation == sent, self.inFlight?.id == id else { return }
      self.inFlight = nil
      // Not taken: the app's Dart side not listening yet (kept for its
      // flush, the app awake until the deadline so it can boot), or the
      // headless one failed (kept for the next reading).
      guard Self.handled(reply) else { return }
      self.queue.remove(id: id)
      // The headless engine's core says the shift is over, or nobody is
      // signed in: tracking stops, as Android's service does (CL-17).
      if route == .headless, (reply as? Bool) == false { self.stop() }
      self.flush()
    }
  }

  // MARK: the headless engine

  private func startHeadless() {
    guard headless == nil, let engine = makeHeadless() else { return }
    headless = engine
    headlessReady = false
    let c = FlutterMethodChannel(
      name: Self.headlessChannelName, binaryMessenger: engine.messenger)
    c.setMethodCallHandler { [weak self, weak engine] call, result in
      guard let self, let engine, self.headless === engine else { return result(nil) }
      guard call.method == "ready" else { return result(FlutterMethodNotImplemented) }
      self.headlessReady = true
      result(nil)
      self.flush()
    }
    headlessChannel = c
  }

  /// The headless engine goes once nothing is left for it: the app's Dart
  /// side listens, or its pings are answered and no reading is on its way.
  private func retireHeadlessIfIdle() {
    guard headless != nil, inFlight?.route != .headless else { return }
    if appListening || (queue.items.isEmpty && pendingWake == nil && !expectingWake) {
      retireHeadless()
    }
  }

  private func retireHeadless() {
    guard let engine = headless else { return }
    headlessChannel?.setMethodCallHandler(nil)
    headlessChannel = nil
    headless = nil
    headlessReady = false
    if inFlight?.route == .headless {
      // Cut short (the background time is up): kept, sent again later.
      generation += 1
      inFlight = nil
    }
    engine.destroy()
  }

  /// Whether the Dart side took a reading (no handler yet: not implemented).
  static func handled(_ reply: Any?) -> Bool {
    if reply is FlutterError { return false }
    if let o = reply as? NSObject, o === FlutterMethodNotImplemented { return false }
    return true
  }

  // MARK: background time

  /// Background time for a reading and its ping, so the network call can
  /// finish: from a fence crossing or a new reading until the queue is
  /// empty, at most [awakeFor].
  private func holdAwake() {
    guard awake == .invalid else { return }
    awake = backgroundTime.begin { [weak self] in self?.letSleep() }
    let deadline = DispatchWorkItem { [weak self] in self?.letSleep() }
    awakeDeadline = deadline
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.awakeFor, execute: deadline)
  }

  /// Nothing kept, nothing in flight, no reading asked for or on its way:
  /// the app may sleep.
  private func releaseIfIdle() {
    if queue.items.isEmpty, inFlight == nil, pendingWake == nil, !expectingWake { letSleep() }
  }

  /// Idle, or the background time is up: the headless engine goes too.
  private func letSleep() {
    awakeDeadline?.cancel()
    awakeDeadline = nil
    expectingWake = false
    retireHeadless()
    guard awake != .invalid else { return }
    backgroundTime.end(awake)
    awake = .invalid
  }

  // MARK: "Always"

  /// "Always" location (CL-4): geolocator asks iOS only while the choice is
  /// undetermined, and its ask is "While Using". This is the upgrade, asked
  /// once by the app; iOS shows it once and answers through the delegate
  /// only when the choice changes (the app gives up waiting after a while).
  private var alwaysAnswer: FlutterResult?

  private func requestAlways(_ result: @escaping FlutterResult) {
    let status = watch.authorizationStatus
    guard status == .authorizedWhenInUse else {
      result(status == .authorizedAlways)
      return
    }
    alwaysAnswer?(nil)
    alwaysAnswer = result
    watch.requestAlwaysAuthorization()
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard manager === watch, let answer = alwaysAnswer else { return }
    let status = manager.authorizationStatus
    if status == .notDetermined { return }
    alwaysAnswer = nil
    answer(status == .authorizedAlways)
  }
}
