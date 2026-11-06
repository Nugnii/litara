import Foundation

/// Хоткей: сочетание с клавишей (⌘L) либо «нажать и отпустить» одни модификаторы (⌥, ⌥⇧).
/// `flags` — биты модификаторов CGEventFlags (они же NSEvent.ModifierFlags).
public struct Hotkey: Equatable, Sendable {
    /// Код клавиши; `nil` — одни модификаторы.
    public let code: UInt16?
    public let flags: UInt64

    public static let shift: UInt64 = 1 << 17, control: UInt64 = 1 << 18, option: UInt64 = 1 << 19, command: UInt64 = 1 << 20

    public init(code: UInt16?, flags: UInt64) {
        self.code = code
        self.flags = flags
    }

    /// Запись 0.4.0 хранила ещё подпись — она не читается: подпись строится из кода.
    init?(_ dictionary: [String: Any]) {
        guard let flags = dictionary["flags"] as? Int else { return nil }
        self.init(code: (dictionary["code"] as? Int).map(UInt16.init), flags: UInt64(flags))
    }

    var dictionary: [String: Any] {
        var result: [String: Any] = ["flags": Int(flags)]
        if let code { result["code"] = Int(code) }
        return result
    }

    /// Хоткей из настроек Punto Switcher (перенос при первом запуске, docs/spec.md): `charKeycode` 666 — без
    /// клавиши, одни модификаторы; ни клавиши, ни модификаторов — не назначен.
    public init?(punto: [String: Any]) {
        guard let keycode = punto["charKeycode"] as? Int else { return nil }
        func used(_ key: String) -> Bool { (punto[key] as? Int ?? 0) != 0 }
        let flags = (used("isControlUsed") ? Self.control : 0) | (used("isAltUsed") ? Self.option : 0)
            | (used("isShiftUsed") ? Self.shift : 0) | (used("isCommandUsed") ? Self.command : 0)
        let code = keycode == 666 ? nil : UInt16(exactly: keycode)
        guard code != nil || flags != 0 else { return nil }
        self.init(code: code, flags: flags)
    }

    /// «⌃⌥⇧⌘» в порядке меню macOS, затем клавиша.
    public func label(key: String) -> String {
        (flags & Self.control != 0 ? "⌃" : "") + (flags & Self.option != 0 ? "⌥" : "")
            + (flags & Self.shift != 0 ? "⇧" : "") + (flags & Self.command != 0 ? "⌘" : "") + key
    }
}

/// Действия с хоткеем (docs/spec.md).
public enum HotkeyAction: String, CaseIterable, Sendable {
    case fix, nextLayout, changeCase, transliterate, toggleAutoCorrect

    /// docs/spec.md «Хоткеи по умолчанию»: регистр и транслит без сочетания (⌘L в браузерах занят адресной
    /// строкой); ⌘L владельца приходит переносом из Punto.
    public var defaultHotkey: Hotkey? {
        switch self {
        case .fix: Hotkey(code: nil, flags: Hotkey.option)
        case .nextLayout: Hotkey(code: nil, flags: Hotkey.option | Hotkey.shift)
        // автопереключение вкл/выкл — по умолчанию не назначен (просьба владельца 2026-10-21)
        case .changeCase, .transliterate, .toggleAutoCorrect: nil
        }
    }

    /// Ключ этого действия в настройках Punto Switcher; `nil` — у Punto такого нет.
    public var puntoKey: String? {
        switch self {
        case .fix: "shortcutChangeLayout"
        case .changeCase: "shortcutChangeCase"
        case .toggleAutoCorrect: "shortcutSwitchAutocorrection"
        case .nextLayout, .transliterate: nil
        }
    }
}

extension UserDefaults {
    /// Хоткей действия. Снятый хранится пустым словарём: иначе после перезапуска вернулось бы умолчание.
    public func hotkey(_ action: HotkeyAction) -> Hotkey? {
        guard let stored = dictionary(forKey: action.rawValue + "Hotkey") else { return action.defaultHotkey }
        return Hotkey(stored)
    }

    public func setHotkey(_ hotkey: Hotkey?, for action: HotkeyAction) {
        set(hotkey?.dictionary ?? [:], forKey: action.rawValue + "Hotkey")
    }
}

/// Запись хоткея по нажатиям (окно настроек): сочетание с ⌘, ⌃ или ⌥ — либо одни модификаторы, нажатые и
/// отпущенные (⌥, ⌥⇧). Esc — отмена. ⇧ сам по себе и клавиша без ⌘⌃⌥ — не хоткей: запись ждёт дальше.
public struct HotkeyRecorder {
    public enum Outcome: Equatable { case wait, cancel, done(Hotkey) }

    /// Модификаторы, нажатые с тех пор, как все были отпущены.
    private var peak: UInt64 = 0

    public init() {}

    /// Модификаторы сменились; `flags` — нажатые сейчас (только ⌘⌃⌥⇧).
    public mutating func modifiers(_ flags: UInt64) -> Outcome {
        peak |= flags
        guard flags == 0 else { return .wait }
        defer { peak = 0 }
        return Self.outcome(Hotkey(code: nil, flags: peak))
    }

    public mutating func key(_ code: UInt16, flags: UInt64) -> Outcome {
        code == 53 && flags == 0 ? .cancel : Self.outcome(Hotkey(code: code, flags: flags))
    }

    private static func outcome(_ hotkey: Hotkey) -> Outcome {
        hotkey.flags & (Hotkey.command | Hotkey.control | Hotkey.option) != 0 ? .done(hotkey) : .wait
    }
}
