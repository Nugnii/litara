import Carbon
import Testing
@testable import LitaraCore

@MainActor
private func layout(_ name: String) -> KeyboardLayout? {
    KeyboardLayout.available().first { $0.id == "com.apple.keylayout.\(name)" }
}

@Test @MainActor func everyLanguageHasASystemLayout() {
    #expect(Set(KeyboardLayout.available().map(\.language)) == Set(Language.allCases))
}

// Клавиши S (код 1) и B (код 11) дают разные буквы в кириллических раскладках —
// ровно поэтому таблицы берутся из системы, а не зашиваются.
@Test(arguments: [
    ("RussianWin", "ы", "и"),
    ("Russian", "ы", "и"),
    ("Byelorussian", "ы", "і"),
    ("Ukrainian", "и", "і"),
    ("Ukrainian-PC", "і", "и"),
])
@MainActor
func cyrillicLayoutsDifferOnKeysSAndB(name: String, keyS: String, keyB: String) throws {
    let l = try #require(layout(name))
    #expect(l.chars[Keystroke(code: 1)] == keyS)
    #expect(l.chars[Keystroke(code: 11)] == keyB)
}

@Test @MainActor func byelorussianYoIsOnBackslashKey() throws {
    #expect(try #require(layout("Byelorussian")).chars[Keystroke(code: 42)] == "ё")
}

@Test @MainActor func equalKeysAreChosenExplicitly() throws {
    // B25, R12: из равных нажатий одного знака выбор шёл порядком словаря — свой в каждом запуске: выделенное «всё» через
    // ⌥ становилось то «вс’», то «вс“». «ё» в «Русской – ПК» — на 10 и 50; владелец 2026-11-06: «ё» набирает клавишей
    // слева от «1» — это 10. «+» в «Белорусской» — на 10⇧ и 24⇧: берётся обычная клавиша, 24⇧
    let ru = try #require(layout("RussianWin")), be = try #require(layout("Byelorussian"))
    // ISO (по умолчанию, слева от «1» — 10): «ё» только на 10, на 50 — «]» (B44); на ANSI — на обеих
    #expect(ru.chars[Keystroke(code: 10)] == "ё" && ru.chars[Keystroke(code: 50)] == "]")
    #expect(ru.keystrokes(for: "ё") == [Keystroke(code: 10)])
    #expect(be.keystrokes(for: "+") == [Keystroke(code: 24, shift: true)])
    #expect(be.converting("всё", from: ru) == "вс’")
    #expect(ru.converting("1+1", from: be) == "1+1")
    // американская (ANSI) клавиатура: слева от «1» — 50, «ё» там же; встроенная и внешняя бывают разными (владелец)
    KeyboardLayout.keyboardType = KeyboardLayout.firstType(kKeyboardANSI)
    defer { KeyboardLayout.keyboardType = KeyboardLayout.firstType(kKeyboardISO) }
    #expect(ru.chars[Keystroke(code: 10)] == "ё" && ru.chars[Keystroke(code: 50)] == "ё")
    #expect(ru.keystrokes(for: "ё") == [Keystroke(code: 50)])
    #expect(be.converting("всё", from: ru) == "вс“")
    #expect(be.keystrokes(for: "+") == [Keystroke(code: 24, shift: true)])
    // тип клавиатуры macOS: ISO — 10, остальные — 50 (значения типов — с этой системы)
    let types = (1...255).map { Int64($0) }
    let iso = try #require(types.first { KBGetLayoutType(Int16($0)) == kKeyboardISO })
    let ansi = try #require(types.first { KBGetLayoutType(Int16($0)) == kKeyboardANSI })
    #expect(KeyboardLayout.leftOfOne(forKeyboardType: iso) == 10)
    #expect(KeyboardLayout.leftOfOne(forKeyboardType: ansi) == 50)
}

@Test @MainActor func keyTablesFollowTheTypingKeyboard() throws {
    // B44, R18: таблица строилась под клавиатуру, которой печатали последней (`LMGetKbdType`), — после набора на ISO тест
    // выше падал. Теперь `chars` — таблица типа клавиатуры нажатия (`keyboardType`)
    let ansi = KeyboardLayout.firstType(kKeyboardANSI), iso = KeyboardLayout.firstType(kKeyboardISO)
    defer { KeyboardLayout.keyboardType = iso }
    let ru = try #require(layout("RussianWin")), be = try #require(layout("Byelorussian"))
    // знаки ПК в белорусской: на ISO клавиша 50 «Русской – ПК» — знак «]», он и ставится; на ANSI там буква «ё» — у
    // белорусской остаётся своё «“»
    let pc = be.withPunctuation(of: ru)
    KeyboardLayout.keyboardType = ansi
    #expect(ru.chars[Keystroke(code: 50)] == "ё" && pc.chars[Keystroke(code: 50)] == "“")
    KeyboardLayout.keyboardType = iso
    #expect(ru.chars[Keystroke(code: 50)] == "]" && pc.chars[Keystroke(code: 50)] == "]")
}

@Test @MainActor func jisKeyboardUsesItsTable() throws {
    // B45 (скептик B44): JIS попадал в таблицу ANSI, а у JIS свои знаки и мёртвые клавиши — и разные у разных типов JIS.
    // Таблица Litara под каждый тип сверяется с ответом системы (`UCKeyTranslate`) по тем же нажатиям
    let types = [KeyboardLayout.firstType(kKeyboardANSI), KeyboardLayout.firstType(kKeyboardISO)]
        + (1...255).filter { KBGetLayoutType(Int16($0)) == kKeyboardJIS }.map(UInt32.init)
    defer { KeyboardLayout.keyboardType = KeyboardLayout.firstType(kKeyboardISO) }
    var wrong: [String] = []
    for name in ["ABC", "USInternational-PC", "RussianWin", "Byelorussian", "PolishPro"] {
        let l = try #require(layout(name))
        let source = try #require((TISCreateInputSourceList([kTISPropertyInputSourceID: l.id] as CFDictionary, true)?
            .takeRetainedValue() as? [TISInputSource])?.first)
        let data = Unmanaged<CFData>.fromOpaque(try #require(TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)))
            .takeUnretainedValue() as Data
        for type in types {
            KeyboardLayout.keyboardType = type
            for code in UInt16(0)...50 { for shift in [false, true] { for option in [false, true] {
                let key = Keystroke(code: code, shift: shift, option: option)
                let (text, dead) = data.withUnsafeBytes { raw -> (String, Bool) in
                    var state: UInt32 = 0, length = 0, buffer = [UniChar](repeating: 0, count: 4)
                    let modifiers = UInt32(shift ? shiftKey >> 8 : 0) | UInt32(option ? optionKey >> 8 : 0)
                    _ = UCKeyTranslate(raw.bindMemory(to: UCKeyboardLayout.self).baseAddress!, code, UInt16(kUCKeyActionDown),
                                       modifiers, type, 0, &state, buffer.count, &length, &buffer)
                    return (String(utf16CodeUnits: buffer, count: length), length == 0 && state != 0)
                }
                if l.chars[key] != (text.isEmpty ? nil : text) || (l.deadKeys[key] != nil) != dead {
                    wrong.append("\(name) тип \(type) клавиша \(code)\(shift ? "⇧" : "")\(option ? "⌥" : "")")
                }
            } } }
        }
    }
    #expect(wrong.isEmpty, "\(wrong.count): \(wrong.prefix(5))")
    // и выбор действительно различает: у ABC на JIS клавиша 24 иная, чем на ANSI (замер скептика)
    let abc = try #require(layout("ABC"))
    KeyboardLayout.keyboardType = types[0]
    let onANSI = abc.chars[Keystroke(code: 24)]
    KeyboardLayout.keyboardType = types[2]
    #expect(abc.chars[Keystroke(code: 24)] != onANSI)
}

@Test @MainActor func usInternationalPCApostropheIsDeadKey() throws {
    #expect(try #require(layout("USInternational-PC")).chars[Keystroke(code: 39)] == nil)
}

// Ожидаемые слова посчитаны по таблицам раскладок с этого Mac (дамп 2026-10-20).
@Test(arguments: [
    ("ABC", "RussianWin", "ghbdtn", "привет"),
    ("ABC", "RussianWin", "Ghbdtn", "Привет"),
    ("ABC", "Byelorussian", "ghbdtn", "прівет"),
    ("ABC", "Ukrainian-PC", "ghbdsn", "привіт"),
    ("ABC", "Ukrainian", "ghsdbn", "привіт"),
    ("USInternational-PC", "RussianWin", "ghbdtn", "привет"),
    ("RussianWin", "ABC", "руддщ", "hello"),
    ("Byelorussian", "RussianWin", "і", "и"),
    ("RussianWin", "Byelorussian", "щи", "ўі"),
])
@MainActor
func convertsTextBetweenLayouts(from: String, to: String, typed: String, expected: String) throws {
    let source = try #require(layout(from)), target = try #require(layout(to))
    #expect(target.converting(typed, from: source) == expected)
}

@Test @MainActor func textWithUntypableCharacterIsNotConverted() throws {
    let usIntl = try #require(layout("USInternational-PC")), ru = try #require(layout("RussianWin"))
    #expect(ru.converting("🙂", from: usIntl) == nil)
    // апостроф в «США международная – ПК» — мёртвая клавиша: «'t» набирается ею и «t»
    #expect(ru.converting("don't", from: usIntl) == "вщтэе")
}

@Test @MainActor func layoutHasSystemName() throws {
    // вариант раскладки выбирается в настройках по названию macOS, а не по id
    let ru = try #require(KeyboardLayout.available().first { $0.id == "com.apple.keylayout.RussianWin" })
    #expect(!ru.name.isEmpty && ru.name != ru.id)
}

@Test @MainActor func deadKeysCompose() throws {
    // проба владельца 2026-10-21: «Это» в «США международной – ПК» выходит «"nj» — кавычка там мёртвая клавиша
    let intl = try #require(KeyboardLayout.available().first { $0.id == "com.apple.keylayout.USInternational-PC" })
    let quote = Keystroke(code: 39, shift: true), n = Keystroke(code: 45), j = Keystroke(code: 38)
    #expect(intl.chars[quote] == nil)
    #expect(intl.text(for: [quote, n, j]) == "\"nj")
    #expect(intl.text(for: [quote, Keystroke(code: 0)]) == "ä")
    #expect(intl.keystrokes(for: "\"nj") == [quote, n, j])
}
