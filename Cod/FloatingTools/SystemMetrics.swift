import CoreLocation
import Darwin
import Network
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
  var connection: String?
  var freeStorage: Int64?
  var memoryUsed: UInt64?
  var memoryTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
  /// 0...1 across all cores, nil until two samples exist.
  var cpuUsage: Double?
  var lowPowerMode = false

  static let placeholder = SystemMetrics()

  func text(for metric: SystemMetric) -> String {
    switch metric {
    case .battery: return batteryText
    case .temperature: return thermalText
    case .download: return Self.rateText(downloadRate)
    case .upload: return Self.rateText(uploadRate)
    case .connection: return connection ?? "—"
    case .storage: return freeStorage.map { "\(Self.bytesText(Double($0))) free" } ?? "—"
    case .memory:
      guard let memoryUsed, memoryTotal > 0 else { return "—" }
      return "\(Self.gigabytes(memoryUsed)) / \(Self.gigabytes(memoryTotal)) GB"
    case .cpu:
      guard let cpuUsage, cpuUsage.isFinite else { return "—" }
      return "\(Int((min(1, max(0, cpuUsage)) * 100).rounded()))%"
    case .lowPower: return lowPowerMode ? "On" : "Off"
    }
  }

  static func bytesText(_ bytes: Double) -> String {
    guard bytes.isFinite, bytes >= 0 else { return "—" }
    let units = ["B", "KB", "MB", "GB", "TB"]
    var scaled = bytes
    var unit = 0
    while scaled >= 1_000, unit < units.count - 1 {
      scaled /= 1_000
      unit += 1
    }
    let digits = unit < 2 || scaled >= 100 ? 0 : 1
    return String(format: "%.\(digits)f %@", scaled, units[unit])
  }

  static func gigabytes(_ bytes: UInt64) -> String {
    let value = Double(bytes) / 1_073_741_824
    return value >= 10 ? String(format: "%.0f", value) : String(format: "%.1f", value)
  }

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

/// Busy and total CPU ticks summed over every core.
struct CPUTicks: Equatable {
  var busy: UInt64
  var total: UInt64

  /// Share of time the CPU was busy between two readings. Counters that went
  /// backwards (a core went offline) count as "no data".
  static func usage(from old: CPUTicks, to new: CPUTicks) -> Double? {
    guard new.total > old.total, new.busy >= old.busy else { return nil }
    return min(1, Double(new.busy - old.busy) / Double(new.total - old.total))
  }

  static func read() -> CPUTicks? {
    var cores: natural_t = 0
    var info: processor_info_array_t?
    var count: mach_msg_type_number_t = 0
    guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cores, &info, &count) == KERN_SUCCESS,
      let info
    else { return nil }
    defer {
      vm_deallocate(
        mach_task_self_, vm_address_t(UInt(bitPattern: info)),
        vm_size_t(Int(count) * MemoryLayout<integer_t>.stride))
    }
    var busy: UInt64 = 0
    var total: UInt64 = 0
    for core in 0..<Int(cores) {
      let base = core * Int(CPU_STATE_MAX)
      func ticks(_ state: Int32) -> UInt64 { UInt64(UInt32(bitPattern: info[base + Int(state)])) }
      let working = ticks(CPU_STATE_USER) + ticks(CPU_STATE_SYSTEM) + ticks(CPU_STATE_NICE)
      busy += working
      total += working + ticks(CPU_STATE_IDLE)
    }
    return CPUTicks(busy: busy, total: total)
  }
}

enum DeviceReadings {
  /// Active, wired and compressed memory: what the system is holding on to.
  static func memoryUsed() -> UInt64? {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
    let result = withUnsafeMutablePointer(to: &stats) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }
    var pageSize: vm_size_t = 0
    guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
    let pages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
    return pages * UInt64(pageSize)
  }

  /// Space available for things people choose to keep, as Settings reports
  /// it. Declared in the privacy manifest (reason 85F4.1: shown to the user).
  static func freeStorage() -> Int64? {
    let home = URL(fileURLWithPath: NSHomeDirectory())
    return try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      .volumeAvailableCapacityForImportantUsage
  }

  static func connectionText(_ path: NWPath) -> String {
    guard path.status == .satisfied else { return "Offline" }
    if path.usesInterfaceType(.wifi) { return "Wi-Fi" }
    if path.usesInterfaceType(.cellular) { return "Cellular" }
    if path.usesInterfaceType(.wiredEthernet) { return "Ethernet" }
    return "Online"
  }
}

/// Samples once a second while a System Monitor is floating. Rendering can
/// happen off the main thread, so the latest reading is lock-protected.
/// Off-main callbacks touch only the lock-protected reading via `update`;
/// everything else runs on the main actor.
final class SystemMetricsSampler: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
  static let shared = SystemMetricsSampler()

  private let lock = NSLock()
  private var stored = SystemMetrics.placeholder
  private var lastCounters: NetworkCounters?
  private var timer: Timer?
  private var users = 0
  private var location: CLLocationManager?
  private var speedUsers = 0
  private var lastTicks: CPUTicks?
  private var tick = 0
  private var pathMonitor: NWPathMonitor?

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
    if pathMonitor == nil {
      let monitor = NWPathMonitor()
      monitor.pathUpdateHandler = { [weak self] path in
        let text = DeviceReadings.connectionText(path)
        self?.update { $0.connection = text }
      }
      monitor.start(queue: DispatchQueue(label: "cod.system.connection", qos: .utility))
      pathMonitor = monitor
    }
    if includeSpeed {
      speedUsers += 1
      startSpeed()
    }
  }

  /// Pass the same `includeSpeed` given to the matching `start`.
  @MainActor func stop(includeSpeed: Bool = false) {
    if includeSpeed {
      speedUsers = max(0, speedUsers - 1)
      if speedUsers == 0 {
        location?.stopUpdatingLocation()
        location = nil
        update { $0.speed = nil }
      }
    }
    users = max(0, users - 1)
    guard users == 0 else { return }
    timer?.invalidate()
    timer = nil
    lastCounters = nil
    lastTicks = nil
    tick = 0
    pathMonitor?.cancel()
    pathMonitor = nil
    location?.stopUpdatingLocation()
    location = nil
    speedUsers = 0
    UIDevice.current.isBatteryMonitoringEnabled = false
    update { $0 = .placeholder }
  }

  @MainActor private func sample() {
    let device = UIDevice.current
    let level = device.batteryLevel
    let counters = NetworkCounters.read()
    let rates = zip(lastCounters, counters).flatMap { NetworkCounters.rates(from: $0, to: $1) }
    if let counters { lastCounters = counters }
    let ticks = CPUTicks.read()
    let cpu = zip(lastTicks, ticks).flatMap { CPUTicks.usage(from: $0, to: $1) }
    if let ticks { lastTicks = ticks }
    // Storage changes slowly; asking every ten seconds is plenty.
    let storage = tick % 10 == 0 ? DeviceReadings.freeStorage() : nil
    tick += 1
    let memory = DeviceReadings.memoryUsed()
    let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    update {
      if let cpu { $0.cpuUsage = cpu }
      if let storage { $0.freeStorage = storage }
      $0.memoryUsed = memory
      $0.lowPowerMode = lowPower
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
    // GPS-grade accuracy is enough for speed; the navigation level is meant
    // for a plugged-in device and costs more battery.
    manager.desiredAccuracy = kCLLocationAccuracyBest
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
