import Foundation
import Testing
@testable import LitaraCore

// Второй круг атак на be95bef (B51 условный уход, B52 аббревиатуры). Харнес — копия round-1 (`zzType`/`zzScreen`).

@MainActor
private func r2Type(_ input: String, _ s: inout TypingSession, _ screen: inout String, _ log: inout [String],
                    keyboard: Language = .ru, layouts: [Language: KeyboardLayout]) throws {
    func apply(_ actions: [TypingSession.Action]) {
        for case let .replace(n, text) in actions {
            precondition(n <= screen.count, "стирает \(n) из «\(screen)»")
            screen = String(screen.dropLast(n)) + text
        }
    }
    for ch in input {
        switch ch {
        case " ", "\n", "\t":
            apply(s.separator(String(ch))); screen.append(ch)
            if let d = s.lastDecision { log.append(d) }
        case "⌫":
            s.backspace(); if !screen.isEmpty { screen.removeLast() }
        case "⌥":
            apply(s.cycleWord()); log.append(s.lastDecision ?? "⌥ —")
        case "⟲":
            s.reset()
        default:
            let key = try #require(layouts[keyboard]?.keystrokes(for: String(ch))?.first, "\(ch) в \(keyboard)")
            let before = s.current
            let actions = s.key(key)
            if actions.isEmpty { screen += layouts[before]?.chars[key] ?? "" } else { apply(actions); log.append(s.lastDecision ?? "") }
        }
    }
}

@MainActor
private func r2Screen(_ input: String, from start: Language = .ru, ids: [Language: String] = ownerLayoutIDs,
                      configure: (inout TypingSession) -> Void = { _ in })
    throws -> (text: String, language: Language, log: [String]) {
    let (detector, layouts) = try makeDetector(ids, pcPunctuation: true)
    var s = TypingSession(detector: detector, layouts: layouts, current: start)
    configure(&s)
    var screen = "", log: [String] = []
    try r2Type(input, &s, &screen, &log, layouts: layouts)
    return (screen, s.current, log)
}

private func show(_ s: String) -> String { s.replacingOccurrences(of: "\t", with: "⇥").replacingOccurrences(of: "\n", with: "⏎") }


// MARK: - Находки (каждая проверка падает на be95bef)

/// Словарные факты находок — из настоящих словарей.
@Test @MainActor func r2FactsTheFindingsRelyOn() throws {
    let (d, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    let ru = try #require(layouts[.ru]), be = try #require(layouts[.be]), en = try #require(layouts[.en])
    let umova = try #require(ru.keystrokes(for: "умова")), umovami = try #require(ru.keystrokes(for: "умовами"))
    #expect(!d.isWord("умова", in: .ru) && d.isWord("умова", in: .be))
    #expect(!d.clearlyForeign(umova, typedIn: .ru, to: .be, whole: true))                // уход по «умова» — условный
    #expect(be.text(for: umovami) == "умовамі" && d.isWordOnly(umovami, in: .be, not: .ru)) // «умовамі» — только be
    #expect(umovami.starts(with: umova))
    let dns = try #require(en.keystrokes(for: "DNS"))
    #expect(ru.text(for: dns) == "ВТЫ" && !d.isWord("ВТЫ", in: .ru))                     // «ВТЫ» — не слово
    let tls = try #require(en.keystrokes(for: "TLS"))
    #expect(ru.text(for: tls) == "ЕДЫ" && d.isWord("ЕДЫ", in: .ru))
    #expect(d.isWord("так", in: .ru) && d.isWord("и", in: .ru) && d.isWord("і", in: .be))
}

/// M, регрессия be95bef. Галочка «не переключать аббревиатуры»: после условного ухода и английского слова (раскладка en)
/// английская аббревиатура «DNS» уходит на лету в «ВТЫ», «TLS» — в «ЕДЫ»: исключение «аббревиатура отменяет уход» не
/// проверяет, что буквы испорчены уходом (набрано в раскладке `to`), а латиница уход теперь не снимает. Без условного
/// ухода те же нажатия дают «home DNS». На cd752a4 — «home DNS» (уход снимала латиница).
@Test @MainActor func r2AbbreviationInLatinCancelsPendingSwitch() throws {
    let control = try r2Screen("рщьу ВТЫ ") { $0.skipAbbreviations = true }
    #expect(control.text == "home DNS ")
    let dns = try r2Screen("употреблением беларуских рщьу ВТЫ ") { $0.skipAbbreviations = true }
    #expect(dns.text.hasSuffix(" home DNS "), "\(dns.text) \(dns.log)")
    let tls = try r2Screen("употреблением беларуских рщьу ЕДЫ ") { $0.skipAbbreviations = true }
    #expect(tls.text.hasSuffix(" home TLS "), "\(tls.text) \(tls.log)")
}

/// M, неполная починка M3/M4 (было и на cd752a4). Отменяющее слово внутри скобок, но не первое в них: открывающая
/// поставила `tentative.start = 0` внутреннего предложения — отмена переписывает только скобку, снимает уход, а
/// закрывающая возвращает раскладку до скобки — белорусскую, раскладку отменённого ухода. «беларускіх» остаётся,
/// русский набор после «)» идёт в be.
@Test @MainActor func r2CancelInsideBracketNotFirstWord() throws {
    // Предел, принятый после второго круга (B55): скобка — отдельное предложение, отмена после неё возвращает только
    // раскладку. Возврат текста перед скобкой портил «(п. 3)» — текст цел, слово ухода остаётся с «і».
    // Починено: после «)» раскладка — та, откуда уходили, а не условная.
    let r = try r2Screen("употреблением беларуских (да слов) ")
    #expect(r.text == "употреблением беларускіх (да слов) ", "\(r.text) \(r.log)")
    #expect(r.language == .ru, "\(r.language)")
    let nested = try r2Screen("употреблением беларуских (да (да) слов) ")
    #expect(nested.text == "употреблением беларускіх (да (да) слов) " && nested.language == .ru, "\(nested.text)")
    let open = try r2Screen("употреблением беларуских (да слов ")
    #expect(open.text == "употреблением беларускіх (да слов " && open.language == .ru, "\(open.text)")
}

/// L, регрессия be95bef. Отмена условного ухода словом, набранным в латинице, переводит только слова раскладки `to`:
/// однобуквенное перед словом («1/» → «1.», spec: «1/ ghbdtn» → «1. привет») остаётся латиницей. Без условного ухода —
/// «home 1. привет»; на cd752a4 — тоже «1.».
@Test @MainActor func r2LatinCancelSkipsSingleLetterBeforeWord() throws {
    let control = try r2Screen("рщьу 1. привет ")
    #expect(control.text == "home 1. привет ")
    let r = try r2Screen("употреблением беларуских рщьу 1. привет ")
    #expect(r.text == "употреблением беларуских home 1. привет ", "\(r.text) \(r.log)")
}

/// L, регрессия be95bef. Проверка «само слово ухода себя не подтверждает» — `starts(with:)`: другое слово только нового
/// языка, которое начинается с тех же клавиш («умовамі» после «умова»), уход не подтверждает, и «слов» переписывает его
/// в «умовами». На cd752a4 — «умова умовамі слов».
@Test @MainActor func r2LongerWordWithTriggerPrefixDoesNotConfirm() throws {
    let r = try r2Screen("умова умовами слов ")
    #expect(r.text == "умова умовамі слов ", "\(r.text) \(r.log)")
}

/// L, было и на cd752a4. Enter не дописывается к разделителю прошлого слова (`separator != "\n"`): после «слово ⏎» ⌥
/// стирает «слово » на экране «слово ⏎» — «беларускіих»; ⌫ по Enter открывает слово, хотя пробел за ним на экране, —
/// следующий перевод предложения стирает на знак меньше: «иі беларускіх».
@Test @MainActor func r2EnterAfterSpaceDesyncs() throws {
    let hotkey = try r2Screen("употреблением беларуских \n⌥")
    #expect(hotkey.text == "употреблением беларуских \n", "\(show(hotkey.text))")
    // стёртый Enter возвращает курсор в прошлое предложение, а сеанс его уже не помнит: оно не переводится, но и не
    // портится («иі беларускіх» до починки)
    let back = try r2Screen("и \n⌫ беларуских ")
    #expect(back.text == "и  беларускіх ", "\(show(back.text))")
}

/// L, было и на cd752a4. Слово, открытое ⌫ и стёртое целиком, — `last == nil`: второй пробел после предыдущего слова
/// не записывается, перевод предложения стирает на знак меньше.
@Test @MainActor func r2SpaceAfterErasedReopenedWordNotTracked() throws {
    let r = try r2Screen("и бы ⌫⌫⌫ беларуских ")
    #expect(r.text == "і  беларускіх ", "\(r.text)")
}

/// L, было и на cd752a4. Отмена не возвращает слова в скобках, набранные во время ухода: «(и так)» осталось «(і так)».
@Test @MainActor func r2CancelLeavesBracketWordsOfTheSwitch() throws {
    // Предел, принятый после второго круга (B55): скобка — отдельное предложение, отмена после неё возвращает только
    // раскладку. Возврат текста перед скобкой портил «(п. 3)» — текст цел, слово ухода остаётся с «і».
    let r = try r2Screen("употреблением беларуских (и так) слов ")
    #expect(r.text == "употреблением беларускіх (і так) слов " && r.language == .ru, "\(r.text) \(r.log)")
    let abbr = try r2Screen("употреблением беларуских (ГИБДД) слов ")
    #expect(abbr.text == "употреблением беларускіх (ГІБДД) слов " && abbr.language == .ru, "\(abbr.text) \(abbr.log)")
}

/// H, регрессия be95bef. Конец предложения внутри скобок («п. 3», «т. 2», «т. е.», Enter) очищает `sentence`, но не
/// `outer`; закрывающая собирает предложение из внешнего и слов скобки после точки — слов до точки в модели нет. be95bef
/// после закрывающей возвращает отмене `start` во внешнем предложении (тот же уход), и отмена стирает по неполной модели:
/// «(п. 3)» → «(их 3)», «(т. е. 5)» → «(т. их 5)», Enter стёрт. На cd752a4 — «беларускіх (п. 3) слов» (отмена терялась,
/// текст целый).
@Test @MainActor func r2SentenceEndInsideBracketCorruptsCancel() throws {
    // Предел, принятый после второго круга (B55): скобка — отдельное предложение, отмена после неё возвращает только
    // раскладку. Возврат текста перед скобкой портил «(п. 3)» — текст цел, слово ухода остаётся с «і».
    for (input, ok) in [("употреблением беларуских (п. 3) слов ", "употреблением беларускіх (п. 3) слов "),
                        ("употреблением беларуских (т. е. 5) слов ", "употреблением беларускіх (т. е. 5) слов "),
                        ("употреблением беларуских (да\nда) слов ", "употреблением беларускіх (да\nда) слов ")] {
        let r = try r2Screen(input)
        #expect(r.text == ok && r.language == .ru, "\(show(r.text)) \(r.log)")
    }
}

/// M, было и на cd752a4 (тот же корень, старый путь — перевод предложения с начала): «и (п. 3) выдатна» → «и (смі…»-порча.
@Test @MainActor func r2SentenceEndInsideBracketCorruptsSentenceSwitchPreexisting() throws {
    let r = try r2Screen("и (см. ниже) выдатна ")
    #expect(["і (см. ниже) выдатна ", "и (см. ниже) выдатна "].contains(r.text), "\(r.text)")
    let enter = try r2Screen("и (\n) пры ")
    #expect(["і (\n) пры ", "и (\n) пры "].contains(enter.text), "\(show(enter.text))")
}

/// L/M, было и на cd752a4, вне B51/B52. ⌫ после своей замены открывает слово набранными нажатиями, а на экране —
/// замена: пробел снова срабатывает заменой и стирает длину набранного из замены — «МосМосква». С двойным пробелом
/// (be95bef: ⌫ снимает по одному разделителю) путь «мск  ⌫⌫ » теперь тоже ведёт сюда; на cd752a4 он давал «Москва ».
@Test @MainActor func r2BackspaceAfterReplacementRetypesIt() throws {
    let r = try r2Screen("мск ⌫ ") { $0.replacements = [Replacement(what: "мск", with: "Москва")] }
    #expect(r.text == "Москва ", "\(r.text)")
    let double = try r2Screen("мск  ⌫⌫ ") { $0.replacements = [Replacement(what: "мск", with: "Москва")] }
    #expect(double.text == "Москва ", "\(double.text)")
}

// MARK: - Фаззеры

private struct R2Rng {
    var seed: UInt64
    mutating func next(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(n)) }
}

/// Прогон событий: экран, стирания больше экрана, и «сырой» буфер нажатий/разделителей (⌫ стирает последний элемент).
@MainActor
private func r2Run(_ events: String, _ s: inout TypingSession, layouts: [Language: KeyboardLayout])
    -> (screen: String, over: Bool, raw: [[Keystroke]]) {
    var screen = "", over = false
    var buffer: [Keystroke?] = []    // nil — разделитель
    func apply(_ actions: [TypingSession.Action]) {
        for case let .replace(n, text) in actions {
            if n > screen.count { over = true; screen = "" } else { screen = String(screen.dropLast(n)) }
            screen += text
        }
    }
    for ch in events {
        switch ch {
        case " ", "\n", "\t": apply(s.separator(String(ch))); screen.append(ch); buffer.append(nil)
        case "⌫": s.backspace(); if !screen.isEmpty { screen.removeLast() }; if !buffer.isEmpty { buffer.removeLast() }
        case "⌥": apply(s.cycleWord())
        case "⟲": s.reset()
        default:
            guard let key = layouts[.ru]?.keystrokes(for: String(ch))?.first else { continue }
            let before = s.current
            let actions = s.key(key)
            if actions.isEmpty { screen += layouts[before]?.chars[key] ?? "" } else { apply(actions) }
            buffer.append(key)
        }
    }
    var words: [[Keystroke]] = [], cur: [Keystroke] = []
    for item in buffer { if let k = item { cur.append(k) } else if !cur.isEmpty { words.append(cur); cur = [] } }
    if !cur.isEmpty { words.append(cur) }
    return (screen, over, words)
}

private let r2Words = ["слов", "привет", "широко", "употреблением", "и", "в", "дела", "кто", "то", "сейчас", "беларуских",
                       "запасик", "умова", "умовами", "файлик", "прывитанне", "зразумещ", "нацисни", "литару", "выдатна", "з",
                       "руддщ", "рщьу", "ФЗШ", "ВТЫ", "ЕДЫ", "ГИБДД", "ИНН", "ТЗ", "да", "тест", "щи", "1", "ЬЫЛ"]

/// Каждое экранное слово — нажатия этого слова, каждое в какой-то раскладке; стирания больше экрана нет.
/// `clean` — без двух найденных семейств (конец предложения внутри скобок; пробел после слова, открытого ⌫ и стёртого
/// целиком), чтобы видеть, остаётся ли что-то ещё.
@MainActor
private func r2PerCharFuzz(threeCyrillics: Bool, abbreviations: Bool, clean: Bool, seed: UInt64) throws -> [String] {
    let (detector, layouts) = try makeDetector(threeCyrillics ? defaultLayoutIDs : ownerLayoutIDs, pcPunctuation: true)
    var rng = R2Rng(seed: seed &+ (threeCyrillics ? 7 : 0) &+ (abbreviations ? 13 : 0))
    let tails = clean
        ? [" ", "  ", " \t", "\t", "   ", " ⌫ ", "  ⌫⌫ ", "⌫ ", " ⌥", "⌥ ", "  ⌥", "⟲ ", "\t⌫ ", " ⌥⌥", "  ⌫ ", " ⌥ ⌫ "]
        : [" ", "  ", " \t", "\t", "\n", " \n", "\n ", "   ", " ⌫ ", "  ⌫⌫ ", "⌫ ", "⌫⌫ ", " ⌥", "⌥ ", "  ⌥",
           "⟲ ", " ⌫⌫⌫ ", "\t⌫ ", " ⌥⌥", "  ⌫ "]
    var bad: [String] = []
    for round in 0..<adversaryFuzzRounds {
        var s = TypingSession(detector: detector, layouts: layouts, current: .ru)
        s.skipAbbreviations = abbreviations
        var events = ""
        for _ in 0..<(3 + rng.next(9)) {
            var w = r2Words[rng.next(r2Words.count)]
            switch rng.next(12) {
            case 0: w = "(" + w
            case 1: w += ")"
            case 2: w = "(" + w + ")"
            case 3: w += clean ? "" : "."
            case 4: w += clean ? "" : ","
            default: break
            }
            events += w + tails[rng.next(tails.count)]
        }
        let r = r2Run(events, &s, layouts: layouts)
        let shown = r.screen.split(whereSeparator: \.isWhitespace).map(Array.init)
        var ok = !r.over && shown.count == r.raw.count
        if ok {
            for (w, keys) in zip(shown, r.raw) {
                if w.count != keys.count { ok = false; break }
                for (c, k) in zip(w, keys) where !layouts.values.contains(where: { $0.chars[k] == String(c) }) { ok = false }
            }
        }
        if !ok { bad.append("[\(round)] «\(show(events))» → «\(show(r.screen))»\(r.over ? " ПЕРЕСТИРАНИЕ" : "")") }
    }
    return bad
}

@Test(arguments: [(false, false), (false, true), (true, false), (true, true)]) @MainActor
func r2FuzzPerCharOracle(threeCyrillics: Bool, abbreviations: Bool) throws {
    let bad = try r2PerCharFuzz(threeCyrillics: threeCyrillics, abbreviations: abbreviations, clean: false, seed: 0xad_0002)
    #expect(bad.isEmpty, "\(bad.count) из \(adversaryFuzzRounds): \(bad.prefix(8).joined(separator: " | "))")
}

@Test(arguments: [(false, false), (false, true), (true, false), (true, true)]) @MainActor
func r2FuzzPerCharOracleClean(threeCyrillics: Bool, abbreviations: Bool) throws {
    let bad = try r2PerCharFuzz(threeCyrillics: threeCyrillics, abbreviations: abbreviations, clean: true, seed: 0xc1ea_0310)
    #expect(bad.isEmpty, "\(bad.count) из \(adversaryFuzzRounds): \(bad.prefix(8).joined(separator: " | "))")
}

/// Разность: те же события с одним разделителем и с двойными/смешанными — слова на экране и раскладка совпадают.
@MainActor
private func r2DifferentialFuzz(threeCyrillics: Bool, abbreviations: Bool, clean: Bool, seed: UInt64) throws -> [String] {
    let (detector, layouts) = try makeDetector(threeCyrillics ? defaultLayoutIDs : ownerLayoutIDs, pcPunctuation: true)
    var rng = R2Rng(seed: seed &+ (threeCyrillics ? 7 : 0) &+ (abbreviations ? 13 : 0))
    var pairs: [(String, String)] = [(" ", "  "), (" ", " \t "), ("\t", "\t "), (" ", "   "), (" ⌥", "  ⌥"), (" ⌫ ", "  ⌫⌫ "),
                                     (" ", "  ⌫"), (" ⌥ ", "  ⌥ ⌫"), (" ", " "), ("⌥ ", "⌥  "), (" ⌥ ", "\t⌥ "), ("⟲ ", "⟲  ")]
    if !clean { pairs.append(("\n", "\n ")) }
    var bad: [String] = []
    for round in 0..<adversaryFuzzRounds {
        var a = "", b = ""
        for _ in 0..<(3 + rng.next(9)) {
            var w = r2Words[rng.next(r2Words.count)]
            switch rng.next(12) {
            case 0: w = "(" + w
            case 1: w += ")"
            case 2: w = "(" + w + ")"
            case 3: w += clean ? "" : "."
            default: break
            }
            let (x, y) = pairs[rng.next(pairs.count)]
            a += w + x; b += w + y
        }
        var s1 = TypingSession(detector: detector, layouts: layouts, current: .ru), s2 = s1
        s1.skipAbbreviations = abbreviations; s2.skipAbbreviations = abbreviations
        let r1 = r2Run(a, &s1, layouts: layouts), r2 = r2Run(b, &s2, layouts: layouts)
        let w1 = r1.screen.split(whereSeparator: \.isWhitespace), w2 = r2.screen.split(whereSeparator: \.isWhitespace)
        if w1 != w2 || r1.over || r2.over || s1.current != s2.current {
            bad.append("[\(round)] «\(show(a))» → «\(show(r1.screen))» [\(s1.current)] vs «\(show(b))» → «\(show(r2.screen))» [\(s2.current)]")
        }
    }
    return bad
}

@Test(arguments: [(false, false), (false, true), (true, false), (true, true)]) @MainActor
func r2FuzzDoubleSeparatorDifferential(threeCyrillics: Bool, abbreviations: Bool) throws {
    let bad = try r2DifferentialFuzz(threeCyrillics: threeCyrillics, abbreviations: abbreviations, clean: false, seed: 0xd1ff_0310)
    #expect(bad.isEmpty, "\(bad.count) из \(adversaryFuzzRounds): \(bad.prefix(6).joined(separator: " | "))")
}

@Test(arguments: [(false, false), (false, true), (true, false), (true, true)]) @MainActor
func r2FuzzDoubleSeparatorDifferentialClean(threeCyrillics: Bool, abbreviations: Bool) throws {
    let bad = try r2DifferentialFuzz(threeCyrillics: threeCyrillics, abbreviations: abbreviations, clean: true, seed: 0xd2ff_0311)
    #expect(bad.isEmpty, "\(bad.count) из \(adversaryFuzzRounds): \(bad.prefix(6).joined(separator: " | "))")
}

/// Русская фраза с одним словом условного ухода («беларуских», можно не раз), словами обоих языков и ни одного,
/// аббревиатурами, двойными разделителями, ⌫ по разделителю — и в конце «слов». Отмена возвращает всё набранное с
/// ухода: экран равен набору русской раскладкой (⌫ — просто стирание).
@Test(arguments: [(false, false), (false, true), (true, false), (true, true)]) @MainActor
func r2FuzzCancelRestoresRussian(threeCyrillics: Bool, abbreviations: Bool) throws {
    try r2CancelFuzz(threeCyrillics: threeCyrillics, abbreviations: abbreviations, brackets: true)
}

/// То же без скобок: отмена возвращает всё.
@Test(arguments: [(false, false), (false, true), (true, false), (true, true)]) @MainActor
func r2FuzzCancelRestoresRussianNoBrackets(threeCyrillics: Bool, abbreviations: Bool) throws {
    try r2CancelFuzz(threeCyrillics: threeCyrillics, abbreviations: abbreviations, brackets: false)
}

@MainActor
private func r2CancelFuzz(threeCyrillics: Bool, abbreviations: Bool, brackets: Bool) throws {
    let (detector, layouts) = try makeDetector(threeCyrillics ? defaultLayoutIDs : ownerLayoutIDs, pcPunctuation: true)
    var rng = R2Rng(seed: 0xca_9ce1 &+ (threeCyrillics ? 7 : 0) &+ (abbreviations ? 13 : 0))
    // «ТЗ» без галочки уходит в «NP» — цена, названная владельцу (spec); «(ГИБДД)» — находка r2CancelLeavesBracketWordsOfTheSwitch
    let words = ["беларуских", "беларуских", "да", "слов", "привет", "широко", "употреблением", "сейчас", "ИНН", "ГИБДД",
                 "тест", "кто", "1", "(да)", "да)", "(да"] + (abbreviations ? ["ТЗ"] : [])
    let seps = [" ", "  ", "\t", " \t", " ⌫ ", "  ⌫ ", "   ", "\t⌫ "]
    var bad: [String] = []
    for round in 0..<adversaryFuzzRounds {
        var events = ""
        for _ in 0..<(2 + rng.next(8)) { events += words[rng.next(words.count)] + seps[rng.next(seps.count)] }
        events += "слов "
        var expected = ""
        for ch in events { if ch == "⌫" { expected.removeLast() } else { expected.append(ch) } }
        var s = TypingSession(detector: detector, layouts: layouts, current: .ru)
        s.skipAbbreviations = abbreviations
        let r = r2Run(events, &s, layouts: layouts)
        // со скобками (предел B55) слово ухода и слова скобки могут остаться с «і» — сверяется всё, кроме и/і:
        // лишний, потерянный или переставленный знак по-прежнему провал
        func loose(_ t: String) -> String { t.replacingOccurrences(of: "і", with: "и").replacingOccurrences(of: "І", with: "И") }
        let same = brackets ? loose(r.screen) == loose(expected) : r.screen == expected
        if brackets == events.contains("("), !same || r.over || s.current != .ru {
            bad.append("[\(round)] «\(show(events))» → «\(show(r.screen))» [\(s.current)]")
        }
    }
    #expect(bad.isEmpty, "\(bad.count) из \(adversaryFuzzRounds): \(bad.prefix(8).joined(separator: " | "))")
}

