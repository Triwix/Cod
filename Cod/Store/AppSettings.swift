import Combine
import SwiftUI

enum HistoryLimit: Int, CaseIterable, Identifiable, Codable {
    case off = 0
    case ten = 10
    case twenty = 20
    case fifty = 50
    case unlimited = -1

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .unlimited: return "Unlimited"
        default: return "\(rawValue)"
        }
    }
}

enum HistoryRetentionPolicy {
    static func removalCount(total: Int, limit: HistoryLimit) -> Int {
        guard limit != .unlimited else { return 0 }
        return max(0, total - max(0, limit.rawValue))
    }
}

/// What happens the moment a capture arrives.
enum ArrivalMode: String, CaseIterable, Identifiable, Codable {
    /// Drop straight into the crop surface (Snapper's normal mode).
    case selection
    /// Skip selection and fire the instant action on the whole image.
    case instant
    /// Land in the library and let the user choose.
    case library

    var id: String { rawValue }

    var label: String {
        switch self {
        case .selection: return "Select a region"
        case .instant: return "Instant action"
        case .library: return "Open library"
        }
    }

    var detail: String {
        switch self {
        case .selection: return "Open the crop surface so you can draw a region."
        case .instant: return "Run the instant action on the full image immediately."
        case .library: return "Just file it away; decide what to do later."
        }
    }
}

enum OCRAccuracy: String, CaseIterable, Identifiable, Codable {
    case fast
    case accurate

    var id: String { rawValue }
    var label: String { self == .fast ? "Fast" : "Accurate" }
    var detail: String {
        self == .fast
            ? "Lower latency, good for large blocks of clean text."
            : "Slower but far better on small, stylised or noisy text."
    }
}

enum PinShadow: String, CaseIterable, Identifiable, Codable {
    case none
    case black
    case white

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var color: Color? {
        switch self {
        case .none: return nil
        case .black: return .black
        case .white: return .white
        }
    }
}

/// User-facing preferences, including the optional setup tip.
/// Backed by `UserDefaults`; each setter writes through immediately.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults: UserDefaults
    private let sharePreferences: ShareFloatPreferenceStore

    init(defaults: UserDefaults = .standard, sharePreferences: ShareFloatPreferenceStore = SharePreferences.shared) {
        self.defaults = defaults
        self.sharePreferences = sharePreferences
        self.oneTapFloat = sharePreferences.oneTapFloat
        self.useFloatNotification = sharePreferences.useFloatNotification
        self.arrivalMode = defaults.decode(ArrivalMode.self, forKey: Keys.arrivalMode) ?? .selection
        let storedInstant = defaults.decode(SnapAction.self, forKey: Keys.instantAction) ?? .copyImage
        self.instantAction = SnapAction.availableCases.contains(storedInstant) ? storedInstant : .float
        // Preserve the user's ordering, but make sure actions added in a later
        // version still show up instead of silently going missing.
        let storedOrder = defaults.decode([SnapAction].self, forKey: Keys.actionOrder) ?? SnapAction.defaultOrder
        self.actionOrder = (storedOrder + SnapAction.defaultOrder.filter { !storedOrder.contains($0) }).filter(SnapAction.availableCases.contains)
        self.enabledActions = (defaults.decode(Set<SnapAction>.self, forKey: Keys.enabledActions) ?? SnapAction.defaultEnabled).intersection(SnapAction.availableCases)
        self.historyLimit = defaults.decode(HistoryLimit.self, forKey: Keys.historyLimit) ?? .ten
        self.ocrAccuracy = defaults.decode(OCRAccuracy.self, forKey: Keys.ocrAccuracy) ?? .accurate
        self.ocrLanguages = defaults.decode([String].self, forKey: Keys.ocrLanguages) ?? ["en-US"]
        self.ocrLanguageCorrection = defaults.object(forKey: Keys.ocrLanguageCorrection) as? Bool ?? true
        self.pinShadow = defaults.decode(PinShadow.self, forKey: Keys.pinShadow) ?? .black
        self.pinOpacity = defaults.object(forKey: Keys.pinOpacity) as? Double ?? 1.0
        self.pinCornerRadius = defaults.object(forKey: Keys.pinCornerRadius) as? Double ?? 10
        self.keepOtherAudioPlaying = defaults.object(forKey: Keys.keepOtherAudioPlaying) as? Bool ?? true
        self.captureDelay = defaults.object(forKey: Keys.captureDelay) as? Double ?? 0
        self.saveToDedicatedAlbum = defaults.object(forKey: Keys.saveToDedicatedAlbum) as? Bool ?? false
        self.albumName = defaults.string(forKey: Keys.albumName) ?? "Cod"
        self.autoCopyOnCapture = defaults.object(forKey: Keys.autoCopyOnCapture) as? Bool ?? false
        self.watchScreenshots = defaults.object(forKey: Keys.watchScreenshots) as? Bool ?? true
        self.hapticsEnabled = defaults.object(forKey: Keys.hapticsEnabled) as? Bool ?? true
        self.smartRegions = defaults.object(forKey: Keys.smartRegions) as? Bool ?? true
        self.showMagnifier = defaults.object(forKey: Keys.showMagnifier) as? Bool ?? true
        self.lastSeenScreenshotID = defaults.string(forKey: Keys.lastSeenScreenshotID)
        self.hasDismissedFloatSetupTip = defaults.bool(forKey: Keys.hasDismissedFloatSetupTip)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-float-setup") {
            self.hasDismissedFloatSetupTip = false
        }
        #endif
    }

    // MARK: - Activation

    @Published var arrivalMode: ArrivalMode { didSet { defaults.encode(arrivalMode, forKey: Keys.arrivalMode) } }
    @Published var instantAction: SnapAction { didSet { defaults.encode(instantAction, forKey: Keys.instantAction) } }
    @Published var watchScreenshots: Bool { didSet { defaults.set(watchScreenshots, forKey: Keys.watchScreenshots) } }
    @Published var captureDelay: Double { didSet { defaults.set(captureDelay, forKey: Keys.captureDelay) } }
    /// A dismissed tip isn't proof that iOS installed the Shortcut. Installation
    /// stays user-controlled, and the installer remains available in the guide.
    @Published var hasDismissedFloatSetupTip: Bool {
        didSet { defaults.set(hasDismissedFloatSetupTip, forKey: Keys.hasDismissedFloatSetupTip) }
    }

    /// On by default: skip cropping when the prepared share opens in Cod.
    @Published private(set) var oneTapFloat: Bool
    @Published private(set) var useFloatNotification: Bool
    @Published var sharePreferenceError: String?

    func setOneTapFloat(_ enabled: Bool) {
        guard sharePreferences.setOneTapFloat(enabled) else {
            sharePreferenceError = "Couldn't save the share-sheet setting. Please try again."
            return
        }
        oneTapFloat = enabled
        sharePreferenceError = nil
    }

    func setUseFloatNotification(_ enabled: Bool) {
        guard sharePreferences.setUseFloatNotification(enabled) else {
            sharePreferenceError = "Couldn't save the notification setting. Please try again."
            return
        }
        useFloatNotification = enabled
        sharePreferenceError = nil
    }

    // MARK: - Actions

    @Published var actionOrder: [SnapAction] { didSet { defaults.encode(actionOrder, forKey: Keys.actionOrder) } }
    @Published var enabledActions: Set<SnapAction> { didSet { defaults.encode(enabledActions, forKey: Keys.enabledActions) } }

    /// The action bar, in user order, filtered to what's turned on.
    var visibleActions: [SnapAction] { actionOrder.filter { enabledActions.contains($0) && SnapAction.availableCases.contains($0) } }

    // MARK: - Recognition

    @Published var ocrAccuracy: OCRAccuracy { didSet { defaults.encode(ocrAccuracy, forKey: Keys.ocrAccuracy) } }
    @Published var ocrLanguages: [String] { didSet { defaults.encode(ocrLanguages, forKey: Keys.ocrLanguages) } }
    @Published var ocrLanguageCorrection: Bool { didSet { defaults.set(ocrLanguageCorrection, forKey: Keys.ocrLanguageCorrection) } }

    // MARK: - History

    @Published var historyLimit: HistoryLimit { didSet { defaults.encode(historyLimit, forKey: Keys.historyLimit) } }

    // MARK: - Pins

    @Published var pinShadow: PinShadow { didSet { defaults.encode(pinShadow, forKey: Keys.pinShadow) } }
    @Published var pinOpacity: Double { didSet { defaults.set(pinOpacity, forKey: Keys.pinOpacity) } }
    @Published var pinCornerRadius: Double { didSet { defaults.set(pinCornerRadius, forKey: Keys.pinCornerRadius) } }

    /// Floating needs an active audio session. Declaring it mixable leaves your
    /// music playing, but makes Cod a secondary audio app, which can cost it
    /// the background time the floating window needs to survive.
    @Published var keepOtherAudioPlaying: Bool {
        didSet { defaults.set(keepOtherAudioPlaying, forKey: Keys.keepOtherAudioPlaying) }
    }

    // MARK: - Saving

    @Published var saveToDedicatedAlbum: Bool { didSet { defaults.set(saveToDedicatedAlbum, forKey: Keys.saveToDedicatedAlbum) } }
    @Published var albumName: String { didSet { defaults.set(albumName, forKey: Keys.albumName) } }
    @Published var autoCopyOnCapture: Bool { didSet { defaults.set(autoCopyOnCapture, forKey: Keys.autoCopyOnCapture) } }

    // MARK: - Feel

    @Published var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Keys.hapticsEnabled) } }
    @Published var smartRegions: Bool { didSet { defaults.set(smartRegions, forKey: Keys.smartRegions) } }
    @Published var showMagnifier: Bool { didSet { defaults.set(showMagnifier, forKey: Keys.showMagnifier) } }

    /// Local identifier of the newest screenshot we've already offered, so we
    /// don't re-surface the same one every time the app comes forward.
    @Published var lastSeenScreenshotID: String? {
        didSet { defaults.set(lastSeenScreenshotID, forKey: Keys.lastSeenScreenshotID) }
    }

    func resetActions() {
        actionOrder = SnapAction.defaultOrder.filter(SnapAction.availableCases.contains)
        enabledActions = SnapAction.defaultEnabled
    }

    private enum Keys {
        static let arrivalMode = "arrivalMode"
        static let instantAction = "instantAction"
        static let actionOrder = "actionOrder"
        static let enabledActions = "enabledActions"
        static let historyLimit = "historyLimit"
        static let ocrAccuracy = "ocrAccuracy"
        static let ocrLanguages = "ocrLanguages"
        static let ocrLanguageCorrection = "ocrLanguageCorrection"
        static let pinShadow = "pinShadow"
        static let pinOpacity = "pinOpacity"
        static let pinCornerRadius = "pinCornerRadius"
        static let keepOtherAudioPlaying = "keepOtherAudioPlaying"
        static let captureDelay = "captureDelay"
        static let saveToDedicatedAlbum = "saveToDedicatedAlbum"
        static let albumName = "albumName"
        static let autoCopyOnCapture = "autoCopyOnCapture"
        static let watchScreenshots = "watchScreenshots"
        static let hapticsEnabled = "hapticsEnabled"
        static let smartRegions = "smartRegions"
        static let showMagnifier = "showMagnifier"
        static let lastSeenScreenshotID = "lastSeenScreenshotID"
        static let hasDismissedFloatSetupTip = "hasDismissedFloatSetupTip"
    }
}

private extension UserDefaults {
    func encode<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        set(data, forKey: key)
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
