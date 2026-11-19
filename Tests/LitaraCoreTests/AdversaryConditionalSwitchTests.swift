import Foundation
import Testing
@testable import LitaraCore

// Атаки на c5f0134 (B51, условный уход между кириллицами) и cd752a4 (B52, аббревиатуры). Ожидание в каждой проверке —
// то, что показал бы верный экран по docs/spec.md; каждая падающая проверка — найденный дефект.

/// Набор клавишами раскладки `keyboard` (пальцы не знают о переключениях). Особые знаки: «⌫» — Backspace,
/// «⌥» — хоткей «исправить», «⟲» — сброс (клик); пробел, «\n», «\t» — разделители. Экран — как в приложении:
/// нажатие без действий печатает свой знак в текущей раскладке, `replace` стирает и печатает.
@MainActor
private func zzType(_ input: String, _ s: inout TypingSession, _ screen: inout String, _ log: inout [String],
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

/// Фраза клавишами русской раскладки владельца (en «США международная – ПК», be со знаками ПК, ru «Русская – ПК»).
@MainActor
private func zzScreen(_ input: String, from start: Language = .ru, ids: [Language: String] = ownerLayoutIDs,
                      configure: (inout TypingSession) -> Void = { _ in })
    throws -> (text: String, language: Language, log: [String]) {
    let (detector, layouts) = try makeDetector(ids, pcPunctuation: true)
    var s = TypingSession(detector: detector, layouts: layouts, current: start)
    configure(&s)
    var screen = "", log: [String] = []
    try zzType(input, &s, &screen, &log, layouts: layouts)
    return (screen, s.current, log)
}

/// Словарные факты, на которых стоят атаки, — из настоящих словарей и раскладок.
@Test @MainActor func zzFactsTheAttacksRelyOn() throws {
    let (d, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    let ru = try #require(layouts[.ru]), be = try #require(layouts[.be])
    let bel = try #require(ru.keystrokes(for: "беларуских")), inn = try #require(ru.keystrokes(for: "ИНН"))
    let gibdd = try #require(ru.keystrokes(for: "ГИБДД"))
    #expect(!d.isWord("беларуских", in: .ru) && d.isWord(be.text(for: bel), in: .be))
    #expect(!d.clearlyForeign(bel, typedIn: .ru, to: .be, whole: true))                  // уход по нему — условный
    #expect(d.isWord("слов", in: .ru) && !d.isWord("слов", in: .be))                     // «слов» тянет обратно
    #expect(d.isWord("да", in: .ru) && d.isWord("да", in: .be))                          // «да» ничего не решает
    #expect(d.isWord("ИНН", in: .ru) && !d.isWord(be.text(for: inn), in: .be))           // «ІНН» — не слово
    #expect(!d.isWord("ГИБДД", in: .ru) && !d.isWord(be.text(for: gibdd), in: .be))
}

// MARK: - B51: порча экрана

/// H. Второй пробел подряд сеанс не записывает (`separator` с пустым словом — `return []`), а отмена условного ухода
/// теперь переписывает текст ПОСЛЕ слова ухода — стирание считается по модели без второго пробела: «беларускіих».
/// До B51 «слов» после «беларускіх» переписывало только себя (start = sentence.count) — этого пути не было: на 298722a
/// те же нажатия дают «употреблением беларускіх  слов » (неверно, но целое), регрессия — порча.
@Test @MainActor func zzDoubleSpaceAfterConditionalWordCorruptsCancel() throws {
    let r = try zzScreen("употреблением беларуских  слов ")
    #expect(r.text == "употреблением беларуских  слов ", "\(r.text) \(r.log)")
    let tab = try zzScreen("употреблением беларуских\t\tслов ")
    #expect(tab.text == "употреблением беларуских\t\tслов ", "\(tab.text) \(tab.log)")
}

/// Контроль: тот же корень — не новый. Перевод начала предложения при уходе (путь до B51, `sentenceStart` = 0) через
/// двойной пробел портит экран так же: «иі беларускіх».
@Test @MainActor func zzDoubleSpaceBeforeSwitchCorruptsScreenPreexisting() throws {
    let r = try zzScreen("и  беларуских ")
    #expect(r.text == "і  беларускіх ", "\(r.text) \(r.log)")
}

/// Случайный набор (детерминированный): каждое экранное слово должно быть набранными нажатиями в какой-то раскладке
/// (опечатки и замены выключены). Без двойных пробелов — 0 нарушений; с ними на HEAD 61 из 3000, на 298722a
/// (до B51) — 14 из тех же 3000: условная отмена вчетверо расширила старую дыру.
@Test(arguments: [false, true]) @MainActor func zzFuzzScreenWords(doubleSpaces: Bool) throws {
    let (detector, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    let ru = try #require(layouts[.ru])
    let words = ["слов", "привет", "широко", "употреблением", "и", "в", "дела", "объект", "всё", "кто", "то", "сейчас",
                 "беларуских", "запасик", "умова", "файлик", "прывитанне", "зразумещ", "нацисни", "литару", "выдатна", "з",
                 "руддщ", "ФЗШ", "ГИБДД", "ИНН", "да", "тест", "щи"]
    var seed: UInt64 = 0x5eed_0310
    func rnd(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(n)) }
    var failures: [String] = []
    for round in 0..<adversaryFuzzRounds {
        var events = "", typedWords: [String] = []
        for _ in 0..<(3 + rnd(5)) {
            var w = words[rnd(words.count)]
            switch rnd(10) {
            case 0: w += ","
            case 1: w = "(" + w + ")"
            case 2: w = "(" + w
            case 3: w += ")"
            default: break
            }
            events += w
            var final = w
            let sepKind = rnd(12)
            if sepKind == 0 { events += " ⌫, "; final += "," }       // стёр пробел, дописал запятую
            else if sepKind == 1 { events += "\t" }
            else if sepKind == 2 && doubleSpaces { events += "  " }
            else { events += " " }
            typedWords.append(final)
        }
        var s = TypingSession(detector: detector, layouts: layouts, current: .ru)
        var screen = "", log: [String] = []
        try zzType(events, &s, &screen, &log, layouts: layouts)
        let shown = screen.split(whereSeparator: \.isWhitespace).map(String.init)
        var ok = shown.count == typedWords.count
        if ok {
            for (w, t) in zip(shown, typedWords) {
                // дописанная после ⌫ запятая печатается в раскладке, какая тогда стоит, — сверяется слово без неё
                let (w, t) = t.hasSuffix(",") && (w.hasSuffix(",") || w.hasSuffix("?")) ? (String(w.dropLast()), String(t.dropLast())) : (w, t)
                let keys = try #require(ru.keystrokes(for: t))
                if !layouts.values.contains(where: { $0.text(for: keys) == w }) { ok = false }
            }
        }
        if !ok { failures.append("[\(round)] «\(events.replacingOccurrences(of: "\t", with: "⇥"))» → «\(screen.replacingOccurrences(of: "\t", with: "⇥"))»") }
    }
    #expect(failures.isEmpty, "\(failures.count) испорченных: \(failures.prefix(6).joined(separator: " | "))")
}

// MARK: - B51: отмена теряется или не наступает
// Не регрессии относительно 298722a (там «беларускіх» остаётся всегда): новая отмена не срабатывает там, где spec её
// обещает.

/// M. ⌫ стирает пробел после слова условного ухода, пробел снова — то же слово, набранное теперь в белорусской,
/// «бывает только в новом языке» и подтверждает собственный уход. Дальше «слов» уже не отменяет: «беларускіх» остаётся.
/// Так же — с дописанной запятой («беларуских⌫,»): человек дописал знак — слово стало белорусским.
@Test @MainActor func zzBackspaceAndSpaceConfirmsOwnConditionalSwitch() throws {
    let r = try zzScreen("употреблением беларуских ⌫ слов ")
    #expect(r.text == "употреблением беларуских слов ", "\(r.text) \(r.log)")
    let comma = try zzScreen("употреблением беларуских ⌫, слов ")
    #expect(comma.text == "употреблением беларуских, слов ", "\(comma.text) \(comma.log)")
}

/// M. Скобка между уходом и отменой: открывающая ставит start = 0 для пустого предложения, закрывающая —
/// sentence.count, и прежний start во внешнем предложении теряется. «слов» отменяет уход (журнал: «уход не
/// подтвердился»), но «беларускіх» не переписывается. «(да)» — слово обоих языков, оно ничего не решает (spec).
@Test @MainActor func zzBracketAsideLosesCancel() throws {
    // Предел, принятый после второго круга (B55): скобка — отдельное предложение, отмена после неё возвращает только
    // раскладку. Возврат текста перед скобкой портил «(п. 3)» — текст цел, слово ухода остаётся с «і».
    let r = try zzScreen("употреблением беларуских (да) слов ")
    #expect(r.text == "употреблением беларускіх (да) слов " && r.language == .ru, "\(r.text) \(r.log)")
}

/// M. Слово, отменяющее уход, начинается со скобки: rollback взят до того, как открывающая очистила предложение, —
/// переписывается только пустое предложение скобки. Внешнее «беларускіх» остаётся, а `outer` запомнил раскладку
/// условного ухода (be) — после «)» раскладка снова белорусская.
@Test @MainActor func zzCancelInsideBracketKeepsWordAndRestoresBelarusian() throws {
    let r = try zzScreen("употреблением беларуских (слов) ")
    #expect(r.text == "употреблением беларуских (слов) ", "\(r.text) \(r.log)")
    #expect(r.language == .ru, "\(r.language)")
}

/// M/L. Латинское слово, ушедшее на лету в en, снимает условный уход (`current` didSet), хотя по spec слово не из
/// ru/be ничего не решает; следующее русское слово уже не отменяет: «беларускіх API слов».
@Test @MainActor func zzLatinWordBetweenFinalizesConditionalSwitch() throws {
    let r = try zzScreen("употреблением беларуских ФЗШ слов ")
    #expect(r.text == "употреблением беларуских API слов ", "\(r.text) \(r.log)")
}

// MARK: - B52

/// M (B52 × B51). С галочкой русская аббревиатура после условного ухода печатается белорусскими буквами («ІНН»):
/// её не исправить, но она же и не отменяет ошибочный уход. Без галочки — «беларуских ИНН.» (отмена на лету).
@Test @MainActor func zzAbbreviationSettingBlocksCancelOfConditionalSwitch() throws {
    let off = try zzScreen("употреблением беларуских ИНН. ")
    #expect(off.text == "употреблением беларуских ИНН. ", "\(off.text)")
    let on = try zzScreen("употреблением беларуских ИНН. ") { $0.skipAbbreviations = true }
    #expect(on.text == "употреблением беларуских ИНН. ", "\(on.text) \(on.log)")
}

/// L (B52). С галочкой аббревиатура «само не исправляется» (spec), но перевод предложения при уходе между кириллицами
/// её переписывает: «ГИБДД зразумещ» → «ГІБДД зразумеў» (и «ИИ прывитанне» → «ІІ прывітанне»).
@Test @MainActor func zzAbbreviationRewrittenBySentenceSwitch() throws {
    let r = try zzScreen("ГИБДД зразумещ ") { $0.skipAbbreviations = true }
    #expect(r.text == "ГИБДД зразумеў ", "\(r.text) \(r.log)")
}

/// Падений и стирания больше, чем есть на экране, нет: случайные ⌫ (до трёх подряд), ⌥, сброс, Enter, скобки, три
/// кириллицы и галочка аббревиатур. Проходит — в отчёте как «не нашлось».
@Test(arguments: [false, true]) @MainActor func zzFuzzNoCrashNoOverDelete(threeCyrillics: Bool) throws {
    let (detector, layouts) = try makeDetector(threeCyrillics ? defaultLayoutIDs : ownerLayoutIDs, pcPunctuation: true)
    let words = ["слов", "привет", "широко", "и", "всё", "кто", "то", "беларуских", "запасик", "прывитанне", "зразумещ",
                 "нацисни", "з", "руддщ", "ФЗШ", "ИНН", "да", "щи", "вын", "(", ")", "«", "»", ".", ","]
    var seed: UInt64 = 0x0310_dead
    func rnd(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(n)) }
    var over: [String] = []
    for round in 0..<adversaryFuzzRounds {
        var s = TypingSession(detector: detector, layouts: layouts, current: .ru)
        s.skipAbbreviations = round % 2 == 0
        s.correctTypos = round % 3 == 0
        var screen = "", events = ""
        func apply(_ actions: [TypingSession.Action]) {
            for case let .replace(n, text) in actions {
                if n > screen.count { over.append("[\(round)] «\(events)» стирает \(n) из «\(screen)»") }
                screen = String(screen.dropLast(n)) + text
            }
        }
        for _ in 0..<(4 + rnd(8)) {
            let w = words[rnd(words.count)]
            for ch in w {
                guard let key = layouts[.ru]?.keystrokes(for: String(ch))?.first else { continue }
                let before = s.current
                let actions = s.key(key)
                if actions.isEmpty { screen += layouts[before]?.chars[key] ?? "" } else { apply(actions) }
                events.append(ch)
            }
            switch rnd(14) {
            case 0: for _ in 0...rnd(3) { s.backspace(); if !screen.isEmpty { screen.removeLast() }; events += "⌫" }
            case 1: apply(s.cycleWord()); events += "⌥"
            case 2: s.reset(); events += "⟲"
            case 3: apply(s.separator("\n")); screen += "\n"; events += "⏎"
            case 4: apply(s.separator(" ")); screen += " "; apply(s.cycleWord()); events += " ⌥"
            default: apply(s.separator(" ")); screen += " "; events += " "
            }
        }
    }
    #expect(over.isEmpty, "\(over.count): \(over.prefix(5).joined(separator: " | "))")
}
