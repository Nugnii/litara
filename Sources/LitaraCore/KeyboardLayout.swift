import Carbon

/// Раскладка macOS: какой символ даёт каждая клавиша без модификаторов.
///
/// Таблица читается из самой системы (UCKeyTranslate), а не зашивается в код: у одного языка
/// бывает несколько раскладок, и они расходятся. Например, «Украинская» и «Украинская – ПК»
/// меняют местами «и» и «і», а «Русская» и «Русская – ПК» по-разному ставят «ё».
public struct KeyboardLayout: Sendable {
    /// Идентификатор источника ввода, например `com.apple.keylayout.RussianWin`.
    public let id: String
    public let language: Language
    /// Название раскладки в macOS, на языке системы («Русская – ПК»).
    public let name: String
    /// Нажатие (с Shift и Option) → символ. Мёртвые клавиши (апостроф в «США международная – ПК») — в `deadKeys`.
    public let chars: [Keystroke: String]
    /// Мёртвая клавиша → следующее нажатие → что выйдет на экран («"» и «n» — «"n», «"» и «a» — «ä»).
    public let deadKeys: [Keystroke: [Keystroke: String]]
    /// Что выходит мёртвой клавишей с соседом → эти два нажатия (самые простые) — для обратного перевода.
    private let deadSequences: [String: [Keystroke]]

    init(id: String, language: Language, name: String, chars: [Keystroke: String], deadKeys: [Keystroke: [Keystroke: String]] = [:]) {
        self.id = id
        self.language = language
        self.name = name
        self.chars = chars
        self.deadKeys = deadKeys
        var sequences: [String: [Keystroke]] = [:]
        for (dead, next) in deadKeys {
            for (key, text) in next where !key.onKeypad
                && sequences[text].map({ $0[0].effort + $0[1].effort > dead.effort + key.effort }) ?? true {
                sequences[text] = [dead, key]
            }
        }
        deadSequences = sequences
    }

    /// Все раскладки системы для языков из `Language`, включая не добавленные пользователем.
    /// Только с главного потока: параллельные вызовы Text Input Sources роняют процесс (SIGABRT).
    @MainActor
    public static func available() -> [KeyboardLayout] {
        let filter = [kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String] as CFDictionary
        guard let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return sources.compactMap { source in
            guard let id: String = property(source, kTISPropertyInputSourceID),
                  let languages: [String] = property(source, kTISPropertyInputSourceLanguages),
                  let language = languages.first.flatMap(Language.init(rawValue:)),
                  let data: CFData = property(source, kTISPropertyUnicodeKeyLayoutData)
            else { return nil }
            let name: String = property(source, kTISPropertyLocalizedName) ?? id
            let map = keyMap(data as Data)
            return KeyboardLayout(id: id, language: language, name: name, chars: map.chars, deadKeys: map.dead)
        }
    }

    private static func property<T>(_ source: TISInputSource, _ key: CFString) -> T? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue() as? T
    }

    // ponytail: коды 0...50 — основной блок букв и знаков (ANSI и ISO) — и цифровой блок; F-клавиши не нужны
    private static func keyMap(_ data: Data) -> (chars: [Keystroke: String], dead: [Keystroke: [Keystroke: String]]) {
        data.withUnsafeBytes { raw in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return ([:], [:]) }
            let keys = (Array(UInt16(0)...50) + Keystroke.keypadCodes.sorted()).flatMap { code in
                [false, true].flatMap { option in [false, true].map { Keystroke(code: code, shift: $0, option: option) } }
            }
            /// Что напечатает нажатие из состояния мёртвой клавиши `state`; без текста — `nil`, `state` — новое.
            func translate(_ key: Keystroke, _ state: inout UInt32) -> String? {
                var length = 0
                var buffer = [UniChar](repeating: 0, count: 4)
                let modifiers = UInt32(key.shift ? shiftKey >> 8 : 0) | UInt32(key.option ? optionKey >> 8 : 0)
                let status = UCKeyTranslate(layout, key.code, UInt16(kUCKeyActionDown), modifiers,
                                            UInt32(LMGetKbdType()), 0, &state, buffer.count, &length, &buffer)
                return status == noErr && length > 0 ? String(utf16CodeUnits: buffer, count: length) : nil
            }
            var map: [Keystroke: String] = [:]
            var dead: [Keystroke: [Keystroke: String]] = [:]
            for key in keys {
                var state: UInt32 = 0
                if let text = translate(key, &state) {
                    map[key] = text
                } else if state != 0 {
                    // мёртвая клавиша: что выйдет с каждым следующим нажатием
                    var next: [Keystroke: String] = [:]
                    for second in keys {
                        var after = state
                        if let text = translate(second, &after) { next[second] = text }
                    }
                    dead[key] = next
                }
            }
            return (map, dead)
        }
    }

    /// Что напечатают эти нажатия в этой раскладке. Мёртвая клавиша печатается вместе со следующим нажатием;
    /// последняя мёртвая ещё ничего не напечатала. Нажатие без символа пропускается.
    public func text(for keystrokes: [Keystroke]) -> String {
        var result = ""
        var i = keystrokes.startIndex
        while i < keystrokes.endIndex {
            if let next = deadKeys[keystrokes[i]] {
                if i + 1 < keystrokes.endIndex { result += next[keystrokes[i + 1]] ?? "" }
                i += 2
            } else {
                result += chars[keystrokes[i]] ?? ""
                i += 1
            }
        }
        return result
    }

    /// Каждое нажатие что-то печатает: мёртвая клавиша — только вместе со следующим.
    public func renders(_ keystrokes: [Keystroke]) -> Bool {
        var i = keystrokes.startIndex
        while i < keystrokes.endIndex {
            if let next = deadKeys[keystrokes[i]] {
                guard i + 1 < keystrokes.endIndex, next[keystrokes[i + 1]] != nil else { return false }
                i += 2
            } else {
                guard chars[keystrokes[i]] != nil else { return false }
                i += 1
            }
        }
        return true
    }

    /// Код клавиши слева от «1» на клавиатуре, которой сейчас набирают: ISO — 10 (§), ANSI — 50 (`). «ё» в «Русской – ПК»
    /// стоит на обеих, и при переводе текста берётся эта (владелец 2026-11-06: «ё» набирает клавишей слева от «1»;
    /// внешняя и встроенная клавиатуры бывают разного типа — перехват ставит тип по каждому нажатию, B25).
    /// ponytail: общий на процесс — пишет перехват, читает сеанс набора, оба на главном потоке
    nonisolated(unsafe) public static var leftOfOneKey: UInt16 = 10

    /// Клавиша слева от «1» по типу клавиатуры нажатия (`CGEventField.keyboardEventKeyboardType`).
    public static func leftOfOne(forKeyboardType type: Int64) -> UInt16 {
        KBGetLayoutType(Int16(truncatingIfNeeded: type)) == kKeyboardISO ? 10 : 50
    }

    /// Какими нажатиями этот текст набирается в этой раскладке; `nil`, если какой-то символ здесь не набрать.
    public func keystrokes(for text: String) -> [Keystroke]? {
        // один символ бывает на нескольких нажатиях — берём самое простое: без модификаторов, Shift, Option.
        // Цифровой блок только читается: каждый его знак есть и на основном, а свои замены и выученные слова
        // набираются основным — иначе «+» нашёлся бы на цифровом (без Shift) и замена с ним не сработала бы
        // из равных — явно, а не порядком словаря, он в Swift свой в каждом запуске (R12)
        let left = Self.leftOfOneKey
        let reverse = Dictionary(chars.filter { !$0.key.onKeypad }.map { ($1, $0) },
                                 uniquingKeysWith: { a, b in a.rank(leftOfOne: left) <= b.rank(leftOfOne: left) ? a : b })
        // знак, который здесь набирается только мёртвой клавишей, — с соседом: «"n» — «"» и «n»
        let text = Array(text)
        var result: [Keystroke] = []
        var i = 0
        while i < text.count {
            if i + 1 < text.count, reverse[String(text[i])] == nil, let pair = deadSequences[String(text[i...i + 1])] {
                result += pair
                i += 2
            } else if let key = reverse[String(text[i])] {
                result.append(key)
                i += 1
            } else if let pair = deadSequences[String(text[i])] {
                result += pair
                i += 1
            } else {
                return nil
            }
        }
        return result
    }

    /// Буквы соседних клавиш (ряды ANSI, тот же Shift): промах пальцем — опечатка в соседнюю (B21). Ряд выше сдвинут
    /// влево: над A — Q и W, под A — Z.
    public func neighbors(of char: Character) -> Set<Character> {
        let rows: [[UInt16]] = [[12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30],
                                [0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39],
                                [6, 7, 8, 9, 11, 45, 46, 43, 47, 44]]
        guard let key = keystrokes(for: String(char))?.first, !key.option,
              let r = rows.firstIndex(where: { $0.contains(key.code) }), let i = rows[r].firstIndex(of: key.code) else { return [] }
        var near = [(r, i - 1), (r, i + 1)]
        if r > 0 { near += [(r - 1, i), (r - 1, i + 1)] }
        if r < 2 { near += [(r + 1, i - 1), (r + 1, i)] }
        return Set(near.compactMap { row, index in
            rows[row].indices.contains(index) ? chars[Keystroke(code: rows[row][index], shift: key.shift)]?.first : nil
        })
    }

    /// Эта раскладка со знаками `other` там, где обе дают не букву: белорусская «как в Русской – ПК»
    /// (docs/spec.md). У Apple в белорусской «?», «,» и «.» не на тех клавишах; Litara печатает знаки ПК, и
    /// сеанс должен знать именно их — иначе ⌥ переводил «.» в белорусскую «/» (проба владельца 2026-10-21).
    public func withPunctuation(of other: KeyboardLayout) -> KeyboardLayout {
        var chars = self.chars
        for (key, text) in self.chars where !key.option && !key.onKeypad {
            guard let otherText = other.chars[key], otherText != text,
                  !text.contains(where: \.isLetter), !otherText.contains(where: \.isLetter) else { continue }
            chars[key] = otherText
        }
        return KeyboardLayout(id: id, language: language, name: name, chars: chars, deadKeys: deadKeys)
    }

    /// Текст, набранный в раскладке `source`, — каким он вышел бы в этой раскладке.
    public func converting(_ text: String, from source: KeyboardLayout) -> String? {
        source.keystrokes(for: text).map(self.text(for:))
    }
}

/// Нажатие клавиши: код клавиши macOS и зажаты ли Shift и Option. Option нужен польской
/// диакритике: ą, ż, ó в «Польской Pro» набираются с ним.
public struct Keystroke: Hashable, Sendable {
    public let code: UInt16
    public let shift: Bool
    public let option: Bool

    public init(code: UInt16, shift: Bool = false, option: Bool = false) {
        self.code = code
        self.shift = shift
        self.option = option
    }

    var effort: Int { (option ? 2 : 0) + (shift ? 1 : 0) }

    /// Порядок выбора из нажатий одного знака (R12, B25): проще (без модификаторов, Shift, Option); клавиши 10 и 50 — после
    /// обычных («+» в «Белорусской» — 24⇧, а не 10⇧: в русской 10⇧ — «Ё»), из них — слева от «1»; дальше — меньший код.
    func rank(leftOfOne: UInt16) -> (Int, Int, UInt16) {
        (effort, code == leftOfOne ? 1 : (code == 10 || code == 50) ? 2 : 0, code)
    }

    /// Цифровой блок: «.», «*», «+», «/», «-», «=», цифры (Clear и Enter — не знаки). «/» на нём — в любой
    /// раскладке, им ставят «/save» в русской: без него слово с таким знаком не исправлялось вовсе (B15)
    static let keypadCodes: Set<UInt16> = [65, 67, 69, 75, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92]
    var onKeypad: Bool { Self.keypadCodes.contains(code) }
}
