import Foundation

/// Controller-side utility settings.
///
/// Each setting is written with a vendor control request on the default pipe:
/// `bmRequestType = 0x40, bRequest = 0x03, wValue = value << 8, wIndex = selector, wLength = 0`.
/// The device does not report the values back, which is why the original stores them in
/// `~/Library/Preferences/com.pioneerdj.DDJ-FLX10autosetup.plist` and re-sends all of them
/// whenever the controller connects.
public enum ControllerSetting: CaseIterable, Hashable, Sendable {
    case slipModeFlashing
    case slipButtonLED
    case faderStartSync
    case jogRingColor
    case timeMode
    case virtualDeckMode
    case recOut

    /// `wIndex` selector (from the framework's Set*Setting helpers).
    public var selector: UInt16 {
        switch self {
        case .faderStartSync: return 0xC013
        case .recOut: return 0xC01D
        case .timeMode: return 0xC026
        case .virtualDeckMode: return 0xC027
        case .slipModeFlashing: return 0xC028
        case .slipButtonLED: return 0xC029
        case .jogRingColor: return 0xC02B
        }
    }

    /// Key in the original autosetup plist (values stored as decimal strings).
    public var legacyKey: String {
        switch self {
        case .slipModeFlashing: return "slipModeFlashing"
        case .slipButtonLED: return "slipModeButtonSetting"
        case .faderStartSync: return "faderStartOptionIndex"
        case .jogRingColor: return "jogRingColorIndex"
        case .timeMode: return "timeDisplayFormat"
        case .virtualDeckMode: return "virtualDeckModeCheckbutton"
        case .recOut: return "recOutIndex"
        }
    }
}

public enum SlipModeFlashing: UInt8, CaseIterable, Codable, Sendable {
    case disable = 0
    case enable = 1
}

public enum SlipButtonLED: UInt8, CaseIterable, Codable, Sendable {
    case light = 0
    case blink = 1
}

/// The original exposes a "Turn on SYNC on each deck when the Fader Start begins" checkbox.
/// Checked sends 1 and unchecked sends 2; 0 is sent only while that checkbox is disabled.
public enum FaderStartSync: UInt8, CaseIterable, Codable, Sendable {
    case on = 1
    case off = 2
}

public enum JogRingColor: UInt8, CaseIterable, Codable, Sendable {
    case mode1 = 0
    case mode2 = 1
    case mode3 = 2
}

public enum TimeMode: UInt8, CaseIterable, Codable, Sendable {
    case elapsed = 0
    case remaining = 1
}

public enum VirtualDeckMode: UInt8, CaseIterable, Codable, Sendable {
    case off = 0
    case on = 1
}

public enum RecOut: UInt8, CaseIterable, Codable, Sendable {
    case withMic = 0
    case withoutMic = 1
}

/// Which DJ software the controller is used with. Only stored locally; rekordbox users configure
/// these options from rekordbox's own preferences instead.
public enum DJSoftware: Int, CaseIterable, Codable, Sendable {
    case rekordbox = 0
    case seratoDJPro = 1
}

public struct ControllerSettings: Equatable, Codable, Sendable {
    public var slipModeFlashing: SlipModeFlashing = .enable
    public var slipButtonLED: SlipButtonLED = .light
    public var faderStartSync: FaderStartSync = .off
    public var jogRingColor: JogRingColor = .mode1
    public var timeMode: TimeMode = .remaining
    public var virtualDeckMode: VirtualDeckMode = .on
    public var recOut: RecOut = .withMic
    public var software: DJSoftware = .seratoDJPro

    /// Defaults match `-[AudioSetup executeSetValueCommand]` when no value has been saved.
    public init() {}

    public func deviceValue(for setting: ControllerSetting) -> UInt8 {
        switch setting {
        case .slipModeFlashing: return slipModeFlashing.rawValue
        case .slipButtonLED: return slipButtonLED.rawValue
        case .faderStartSync: return faderStartSync.rawValue
        case .jogRingColor: return jogRingColor.rawValue
        case .timeMode: return timeMode.rawValue
        case .virtualDeckMode: return virtualDeckMode.rawValue
        case .recOut: return recOut.rawValue
        }
    }

    /// Reads the original Setup utility's plist, applying the same range checks and fallbacks.
    public init(legacyPlist dictionary: [String: Any]) {
        self.init()
        func int(_ key: String) -> Int? {
            if let string = dictionary[key] as? String { return Int(string) }
            return dictionary[key] as? Int
        }
        if let v = int(ControllerSetting.slipModeFlashing.legacyKey), let e = SlipModeFlashing(rawValue: UInt8(clamping: v)) { slipModeFlashing = e }
        if let v = int(ControllerSetting.slipButtonLED.legacyKey), let e = SlipButtonLED(rawValue: UInt8(clamping: v)) { slipButtonLED = e }
        // Stored as the checkbox state: 3 = enabled+checked, 2 = enabled+unchecked, 0/1 = disabled.
        if let v = int(ControllerSetting.faderStartSync.legacyKey) { faderStartSync = v == 3 ? .on : .off }
        if let v = int(ControllerSetting.jogRingColor.legacyKey), let e = JogRingColor(rawValue: UInt8(clamping: v)) { jogRingColor = e }
        if let v = int(ControllerSetting.timeMode.legacyKey), let e = TimeMode(rawValue: UInt8(clamping: v)) { timeMode = e }
        if let v = int(ControllerSetting.virtualDeckMode.legacyKey), let e = VirtualDeckMode(rawValue: UInt8(clamping: v)) { virtualDeckMode = e }
        if let v = int(ControllerSetting.recOut.legacyKey), let e = RecOut(rawValue: UInt8(clamping: v)) { recOut = e }
        if let v = int("softwarePulldownIndex"), let e = DJSoftware(rawValue: v) { software = e }
    }

    public static var legacyPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.pioneerdj.DDJ-FLX10autosetup.plist")
    }
}

/// Persists settings in the app's own defaults, seeding them once from the original utility.
public final class SettingsStore {
    private let defaults: UserDefaults
    private let key = "controllerSettings"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> ControllerSettings {
        if let data = defaults.data(forKey: key), let settings = try? JSONDecoder().decode(ControllerSettings.self, from: data) {
            return settings
        }
        if let legacy = NSDictionary(contentsOf: ControllerSettings.legacyPlistURL) as? [String: Any] {
            return ControllerSettings(legacyPlist: legacy)
        }
        return ControllerSettings()
    }

    public func save(_ settings: ControllerSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
    }
}
