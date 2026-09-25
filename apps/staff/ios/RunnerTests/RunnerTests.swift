import CoreLocation
import Flutter
import UIKit
import XCTest

@testable import Runner

// CL-4: the on-shift tracker (AppDelegate.swift) over recorded Core Location,
// a recorded Dart side and its own UserDefaults suite.

/// Core Location as the tracker drives it: recorded, never done.
final class FakeLocationManager: CLLocationManager {
  var calls: [String] = []
  var regions = Set<CLRegion>()
  private var background = false
  private var indicator = false

  override class func significantLocationChangeMonitoringAvailable() -> Bool { true }
  override class func isMonitoringAvailable(for regionClass: AnyClass) -> Bool { true }
  override var maximumRegionMonitoringDistance: CLLocationDistance { 1000 }
  override var monitoredRegions: Set<CLRegion> { regions }
  override var allowsBackgroundLocationUpdates: Bool {
    get { background }
    set { background = newValue }
  }
  override var showsBackgroundLocationIndicator: Bool {
    get { indicator }
    set { indicator = newValue }
  }
  override func startMonitoringSignificantLocationChanges() { calls.append("significant.start") }
  override func stopMonitoringSignificantLocationChanges() { calls.append("significant.stop") }
  override func startMonitoring(for region: CLRegion) {
    regions.insert(region)
    calls.append("region.start")
  }
  override func stopMonitoring(for region: CLRegion) {
    regions.remove(region)
    calls.append("region.stop")
  }
  override func startUpdatingLocation() { calls.append("updates.start") }
  override func stopUpdatingLocation() { calls.append("updates.stop") }
  override func requestLocation() { calls.append("one") }
}

final class FakeBackgroundTime: DawamBackgroundTime {
  var begun = 0
  var ended = 0
  func begin(expired: @escaping () -> Void) -> UIBackgroundTaskIdentifier {
    begun += 1
    return UIBackgroundTaskIdentifier(rawValue: begun)
  }
  func end(_ task: UIBackgroundTaskIdentifier) { ended += 1 }
}

/// The app's Dart side of `com.madar.dawam/tracking`.
final class FakeDart: NSObject, FlutterBinaryMessenger {
  let codec = FlutterStandardMethodCodec.sharedInstance()
  /// No handler yet (a relaunch still booting): every reading is answered
  /// "not implemented".
  var listening = true
  /// Readings the host sent, in order.
  private(set) var fixes: [[String: Any]] = []
  /// What the Dart side answers a reading with (the headless one: whether
  /// the shift is still on).
  var answer: Any = true
  /// Replies held back, to answer later (a ping still going).
  var holdReplies = false
  private var held: [FlutterBinaryReply] = []
  private var handler: FlutterBinaryMessageHandler?

  func send(onChannel channel: String, message: Data?) {
    send(onChannel: channel, message: message, binaryReply: nil)
  }

  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
    let call = codec.decodeMethodCall(message!)
    if call.method == "fix" { fixes.append(call.arguments as? [String: Any] ?? [:]) }
    guard let callback else { return }
    if holdReplies {
      held.append(callback)
    } else {
      callback(listening ? codec.encodeSuccessEnvelope(answer) : nil)
    }
  }

  func answerHeld() {
    let replies = held
    held = []
    for r in replies { r(codec.encodeSuccessEnvelope(answer)) }
  }

  func setMessageHandlerOnChannel(
    _ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?
  ) -> FlutterBinaryMessengerConnection {
    self.handler = handler
    return 1
  }

  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}

  /// The Dart side calls the host ("start", "stop", "flush"; "ready").
  func call(_ method: String, _ arguments: Any? = nil) {
    handler?(codec.encode(FlutterMethodCall(methodName: method, arguments: arguments))) { _ in }
  }
}

/// `dawamTrackingMain` in a headless engine: its Dart side, recorded.
final class FakeHeadless: DawamHeadlessEngine {
  let dart = FakeDart()
  private(set) var destroyed = false
  var messenger: FlutterBinaryMessenger { dart }
  func destroy() { destroyed = true }
}

final class DawamTrackerTests: XCTestCase {
  private var suite: String!
  private var defaults: UserDefaults!
  private var watch: FakeLocationManager!
  private var live: FakeLocationManager!
  private var oneShot: FakeLocationManager!
  private var time: FakeBackgroundTime!
  /// Headless engines the tracker started, in order.
  private var engines: [FakeHeadless] = []
  /// No screen connected (iOS woke the closed app). Default: a screen.
  private var sceneless = false

  override func setUp() {
    super.setUp()
    suite = "dawam.tests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suite)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suite)
    super.tearDown()
  }

  /// A tracker as the app makes one at launch: over the same saved state
  /// each time, so a second one is a relaunch.
  private func launch() -> DawamTracker {
    watch = FakeLocationManager()
    live = FakeLocationManager()
    oneShot = FakeLocationManager()
    time = FakeBackgroundTime()
    return DawamTracker(
      defaults: defaults, watch: watch, live: live, oneShot: oneShot, backgroundTime: time,
      makeHeadless: { [unowned self] in
        let e = FakeHeadless()
        self.engines.append(e)
        return e
      },
      sceneless: { [unowned self] in self.sceneless },
      battery: { 55 })
  }

  private let zamalek = DawamFence(latitude: 30.0609, longitude: 31.2197, radius: 200)

  private func at(_ lat: Double, _ t: Date = Date()) -> CLLocation {
    CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: lat, longitude: 31.2197), altitude: 0,
      horizontalAccuracy: 65, verticalAccuracy: -1, timestamp: t)
  }

  // MARK: start / stop

  func testStartArmsEverythingAndStopDisarmsIt() {
    let tracker = launch()
    tracker.start(fence: zamalek)
    XCTAssertTrue(tracker.isOn)
    XCTAssertEqual(tracker.fence, zamalek)
    XCTAssertEqual(watch.calls, ["significant.start", "region.start"])
    XCTAssertEqual(live.calls, ["updates.start"], "the app keeps running in the background")
    XCTAssertTrue(live.allowsBackgroundLocationUpdates)
    XCTAssertTrue(live.showsBackgroundLocationIndicator)
    XCTAssertEqual(live.distanceFilter, 100)
    XCTAssertEqual(live.desiredAccuracy, kCLLocationAccuracyHundredMeters)
    XCTAssertFalse(live.pausesLocationUpdatesAutomatically)
    let region = watch.regions.first as? CLCircularRegion
    XCTAssertEqual(region?.identifier, DawamTracker.regionId)
    XCTAssertEqual(region?.radius, 200)
    XCTAssertEqual(region?.center.latitude, 30.0609)
    XCTAssertTrue(region?.notifyOnExit == true && region?.notifyOnEntry == true)

    tracker.stop()
    XCTAssertFalse(tracker.isOn)
    XCTAssertNil(tracker.fence)
    XCTAssertEqual(watch.calls.suffix(2), ["significant.stop", "region.stop"])
    XCTAssertTrue(watch.regions.isEmpty)
    XCTAssertEqual(live.calls.last, "updates.stop")
  }

  func testATinyFenceIsWatchedAtWhatIOSReportsAndAHugeOneAtItsLimit() {
    XCTAssertEqual(DawamFence(latitude: 30, longitude: 31, radius: 0).region(maximum: 1000).radius, 100)
    XCTAssertEqual(DawamFence(latitude: 30, longitude: 31, radius: 5000).region(maximum: 1000).radius, 1000)
  }

  func testTheFenceIsReadFromTheChannel() {
    XCTAssertEqual(DawamFence(["latitude": 30.0609, "longitude": 31.2197, "radius": 200]), zamalek)
    XCTAssertNil(DawamFence(NSNull()), "a branch with no coordinates")
    XCTAssertNil(DawamFence(["latitude": 95.0, "longitude": 31.0, "radius": 200]))
  }

  func testStartWithoutAFenceWatchesNoRegion() {
    let tracker = launch()
    tracker.start(fence: zamalek)
    tracker.start(fence: nil)
    XCTAssertNil(tracker.fence)
    XCTAssertTrue(watch.regions.isEmpty)
    XCTAssertEqual(live.calls.last, "updates.start")
  }

  // MARK: relaunch

  func testARelaunchOnShiftReArmsTheSavedFence() {
    launch().start(fence: zamalek)
    let region = watch.regions.first!
    // iOS relaunches the closed app: a new tracker over the same saved state,
    // with the region still monitored by iOS.
    let tracker = launch()
    watch.regions = [region]
    tracker.resumeIfOn()
    XCTAssertEqual(tracker.fence, zamalek)
    XCTAssertEqual(
      watch.calls, ["significant.start"],
      "the same region is left alone: restarting it could lose the crossing that relaunched the app")
    XCTAssertEqual(live.calls, ["updates.start"], "the updates start again")
  }

  func testARelaunchWatchesTheFenceAgainWhenIOSLostIt() {
    launch().start(fence: zamalek)
    let tracker = launch()  // no region monitored
    tracker.resumeIfOn()
    XCTAssertEqual(watch.calls, ["significant.start", "region.start"])
    XCTAssertEqual((watch.regions.first as? CLCircularRegion)?.radius, 200)
  }

  func testARelaunchOffShiftTouchesNothing() {
    let tracker = launch()
    tracker.resumeIfOn()
    XCTAssertTrue(watch.calls.isEmpty && live.calls.isEmpty)
  }

  // MARK: readings and the 14 minutes

  func testLeavingTheBranchAsksForOneReadingSentAtOnce() {
    let tracker = launch()
    let dart = FakeDart()
    tracker.attach(messenger: dart)
    tracker.start(fence: zamalek)
    let t0 = Date()
    tracker.take(at(30.0609, t0), wake: "interval", now: t0)
    tracker.locationManager(watch, didExitRegion: watch.regions.first!)
    // Delivered to every manager's delegate: asked once.
    tracker.locationManager(live, didExitRegion: watch.regions.first!)
    XCTAssertEqual(oneShot.calls, ["one"])
    XCTAssertEqual(tracker.pendingWake, "region_exit")
    let t1 = t0.addingTimeInterval(60)
    tracker.locationManager(oneShot, didUpdateLocations: [at(30.07, t1)])
    XCTAssertEqual(dart.fixes.map { $0["wake"] as? String }, ["interval", "region_exit"])
    XCTAssertNil(tracker.pendingWake)
  }

  func testOtherReadingsGoOncePer14Minutes() {
    let tracker = launch()
    let dart = FakeDart()
    tracker.attach(messenger: dart)
    tracker.start(fence: zamalek)
    let t0 = Date()
    tracker.take(at(30.0609, t0), wake: "interval", now: t0)
    tracker.take(at(30.0610, t0), wake: "interval", now: t0.addingTimeInterval(5 * 60))
    tracker.take(at(30.0700, t0), wake: "significant_change", now: t0.addingTimeInterval(13 * 60))
    XCTAssertEqual(dart.fixes.count, 1, "held back inside the 14 minutes")
    tracker.take(at(30.0611, t0), wake: "interval", now: t0.addingTimeInterval(14 * 60))
    XCTAssertEqual(dart.fixes.count, 2)
    XCTAssertEqual(tracker.cadence.wait(at: t0.addingTimeInterval(20 * 60)), 8 * 60)
  }

  func testNothingIsTakenOffShift() {
    let tracker = launch()
    tracker.take(at(30.0609), wake: "significant_change")
    XCTAssertTrue(tracker.queue.items.isEmpty)
  }

  // MARK: the queue

  func testTheQueueIsKeptAndCapped() {
    let tracker = launch()
    tracker.start(fence: zamalek)
    let t0 = Date()
    for i in 0..<25 {
      // Fence crossings go whatever the spacing.
      tracker.take(at(30 + Double(i) / 1000, t0), wake: "region_exit", now: t0)
    }
    XCTAssertEqual(tracker.queue.items.count, DawamFixQueue.cap)
    XCTAssertEqual(
      tracker.queue.items.first?["latitude"] as? Double ?? 0, 30.005, accuracy: 1e-9,
      "the oldest went first")
    // A relaunch finds them all.
    XCTAssertEqual(launch().queue.items.count, DawamFixQueue.cap)
  }

  func testReadingsWaitUntilTheDartSideListensThenFlush() {
    let tracker = launch()
    tracker.start(fence: zamalek)
    let t0 = Date()
    // Relaunched by leaving the branch: the reading comes before the engine.
    tracker.take(at(30.07, t0), wake: "region_exit", now: t0)
    XCTAssertEqual(tracker.queue.items.count, 1)
    XCTAssertTrue(tracker.isHoldingAwake, "the app stays awake for it")

    // The engine is up but the Dart side not yet listening.
    let dart = FakeDart()
    dart.listening = false
    tracker.attach(messenger: dart)
    XCTAssertEqual(dart.fixes.count, 1, "tried on attach")
    XCTAssertEqual(tracker.queue.items.count, 1, "kept: not implemented yet")

    // Dart registers its handler and asks for the flush.
    dart.listening = true
    dart.call("flush")
    XCTAssertEqual(dart.fixes.count, 2)
    XCTAssertEqual(dart.fixes.last?["wake"] as? String, "region_exit")
    XCTAssertNotNil(dart.fixes.last?["age_s"] as? Int)
    XCTAssertNil(dart.fixes.last?["at"], "the phone clock is not sent")
    XCTAssertTrue(tracker.queue.items.isEmpty, "answered: gone")
    XCTAssertFalse(tracker.isHoldingAwake, "nothing left: the app may sleep")
    XCTAssertEqual(time.begun, time.ended)
  }

  func testAReadingLeavesTheQueueOnlyWhenTheCoreHasIt() {
    let tracker = launch()
    let dart = FakeDart()
    dart.holdReplies = true
    tracker.attach(messenger: dart)
    tracker.start(fence: zamalek)
    tracker.take(at(30.07), wake: "region_exit")
    XCTAssertEqual(tracker.queue.items.count, 1, "the ping is still going")
    XCTAssertTrue(tracker.isHoldingAwake)
    dart.answerHeld()
    XCTAssertTrue(tracker.queue.items.isEmpty)
    XCTAssertFalse(tracker.isHoldingAwake)
  }

  func testAReadingSentBeforeDartListenedIsSentAgainOnItsFlush() {
    let tracker = launch()
    tracker.start(fence: zamalek)
    let dart = FakeDart()
    dart.holdReplies = true  // sent before the Dart side ran: no answer comes
    tracker.attach(messenger: dart)
    tracker.take(at(30.07), wake: "region_exit")
    XCTAssertEqual(dart.fixes.count, 1)
    // Dart listens now and asks for the flush.
    dart.holdReplies = false
    dart.call("flush")
    XCTAssertEqual(dart.fixes.count, 2, "sent again")
    XCTAssertEqual(
      Set(dart.fixes.compactMap { $0["id"] as? String }).count, 1,
      "the same reading: Dart knows the repeat by its id")
    XCTAssertTrue(tracker.queue.items.isEmpty)
    // The first send's answer arriving late changes nothing.
    dart.answerHeld()
    XCTAssertEqual(dart.fixes.count, 2)
    XCTAssertFalse(tracker.isHoldingAwake)
  }

  func testTheChannelStartsAndStops() {
    let tracker = launch()
    let dart = FakeDart()
    tracker.attach(messenger: dart)
    dart.call(
      "start",
      ["title": "Dawam", "text": "On shift", "fence": ["latitude": 30.0609, "longitude": 31.2197, "radius": 200]])
    XCTAssertTrue(tracker.isOn)
    XCTAssertEqual(tracker.fence, zamalek)
    dart.call("stop")
    XCTAssertFalse(tracker.isOn)
    XCTAssertTrue(watch.regions.isEmpty)
  }

  // MARK: which engine delivers

  func testTheRoute() {
    typealias R = DawamRoute
    // The app's Dart side listens: it takes every reading.
    for h in [DawamHeadlessState.none, .starting, .ready] {
      XCTAssertEqual(R.route(appListening: true, appAttached: true, headless: h, sceneless: true), .app)
    }
    // A headless engine that is up keeps going until the app listens.
    XCTAssertEqual(R.route(appListening: false, appAttached: true, headless: .ready, sceneless: false), .headless)
    XCTAssertEqual(R.route(appListening: false, appAttached: false, headless: .starting, sceneless: true), .wait)
    // The app's engine is up but not listening yet: tried, kept until its flush.
    XCTAssertEqual(R.route(appListening: false, appAttached: true, headless: .none, sceneless: false), .app)
    // No app engine: with no screen, headless; a screen means one is coming.
    XCTAssertEqual(R.route(appListening: false, appAttached: false, headless: .none, sceneless: true), .startHeadless)
    XCTAssertEqual(R.route(appListening: false, appAttached: false, headless: .none, sceneless: false), .wait)
  }

  func testWokenWithNoScreenTheHeadlessEnginePingsThenGoes() {
    sceneless = true
    launch().start(fence: zamalek)
    let tracker = launch()  // iOS relaunched the closed app for the fence
    tracker.resumeIfOn()
    tracker.wokenForLocation()
    XCTAssertEqual(engines.count, 1, "booting while iOS gets the reading")
    XCTAssertEqual(tracker.headlessState, .starting)
    XCTAssertTrue(tracker.isHoldingAwake)
    tracker.locationManager(watch, didExitRegion: watch.regions.first ?? zamalek.region(maximum: 1000))
    tracker.locationManager(oneShot, didUpdateLocations: [at(30.07)])
    XCTAssertTrue(engines[0].dart.fixes.isEmpty, "not before it says ready")

    engines[0].dart.call("ready")
    XCTAssertEqual(engines[0].dart.fixes.count, 1)
    let fix = engines[0].dart.fixes.first ?? [:]
    XCTAssertEqual(fix["wake"] as? String, "region_exit")
    XCTAssertEqual(fix["battery"] as? Int, 55)
    XCTAssertNil(fix["time"], "never the phone clock as GPS time")
    XCTAssertTrue(tracker.queue.items.isEmpty, "answered: gone")
    XCTAssertTrue(engines[0].destroyed, "its pings answered: torn down")
    XCTAssertEqual(tracker.headlessState, .none)
    XCTAssertFalse(tracker.isHoldingAwake)
  }

  func testTheIntervalReadingWithNoScreenStartsTheHeadlessEngine() {
    sceneless = true
    let tracker = launch()
    tracker.start(fence: zamalek)
    tracker.take(at(30.0609), wake: "interval")
    XCTAssertEqual(engines.count, 1)
    engines[0].dart.call("ready")
    XCTAssertEqual(engines[0].dart.fixes.count, 1)
    XCTAssertTrue(engines[0].destroyed)
    // The next one, 14 minutes on, boots a fresh engine.
    tracker.take(at(30.0609), wake: "interval", now: Date().addingTimeInterval(14 * 60))
    XCTAssertEqual(engines.count, 2)
  }

  func testWithAScreenNoHeadlessEngineStarts() {
    let tracker = launch()  // a screen is connected: the app's engine is coming
    tracker.start(fence: zamalek)
    tracker.take(at(30.07), wake: "region_exit")
    XCTAssertTrue(engines.isEmpty)
    XCTAssertEqual(tracker.queue.items.count, 1, "kept for the app's engine")
    let dart = FakeDart()
    tracker.attach(messenger: dart)
    dart.call("flush")
    XCTAssertEqual(dart.fixes.count, 1)
    XCTAssertTrue(engines.isEmpty)
  }

  func testTheAppsEngineTakesOverWithoutSendingAReadingTwice() {
    sceneless = true
    let tracker = launch()
    tracker.start(fence: zamalek)
    tracker.take(at(30.07), wake: "region_exit")
    let headless = engines[0]
    headless.dart.holdReplies = true  // its ping is still going
    headless.dart.call("ready")
    XCTAssertEqual(headless.dart.fixes.count, 1)

    // A screen connects: the app's engine attaches and listens.
    sceneless = false
    let app = FakeDart()
    tracker.attach(messenger: app)
    app.call("flush")
    XCTAssertTrue(app.fixes.isEmpty, "in flight on the headless engine: never sent to both")
    XCTAssertFalse(headless.destroyed, "left to finish")

    headless.dart.answerHeld()
    XCTAssertTrue(tracker.queue.items.isEmpty)
    XCTAssertTrue(headless.destroyed, "handed over")
    // What comes next goes to the app.
    tracker.take(at(30.0609), wake: "region_entry")
    XCTAssertEqual(app.fixes.count, 1)
    XCTAssertEqual(headless.dart.fixes.count, 1)
    XCTAssertEqual(engines.count, 1)
  }

  func testTheAppListeningFirstRetiresAnIdleHeadlessEngine() {
    sceneless = true
    let tracker = launch()
    tracker.start(fence: zamalek)
    tracker.wokenForLocation()
    XCTAssertEqual(tracker.headlessState, .starting)
    let app = FakeDart()
    tracker.attach(messenger: app)
    app.call("flush")
    XCTAssertTrue(engines[0].destroyed)
    tracker.take(at(30.07), wake: "region_exit")
    XCTAssertEqual(app.fixes.count, 1)
    XCTAssertTrue(engines[0].dart.fixes.isEmpty)
  }

  func testWhenTheAppsEngineGoesReadingsGoHeadless() {
    sceneless = true
    let tracker = launch()
    tracker.start(fence: zamalek)
    let app = FakeDart()
    var owner: NSObject? = NSObject()
    tracker.attach(messenger: app, owner: owner)
    app.call("flush")
    tracker.take(at(30.07), wake: "region_exit")
    XCTAssertEqual(app.fixes.count, 1)
    owner = nil  // the scene disconnected and its engine went
    tracker.take(at(30.0609), wake: "region_entry")
    XCTAssertEqual(app.fixes.count, 1)
    XCTAssertEqual(engines.count, 1)
    engines.first?.dart.call("ready")
    XCTAssertEqual(engines.first?.dart.fixes.count, 1)
  }

  func testTheHeadlessCoreSayingTheShiftIsOverStopsTracking() {
    sceneless = true
    let tracker = launch()
    tracker.start(fence: zamalek)
    tracker.take(at(30.07), wake: "region_exit")
    engines[0].dart.answer = false
    engines[0].dart.call("ready")
    XCTAssertFalse(tracker.isOn)
    XCTAssertTrue(watch.regions.isEmpty)
    XCTAssertEqual(live.calls.last, "updates.stop")
    XCTAssertTrue(engines[0].destroyed)
  }

  func testWokenOffShiftStartsNothing() {
    sceneless = true
    let tracker = launch()
    tracker.wokenForLocation()
    XCTAssertTrue(engines.isEmpty)
    XCTAssertFalse(tracker.isHoldingAwake)
  }

  func testAHeadlessEngineThatNeverAnswersIsNotSentToTwice() {
    sceneless = true
    let tracker = launch()
    tracker.start(fence: zamalek)
    tracker.take(at(30.07), wake: "region_exit")
    engines[0].dart.holdReplies = true
    engines[0].dart.call("ready")
    // Another reading while the first is in flight waits its turn.
    tracker.take(at(30.08), wake: "region_entry")
    XCTAssertEqual(engines[0].dart.fixes.count, 1)
    XCTAssertEqual(tracker.queue.items.count, 2)
    engines[0].dart.answerHeld()
    XCTAssertEqual(engines[0].dart.fixes.count, 2, "then the next, once")
  }

  func testTheDartAnswerIsReadRight() {
    XCTAssertTrue(DawamTracker.handled(true))
    XCTAssertTrue(DawamTracker.handled(nil))
    XCTAssertFalse(DawamTracker.handled(FlutterMethodNotImplemented))
    XCTAssertFalse(DawamTracker.handled(FlutterError(code: "x", message: nil, details: nil)))
  }
}
