import Foundation
import Testing
@testable import LitaraCore

// Скептик B56 (коммит 792305a: «jr», «ye», «pg» — не слова en, «jr», «pg» — не слова pl; «ок», «окей» — слова ru и be).
// Красные тесты — находки; зелёные — атаки, которые не прошли (покрытие).

/// Набирает строку пальцами раскладки `keyboard` (человек думает, что он в ней); пробел и Enter — разделители.
@MainActor
private func type(_ input: String, as keyboard: Language, in session: inout TypingSession,
                  layouts: [Language: KeyboardLayout]) throws -> [TypingSession.Action] {
    var actions: [TypingSession.Action] = []
    for ch in input {
        if ch == " " || ch == "\n" {
            actions += session.separator(String(ch))
        } else {
            let key = try #require(layouts[keyboard]?.keystrokes(for: String(ch))?.first, "\(ch) в \(keyboard)")
            actions += session.key(key)
        }
    }
    return actions
}

// MARK: - Находки (красные)

/// H, регрессия коммита. Пятиязычный набор (`defaultLayoutIDs`), «Моих слов» нет: «pg» перестало быть английским и
/// польским словом, а в украинском словаре «зп» есть (Dictionaries/uk/index.dic:105850) — «pg», «Pg», «PG», набранные
/// в английской или польской, уходят в «зп» и переключают раскладку на УКРАИНСКУЮ. До коммита оставались как набраны.
/// Починка: «зп» — слово и русского, и белорусского (`extraWords`), ничья кириллиц решается языком текста, без него —
/// русской, первой по порядку; в украинскую «pg» не уводит.
@Test @MainActor func adversaryB56PgDoesNotPullLatinIntoUkrainian() throws {
    let (detector, layouts) = try makeDetector(defaultLayoutIDs)
    for start in [Language.en, .pl] {
        for (word, shown) in [("pg ", "зп"), ("Pg ", "Зп"), ("PG ", "ЗП")] {
            var s = TypingSession(detector: detector, layouts: layouts, current: start)
            let actions = try type(word, as: start, in: &s, layouts: layouts)
            #expect(actions == [.replace(deleteCount: 2, text: shown), .switchLayout(.ru)],
                    "\(word) [\(start)] → \(s.lastDecision ?? "")")
        }
    }
}

/// H, регрессия коммита. Пятиязычный набор: русская фраза, английское слово, затем «зп» пальцами русской в английской
/// раскладке («pg») — уходит в «зп» [uk], и следующее русское «мы» печатается украинским «мі» и остаётся (оба — слова).
@Test @MainActor func adversaryB56PgInRussianSentenceKeepsRussian() throws {
    let (detector, layouts) = try makeDetector(defaultLayoutIDs)
    var s = TypingSession(detector: detector, layouts: layouts, current: .ru)
    _ = try type("дорога ", as: .ru, in: &s, layouts: layouts)
    _ = try type("фззду ", as: .ru, in: &s, layouts: layouts)     // apple
    #expect(s.current == .en)
    _ = try type("зп ", as: .ru, in: &s, layouts: layouts)        // «pg» на экране
    #expect(s.current != .uk, "\(s.lastDecision ?? "")")
    _ = try type("мы ", as: .ru, in: &s, layouts: layouts)
    #expect(s.lastDecision?.contains("«мі»") != true, "\(s.lastDecision ?? "")")
}

/// H, не регрессия — неполнота коммита. Раскладки владельца, «ЗП» нет в «Моих словах»: верно набранное русское и
/// белорусское «зп» / «ЗП» / «Зп» по пробелу становится английским «pg» / «PG» / «Pg». `isWord` «pg» уже не знает,
/// но `impossibleCorrection` (B47) решает по таблице троек en.trigrams, собранной из того же словаря: «^pg», «pg$» в ней
/// есть, «^зп» в ru/be нет. Spec: «pg» — не слово английского «в любом регистре».
@Test @MainActor func adversaryB56CyrillicZpIsNotRetypedAsPg() throws {
    let (detector, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    for start in [Language.ru, .be] {
        for word in ["зп ", "ЗП ", "Зп "] {
            var s = TypingSession(detector: detector, layouts: layouts, current: start)
            #expect(try type(word, as: start, in: &s, layouts: layouts).isEmpty, "\(word) [\(start)] → \(s.lastDecision ?? "")")
        }
        let keys = try #require(layouts[start]?.keystrokes(for: "зп"))
        #expect(detector.impossibleCorrection(for: keys, typedIn: start) == nil)
    }
}

/// M, неполнота коммита. Раскладки владельца: белорусская фраза («дзякуй»), английское слово, затем «окей» в английской
/// раскладке («jrtq»). «окей» теперь слово обоих — ничья решается языком текста (spec: «Ничья между кириллицами при
/// наборе из латиницы… решается языком текста»), и «jr» так и уходит в белорусскую. Но «jrtq» на третьей букве уходит
/// на лету в РУССКУЮ: `textLanguage(over:whole: false)` спрашивает `isPrefix("оке", .be)`, а он `extraWords` не знает;
/// дальше раскладка русская, а «окей» в ней слово — пробел ничего не меняет. Белорусский текст дальше идёт в русской.
/// Держит нынешнее (B57): починка началами `extraWords` в `isPrefix` откачена вторым кругом скептика — «оке» стало
/// белорусским началом всех слов на «оке…» и через R25 переписывало белорусскую фразу по-русски. Текст верен («окей»),
/// раскладка русская; станет белорусской вместе с B58.
@Test @MainActor func adversaryB56OkeyInBelarusianSentenceStaysBelarusian() throws {
    let (detector, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    for (word, shown) in [("jrtq ", "окей"), ("Jrtq ", "Окей")] {
        var s = TypingSession(detector: detector, layouts: layouts, current: .en)
        _ = try type("lpzreq ", as: .en, in: &s, layouts: layouts)    // дзякуй
        _ = try type("фззду ", as: .be, in: &s, layouts: layouts)     // apple
        _ = try type(word, as: .en, in: &s, layouts: layouts)
        #expect(s.current == .ru, "\(word) → \(s.lastDecision ?? "")")
        #expect(s.lastDecision?.hasPrefix("«\(shown)» [ru]") == true, "\(s.lastDecision ?? "")")
    }
}

// MARK: - Атаки, которые не прошли (зелёные)

@Test @MainActor func adversaryB56CaseAndPunctuationAroundJr() throws {
    let (detector, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    func run(_ input: String) throws -> ([TypingSession.Action], Language) {
        var s = TypingSession(detector: detector, layouts: layouts, current: .en)
        return (try type(input, as: .en, in: &s, layouts: layouts), s.current)
    }
    #expect(try run("JR ").0 == [.replace(deleteCount: 2, text: "ОК"), .switchLayout(.ru)])
    #expect(try run("jR ").0 == [.replace(deleteCount: 2, text: "оК"), .switchLayout(.ru)])
    #expect(try run("YE ").0 == [.replace(deleteCount: 2, text: "НУ"), .switchLayout(.ru)])
    // знаки «Русской – ПК» пальцами в английской: «.» — «/», «,» — «?», «?» — «&», «"» — «@»
    #expect(try run("Jr/ ").0 == [.replace(deleteCount: 3, text: "Ок."), .switchLayout(.ru)])
    #expect(try run("jr? ").0 == [.replace(deleteCount: 3, text: "ок,"), .switchLayout(.ru)])
    #expect(try run("jr& ").0 == [.replace(deleteCount: 3, text: "ок?"), .switchLayout(.ru)])
    #expect(try run("jr! ").0 == [.replace(deleteCount: 3, text: "ок!"), .switchLayout(.ru)])
    #expect(try run("@jr@ ").0 == [.replace(deleteCount: 4, text: "\"ок\""), .switchLayout(.ru)])
    let (paren, after) = try run("(jr) ")
    #expect(paren == [.replace(deleteCount: 3, text: "ок)"), .switchLayout(.ru), .switchLayout(.en)])
    #expect(after == .en)
    // английский текст со знаками, дающими в русской букву, остаётся как набран (и до коммита)
    for input in ["Jr. ", "jr, ", "jr; ", "jr-jr ", "pg. ", "Jr's "] {
        #expect(try run(input).0.isEmpty, "\(input)")
    }
    // «зп» — слово ru и be (`extraWords`, починка находки скептика): «pg» становится им и без «Моих слов»
    #expect(try run("pg ").0 == [.replace(deleteCount: 2, text: "зп"), .switchLayout(.ru)])
    #expect(try run("PG ").0 == [.replace(deleteCount: 2, text: "ЗП"), .switchLayout(.ru)])
    // «окей» на лету и по пробелу
    #expect(try run("jrtq ") == ([.replace(deleteCount: 2, text: "оке"), .switchLayout(.ru)], .ru))
}

@Test @MainActor func adversaryB56TieGoesToSentenceLanguage() throws {
    let (detector, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    for (word, text) in [("jr ", "ок"), ("ye ", "ну")] {
        var s = TypingSession(detector: detector, layouts: layouts, current: .en)
        _ = try type("lpzreq ", as: .en, in: &s, layouts: layouts)    // дзякуй
        _ = try type("фззду ", as: .be, in: &s, layouts: layouts)     // apple
        #expect(try type(word, as: .en, in: &s, layouts: layouts) == [.replace(deleteCount: 2, text: text), .switchLayout(.be)])
    }
    // пятиязычный: в украинской фразе «jr» — украинское «ок»; «ок», «окей» в украинской остаются
    let (d5, l5) = try makeDetector(defaultLayoutIDs)
    var u = TypingSession(detector: d5, layouts: l5, current: .uk)
    _ = try type("дякую ", as: .uk, in: &u, layouts: l5)
    _ = try type("фззду ", as: .uk, in: &u, layouts: l5)
    #expect(try type("jr ", as: .en, in: &u, layouts: l5) == [.replace(deleteCount: 2, text: "ок"), .switchLayout(.uk)])
    for word in ["ок ", "окей ", "Ок "] {
        var s = TypingSession(detector: d5, layouts: l5, current: .uk)
        #expect(try type(word, as: .uk, in: &s, layouts: l5).isEmpty, "\(word)")
        var b = TypingSession(detector: d5, layouts: l5, current: .be)
        #expect(try type(word, as: .be, in: &b, layouts: l5).isEmpty, "\(word)")   // до коммита уходило в «ок» [uk]
    }
}

@Test @MainActor func adversaryB56SettingsStillWin() throws {
    let (detector, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    var a = TypingSession(detector: detector, layouts: layouts, current: .en)
    a.skipAbbreviations = true
    #expect(try type("JR ", as: .en, in: &a, layouts: layouts).isEmpty)
    #expect(try type("YE ", as: .en, in: &a, layouts: layouts).isEmpty)
    var e = TypingSession(detector: detector, layouts: layouts, current: .en)
    e.exceptions = ["Jr"]
    #expect(try type("jr Jr JR ", as: .en, in: &e, layouts: layouts).isEmpty)
    var r = TypingSession(detector: detector, layouts: layouts, current: .en)
    r.replacements = [Replacement(what: "jr", with: "junior")]
    #expect(try type("jr ", as: .en, in: &r, layouts: layouts) == [.replace(deleteCount: 1, text: "unior")])
    #expect(r.current == .en)
    let (own, _) = try makeDetector(ownerLayoutIDs, pcPunctuation: true, userWords: ["ye", "Jr"])
    var u = TypingSession(detector: own, layouts: layouts, current: .en)
    #expect(try type("ye YE jr ", as: .en, in: &u, layouts: layouts).isEmpty)
}

@Test @MainActor func adversaryB56OkDecidesNothingBetweenCyrillics() throws {
    let (detector, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    // B51: «ок» есть в обоих — условный уход не подтверждает; «слов» его отменяет
    var s = TypingSession(detector: detector, layouts: layouts, current: .ru)
    _ = try type("привет беларуских ", as: .ru, in: &s, layouts: layouts)
    #expect(s.current == .be)
    #expect(try type("ок ", as: .ru, in: &s, layouts: layouts).isEmpty)
    #expect(try type("слов ", as: .ru, in: &s, layouts: layouts) == [.replace(deleteCount: 10, text: "их ок слов"), .switchLayout(.ru)])
    // «ок» в белорусской и русской — не «jr» (до коммита уходило)
    for start in [Language.ru, .be] {
        var t = TypingSession(detector: detector, layouts: layouts, current: start)
        #expect(try type("ок окей ну ", as: start, in: &t, layouts: layouts).isEmpty)
    }
}

@Test @MainActor func adversaryB56HotkeyAndLearning() throws {
    let (detector, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    // ⌥ после «jr» → «ок» возвращает набранное и считается откатом
    var s = TypingSession(detector: detector, layouts: layouts, current: .en)
    _ = try type("jr ", as: .en, in: &s, layouts: layouts)
    #expect(s.cycleWord() == [.replace(deleteCount: 3, text: "jr "), .switchLayout(.en)])
    #expect(s.lastRollback == "jr")
    // ⌥ на «ок», набранном по-русски, даёт «jr» — круг не сломан
    var r = TypingSession(detector: detector, layouts: layouts, current: .ru)
    _ = try type("ок ", as: .ru, in: &r, layouts: layouts)
    #expect(r.cycleWord() == [.replace(deleteCount: 3, text: "jr "), .switchLayout(.en)])
    // учёба: «ок», «окей», «зп» — слова (`extraWords`), учить их незачем
    #expect(detector.learnableWords(in: "окей окей ок ок зп зп", minCount: 1).isEmpty)
}
