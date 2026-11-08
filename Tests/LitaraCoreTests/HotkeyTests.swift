import Foundation
import Testing
@testable import LitaraCore

@Test func hotkeyStorage() throws {
    let suite = temporaryDefaultsName("hotkey")
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { removeTemporaryDefaults(suite) }

    // умолчания docs/spec.md: ⌥ и ⌥⇧ — нажать и отпустить, транслит не назначен
    #expect(defaults.hotkey(.fix) == Hotkey(code: nil, flags: Hotkey.option))
    #expect(defaults.hotkey(.nextLayout)?.label(key: "") == "⌥⇧")
    #expect(defaults.hotkey(.transliterate) == nil)

    // снятый хоткей не возвращается к умолчанию
    defaults.setHotkey(nil, for: .fix)
    #expect(defaults.hotkey(.fix) == nil)

    let tap = Hotkey(code: nil, flags: Hotkey.control | Hotkey.option)
    defaults.setHotkey(tap, for: .changeCase)
    #expect(defaults.hotkey(.changeCase) == tap)

    // хоткей транслита из 0.4.0 — с подписью — читается
    defaults.set(["code": 17, "flags": Int(Hotkey.control), "label": "⌃Е"], forKey: "transliterateHotkey")
    #expect(defaults.hotkey(.transliterate) == Hotkey(code: 17, flags: Hotkey.control))
}

@Test func hotkeyRecording() {
    var recorder = HotkeyRecorder()
    // ⌥⇧ нажать и отпустить — в любом порядке
    #expect(recorder.modifiers(Hotkey.option) == .wait)
    #expect(recorder.modifiers(Hotkey.option | Hotkey.shift) == .wait)
    #expect(recorder.modifiers(Hotkey.shift) == .wait)
    #expect(recorder.modifiers(0) == .done(Hotkey(code: nil, flags: Hotkey.option | Hotkey.shift)))
    // ⇧ сам по себе и буква без ⌘⌃⌥ — не хоткей
    #expect(recorder.modifiers(Hotkey.shift) == .wait)
    #expect(recorder.modifiers(0) == .wait)
    #expect(recorder.key(0, flags: Hotkey.shift) == .wait)
    #expect(recorder.key(37, flags: Hotkey.command) == .done(Hotkey(code: 37, flags: Hotkey.command)))
    #expect(recorder.key(53, flags: 0) == .cancel)
    #expect(recorder.key(53, flags: Hotkey.control) == .done(Hotkey(code: 53, flags: Hotkey.control)))
}

@Test func puntoHotkeys() {
    // значения из настроек Punto владельца (ru.yandex.punto, 2026-10-21)
    let changeLayout: [String: Any] = ["charKeycode": 666, "isAltUsed": 1, "isCommandUsed": 0, "isControlUsed": 0, "isShiftUsed": 0]
    let changeCase: [String: Any] = ["charKeycode": 37, "isAltUsed": 0, "isCommandUsed": 1, "isControlUsed": 0, "isShiftUsed": 0]
    let none: [String: Any] = ["charKeycode": 666, "isAltUsed": 0, "isCommandUsed": 0, "isControlUsed": 0, "isShiftUsed": 0]
    #expect(Hotkey(punto: changeLayout) == Hotkey(code: nil, flags: Hotkey.option))  // одиночный ⌥
    #expect(Hotkey(punto: changeCase) == Hotkey(code: 37, flags: Hotkey.command))   // ⌘L
    #expect(Hotkey(punto: none) == nil)
    #expect(HotkeyAction.fix.puntoKey == "shortcutChangeLayout")
    // новым пользователям регистр без сочетания (docs/spec.md)
    #expect(HotkeyAction.changeCase.defaultHotkey == nil)
    // автопереключение вкл/выкл — по умолчанию не назначено (просьба владельца 2026-10-21), у Punto оно есть
    #expect(HotkeyAction.toggleAutoCorrect.defaultHotkey == nil)
    #expect(HotkeyAction.toggleAutoCorrect.puntoKey == "shortcutSwitchAutocorrection")
}
