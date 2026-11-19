import Foundation
import Testing
@testable import LitaraCore

// Скептик B56, второй круг (коммит 6d10e43: «зп» — слово ru и be в `extraWords`; `isPrefix` знает начала слов
// `extraWords` — «оке», «окей» стали началами белорусского, «окей» — русского). Красные тесты — находки; зелёные —
// атаки, которые не прошли (покрытие).

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

/// Экран после набора кусков: каждый кусок — пальцами своей раскладки; нажатие без действий печатает знак текущей.
@MainActor
private func screen(_ segments: [(String, Language)], from start: Language, detector: LanguageDetector,
                    layouts: [Language: KeyboardLayout]) throws -> (text: String, language: Language, log: [String]) {
    var s = TypingSession(detector: detector, layouts: layouts, current: start)
    var text = "", log: [String] = []
    func apply(_ actions: [TypingSession.Action]) {
        for case let .replace(n, new) in actions { text = String(text.dropLast(n)) + new }
    }
    for (input, keyboard) in segments {
        for ch in input {
            if ch == " " || ch == "\n" {
                apply(s.separator(String(ch)))
                text.append(ch)
                if let decision = s.lastDecision { log.append(decision) }
            } else {
                let key = try #require(layouts[keyboard]?.keystrokes(for: String(ch))?.first, "\(ch) в \(keyboard)")
                let before = s.current
                let actions = s.key(key)
                if actions.isEmpty { text += layouts[before]?.chars[key] ?? "" } else { apply(actions); log.append(s.lastDecision ?? "") }
            }
        }
    }
    return (text, s.current, log)
}

// MARK: - Находки (красные)

/// H, регрессия 6d10e43. Раскладки владельца и пятиязычный набор (знаки ПК, как в приложении). Белорусская фраза из
/// слов, которые есть и в русском («кіно», «і», «лісты» — в русской раскладке «кино», «и», «листы»), английское слово,
/// затем русское слово на «оке…» пальцами в английской раскладке («jrtfy» — «океан», «Jrt» — «Оке», предложный падеж
/// «Ока»). На третьей букве «jrt» уходит на лету в БЕЛОРУССКУЮ: `textLanguage(over:whole: false)` спрашивает
/// `isPrefix("оке", .be)`, а он теперь «да» только из-за «окей» в `extraWords`. По пробелу «океан» [be] не слово, русское —
/// слово: исправление кириллица → кириллица, белорусских-только слов в предложении нет (`sentenceStart`) — переводится
/// ВСЁ предложение: «кіно і лісты apple океан» → «кино и листы apple океан». До 6d10e43 (и до 792305a) «jrt» уходило
/// сразу в русскую — латиница → кириллица переводит одно слово, белорусские слова оставались.
/// Механизм старый: так же «молоко», «сорок» (общие начала «мол», «сор») — проба на 792305a; 6d10e43 добавил к нему
/// все русские слова на «оке…».
@Test @MainActor func adversaryB56R2OkePrefixKeepsBelarusianSentence() throws {
    for (ids, name) in [(ownerLayoutIDs, "владелец"), (defaultLayoutIDs, "пять")] {
        let (detector, layouts) = try makeDetector(ids, pcPunctuation: true)
        for (sentence, word) in [("кіно і лісты ", "океан"), ("і ", "Оке"), ("лісты і кіно ", "Океании")] {
            let r = try screen([(sentence, .be), ("фззду ", .be), (word + " ", .ru)], from: .be, detector: detector, layouts: layouts)
            #expect(r.text == sentence + "apple " + word + " ", "\(name): \(r.text) \(r.log)")
        }
    }
}

/// M, регрессия 6d10e43. Раскладки владельца. Русская фраза, условный уход B51 («беларуских» → «беларускіх» [be]),
/// английское слово, затем «окей» пальцами в английской раскладке. До коммита «jrt» уходило на лету в русскую — это
/// отмена условного ухода: «беларуских» возвращалось, раскладка — русская. Теперь «jrt» уходит в белорусскую (язык
/// текста — у слова условного ухода, а «оке» — начало белорусского «окей»), «окей» — слово обоих и уход ни отменяет,
/// ни подтверждает: в конце сообщения остаются «беларускіх» и белорусская раскладка. По букве spec (ничья из латиницы —
/// язык текста) новое поведение последовательно; «ок», «ну» на этом месте не отменяли уход и до 792305a («jr», «ye»
/// оставались латиницей) — проба, не регрессия.
@Test @MainActor func adversaryB56R2OkeyFromLatinStillCancelsConditionalSwitch() throws {
    let (detector, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    let r = try screen([("привет беларуских ", .ru), ("фззду ", .be), ("окей ", .ru)], from: .ru, detector: detector, layouts: layouts)
    #expect(r.text == "привет беларуских apple окей " && r.language == .ru, "\(r.text) \(r.language) \(r.log)")
}

/// H, старое (и до 792305a), неполнота 6d10e43. Раскладки владельца: русское «зп» с дефисом — «зп-шка», «зп-то» —
/// в русской и белорусской раскладке по пробелу становится латиницей («pg-irf»). 6d10e43 сделал словом только «зп»
/// целиком; `impossibleCorrection` делит слово по дефису, и «^зп», «зп$» нет в таблицах троек ru/be, а «^pg», «pg$» в
/// английской есть. Spec: «pg» — не слово английского.
@Test @MainActor func adversaryB56R2ZpWithHyphenStaysCyrillic() throws {
    let (detector, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    for start in [Language.ru, .be] {
        for word in ["зп-шка ", "зп-то "] {
            var s = TypingSession(detector: detector, layouts: layouts, current: start)
            #expect(try type(word, as: start, in: &s, layouts: layouts).isEmpty, "\(word) [\(start)] → \(s.lastDecision ?? "")")
        }
    }
}

// MARK: - Атаки, которые не прошли (зелёные)

@Test @MainActor func adversaryB56R2OkePrefixElsewhere() throws {
    let (detector, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    // русская фраза: «океан» с латиницы — в русскую на лету, как до коммита
    let ru = try screen([("привет ", .ru), ("фззду ", .ru), ("океан ", .ru)], from: .ru, detector: detector, layouts: layouts)
    #expect(ru.text == "привет apple океан " && ru.language == .ru, "\(ru.log)")
    // начало сообщения: «Океан», «ОКЕЙ» — в русскую
    for word in ["Океан ", "ОКЕЙ "] {
        let r = try screen([(word, .ru)], from: .en, detector: detector, layouts: layouts)
        #expect(r.text == word && r.language == .ru, "\(r.log)")
    }
    // в русской раскладке «океан», «окей», «Оке» не трогаются; в белорусской — «окей», «ОКЕЙ»
    for (start, words) in [(Language.ru, "океан окей Оке "), (.be, "окей ОКЕЙ Окей ")] {
        var s = TypingSession(detector: detector, layouts: layouts, current: start)
        #expect(try type(words, as: .ru, in: &s, layouts: layouts).isEmpty, "\(start)")
    }
    // белорусская фраза с белорусским-только словом: «океан» исправляется одно, «дзякуй» остаётся
    let be = try screen([("дзякуй ", .be), ("фззду ", .be), ("океан ", .ru)], from: .be, detector: detector, layouts: layouts)
    #expect(be.text == "дзякуй apple океан ")
    // «окей слов» отменяет условный уход и после латиницы
    let cancel = try screen([("привет беларуских ", .ru), ("фззду ", .be), ("окей слов ", .ru)], from: .ru, detector: detector,
                            layouts: layouts)
    #expect(cancel.text == "привет беларуских apple окей слов " && cancel.language == .ru, "\(cancel.log)")
}

@Test @MainActor func adversaryB56R2ZpEverywhere() throws {
    let (detector, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    // в русской и белорусской со знаками и в скобках «зп» остаётся; «з/п», «з.п.», «ЗП-шка», «зпшка» — тоже
    for start in [Language.ru, .be] {
        for word in ["зп, ", "зп. ", "зп? ", "(зп) ", "\"зп\" ", "ЗП-шка ", "зпшка ", "ЗПшка "] {
            var s = TypingSession(detector: detector, layouts: layouts, current: start)
            #expect(try type(word, as: .ru, in: &s, layouts: layouts).isEmpty, "\(word) [\(start)] → \(s.lastDecision ?? "")")
        }
    }
    var slash = TypingSession(detector: detector, layouts: layouts, current: .ru)
    #expect(try type("з/п з.п. ", as: .ru, in: &slash, layouts: layouts).isEmpty)
    // однобуквенное перед «pg»: «z pg» → «я зп»
    #expect(try screen([("я зп ", .ru)], from: .en, detector: detector, layouts: layouts).text == "я зп ")
    // условный уход B51: «зп» не подтверждает и не отменяет, «слов» отменяет
    let b51 = try screen([("привет беларуских зп слов ", .ru)], from: .ru, detector: detector, layouts: layouts)
    #expect(b51.text == "привет беларуских зп слов " && b51.language == .ru, "\(b51.log)")
    // ⌥: «зп» в белорусской → «pg» → снова «зп» в белорусской
    var cycle = TypingSession(detector: detector, layouts: layouts, current: .be)
    _ = try type("зп ", as: .be, in: &cycle, layouts: layouts)
    #expect(cycle.cycleWord() == [.replace(deleteCount: 3, text: "pg "), .switchLayout(.en)])
    #expect(cycle.cycleWord() == [.replace(deleteCount: 3, text: "зп "), .switchLayout(.be)])
    // учёба: «зпшка» вне словарей учится, как прежде
    #expect(detector.learnableWords(in: "зпшка зпшка зп зп", minCount: 1) == ["зпшка"])
    // пятиязычный со знаками ПК: «pg» со знаком — «зп» со знаком; в украинской и белорусской фразе — их язык
    let (d5, l5) = try makeDetector(defaultLayoutIDs, pcPunctuation: true)
    for (word, shown) in [("зп, ", "зп, "), ("зп. ", "зп. "), ("Зп! ", "Зп! ")] {
        let r = try screen([(word, .ru)], from: .en, detector: d5, layouts: l5)
        #expect(r.text == shown && r.language == .ru, "\(r.log)")
        let uk = try screen([("дякую ", .uk), ("фззду ", .uk), (word, .ru)], from: .uk, detector: d5, layouts: l5)
        #expect(uk.text == "дякую apple " + shown && uk.language == .uk, "\(uk.log)")
        let be = try screen([("дзякуй ", .be), ("фззду ", .be), (word, .ru)], from: .be, detector: d5, layouts: l5)
        #expect(be.text == "дзякуй apple " + shown && be.language == .be, "\(be.log)")
    }
}
