import CoreLocation
import Darwin
import UIKit

/// One reading for the System Monitor tool. Everything comes from public,
/// on-device APIs; nothing is sent anywhere.
struct SystemMetrics: Equatable {
  /// 0...1, or nil when iOS doesn't report a level (for example, the Simulator).
  var batteryLevel: Double?
  var batteryState: UIDevice.BatteryState = .unknown
  var thermalState: ProcessInfo.ThermalState = .nominal
  /// Bytes per second across Wi-Fi and cellular, nil until two samples exist.
  var downloadRate: Double?
  var uploadRate: Double?
  /// Meters per second from Core Location, nil when unavailable or off.
  var speed: Double?

  static let placeholder = SystemMetrics()

  var batteryText: String {
    guard let batteryLevel else { return "—" }
    let percent = Int((min(1, max(0, batteryLevel)) * 100).rounded())
    switch batteryState {
    case .charging: return "\(percent)% ⚡︎"
    case .full: return "Full"
    default: return "\(percent)%"
    }
  }

  var thermalText: String {
    switch thermalState {
    case .nominal: return "Cool"
    case .fair: return "Warm"
    case .serious: return "Hot"
    case .critical: return "Very hot"
    @unknown default: return "—"
    }
  }

  static func rateText(_ bytesPerSecond: Double?) -> String {
    guard let value = bytesPerSecond, value.isFinite, value >= 0 else { return "—" }
    let units = ["B/s", "KB/s", "MB/s", "GB/s"]
    var scaled = value
    var unit = 0
    while scaled >= 1_000, unit < units.count - 1 {
      scaled /= 1_000
      unit += 1
    }
    let digits = unit == 0 || scaled >= 100 ? 0 : 1
    return String(format: "%.\(digits)f %@", scaled, units[unit])
  }

  func speedText(metric: Bool) -> String {
    guard let speed, speed.isFinite, speed >= 0 else { return "—" }
    let value = metric ? speed * 3.6 : speed * 2.236_936
    return "\(Int(value.rounded())) \(metric ? "km/h" : "mph")"
  }
}

/// Byte counters for one moment, summed over active Wi-Fi and cellular links.
struct NetworkCounters: Equatable {
  var received: UInt64
  var sent: UInt64
  var at: TimeInterval

  /// Rates between two readings. Interface counters are 32-bit and can wrap,
  /// and links can reset, so a negative step counts as "no data", not a spike.
  static func rates(from old: NetworkCounters, to new: NetworkCounters) -> (down: Double, up: Double)? {
    let interval = new.at - old.at
    guard interval > 0.2, interval.isFinite else { return nil }
    func step(_ a: UInt64, _ b: UInt64) -> Double { b >= a ? Double(b - a) / interval : 0 }
    return (step(old.received, new.received), step(old.sent, new.sent))
  }

  static func read(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> NetworkCounters? {
    var first: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&first) == 0, let start = first else { return nil }
    defer { freeifaddrs(first) }
    var received: UInt64 = 0
    var sent: UInt64 = 0
    var cursor: UnsafeMutablePointer<ifaddrs>? = start
    while let entry = cursor {
      defer { cursor = entry.pointee.ifa_next }
      let flags = Int32(entry.pointee.ifa_flags)
      guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
        let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
        let data = entry.pointee.ifa_data
      else { continue }
      let name = String(cString: entry.pointee.ifa_name)
      // en* is Wi-Fi/Ethernet; pdp_ip* is cellular. Skip VPN/tunnel duplicates.
      guard name.hasPrefix("en") || name.hasPrefix("pdp_ip") else { continue }
      let stats = data.assumingMemoryBound(to: if_data.self).pointee
      received += UInt64(stats.ifi_ibytes)
      sent += UInt64(stats.ifi_obytes)
    }
    return NetworkCounters(received: received, sent: sent, at: time)
  }
}

/// Samples once a second while a System Monitor is floating. Rendering can
/// happen off the main thread, so the latest reading is lock-protected.
final class SystemMetricsSampler: NSObject, CLLocationManagerDelegate {
  static let shared = SystemMetricsSampler()

  private let lock = NSLock()
  private var stored = SystemMetrics.placeholder
  private var lastCounters: NetworkCounters?
  private var timer: Timer?
  private var users = 0
  private var location: CLLocationManager?

  var latest: SystemMetrics {
    lock.lock(); defer { lock.unlock() }
    return stored
  }

  private func update(_ change: (inout SystemMetrics) -> Void) {
    lock.lock(); change(&stored); lock.unlock()
  }

  /// Balanced with `stop`. The speedometer asks for location only when the
  /// user turned it on for this monitor.
  @MainActor func start(includeSpeed: Bool) {
    users += 1
    UIDevice.current.isBatteryMonitoringEnabled = true
    sample()
    if timer == nil {
      let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.sample() }
      }
      RunLoop.main.add(timer, forMode: .common)
      self.timer = timer
    }
    if includeSpeed { startSpeed() }
  }

  @MainActor func stop() {
    users = max(0, users - 1)
    guard users == 0 else { return }
    timer?.invalidate()
    timer = nil
    lastCounters = nil
    location?.stopUpdatingLocation()
    location = nil
    UIDevice.current.isBatteryMonitoringEnabled = false
    update { $0 = .placeholder }
  }

  @MainActor private func sample() {
    let device = UIDevice.current
    let level = device.batteryLevel
    let counters = NetworkCounters.read()
    let rates = zip(lastCounters, counters).flatMap { NetworkCounters.rates(from: $0, to: $1) }
    if let counters { lastCounters = counters }
    update {
      $0.batteryLevel = level >= 0 ? Double(level) : nil
      $0.batteryState = device.batteryState
      $0.thermalState = ProcessInfo.processInfo.thermalState
      if let rates {
        $0.downloadRate = rates.down
        $0.uploadRate = rates.up
      }
    }
  }

  @MainActor private func startSpeed() {
    guard location == nil else { return }
    let manager = CLLocationManager()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    manager.activityType = .otherNavigation
    location = manager
    switch manager.authorizationStatus {
    case .notDetermined: manager.requestWhenInUseAuthorization()
    case .authorizedWhenInUse, .authorizedAlways: beginLocationUpdates(manager)
    default: break
    }
  }

  @MainActor private func beginLocationUpdates(_ manager: CLLocationManager) {
    // Floating means Cod is in the background. Keep updates flowing only while
    // the monitor floats; iOS shows the location indicator meanwhile.
    manager.allowsBackgroundLocationUpdates = true
    manager.showsBackgroundLocationIndicator = true
    manager.pausesLocationUpdatesAutomatically = false
    manager.startUpdatingLocation()
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    Task { @MainActor in
      guard manager === self.location else { return }
      switch manager.authorizationStatus {
      case .authorizedWhenInUse, .authorizedAlways: self.beginLocationUpdates(manager)
      default: self.update { $0.speed = nil }
      }
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let last = locations.last else { return }
    update { $0.speed = last.speed >= 0 ? last.speed : nil }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    update { $0.speed = nil }
  }
}

private func zip<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
  guard let a, let b else { return nil }
  return (a, b)
}
