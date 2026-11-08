import Foundation
import Testing
@testable import LitaraCore

@Test(arguments: [
    ("ghbdtn", Language.en, Language.ru),   // привет
    ("vfvf", .en, .ru),                     // мама — одинаково в ru и be, не неоднозначность
    ("руддщ", .ru, .en),                    // hello
    ("ghsdbnfyyt", .en, .be),               // прывітанне
    ("ghbdsn", .en, .uk),                   // привіт
    ("nj", .en, .ru),                       // то: в словаре только «NJ» заглавными (проба владельца 2026-10-21)
    ("c", .en, .ru),                        // с: однобуквенное исправляется сразу («z» — польское слово)
    ("синия", .ru, .be),                    // сінія — набрано в русской, слово белорусское
    ("k.,jq", .en, .ru),                    // любой: «. ,» в английской — буквы «ю б» в русской
    ("ghbdtn?", .en, .ru),                  // привет, — Shift+/ в русской ПК даёт запятую
    ("(ghbdtn)", .en, .ru),                 // (привет)
    ("руддщб", .ru, .en),                   // hello, — запятая в английской на месте «б»
])
@MainActor
func correctsWrongLayoutWord(typed: String, current: Language, expected: Language) throws {
    let (detector, layouts) = try makeDetector()
    let keys = try #require(layouts[current]?.keystrokes(for: typed))
    #expect(detector.correction(for: keys, typedIn: current) == expected)
}

@Test(arguments: [
    ("ghbdtn?", Language.en, "привет,"),
    ("k.,jq", .en, "любой"),
    ("руддщб", .ru, "hello,"),
])
@MainActor
func convertsWholeTokenWithPunctuation(typed: String, current: Language, expected: String) throws {
    let (detector, layouts) = try makeDetector()
    let keys = try #require(layouts[current]?.keystrokes(for: typed))
    let target = try #require(detector.correction(for: keys, typedIn: current))
    #expect(layouts[target]?.text(for: keys) == expected)
}

@Test(arguments: [
    ("привет", Language.ru),   // уже слово — не трогать
    ("hello", .en),
    ("a", .en),                // английское однобуквенное слово
    ("qwzx", .en),             // нигде не слово
    ("hello,", .en),           // знак по краю не мешает слову
    ("привет!", .ru),
])
@MainActor
func leavesWordAlone(typed: String, current: Language) throws {
    let (detector, layouts) = try makeDetector()
    let keys = try #require(layouts[current]?.keystrokes(for: typed))
    #expect(detector.correction(for: keys, typedIn: current) == nil)
}

/// Точность на тестовом наборе: каждое слово языка L «набирается» в каждой чужой раскладке S;
/// верно, если после решения детектора на экране слово L. Порог из docs/spec.md: be↔ru ≥ 95%.
@Test @MainActor func accuracyOnCorpus() throws {
    let (detector, layouts) = try makeDetector()
    var report: [String] = []
    var accuracy: [String: Double] = [:]
    for intended in Language.allCases {
        let url = try #require(Bundle.module.url(forResource: intended.rawValue, withExtension: "txt",
                                                 subdirectory: "Fixtures"))
        let words = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
        for typedIn in Language.allCases where typedIn != intended {
            var right = 0, total = 0
            var misses: [String] = []
            for word in words {
                guard let keys = layouts[intended]?.keystrokes(for: word) else { continue }
                total += 1
                let shown = detector.correction(for: keys, typedIn: typedIn)
                    .flatMap { layouts[$0]?.text(for: keys) } ?? layouts[typedIn]!.text(for: keys)
                if shown == word { right += 1 } else if misses.count < 4 { misses.append("\(word)→\(shown)") }
            }
            let share = Double(right) / Double(max(total, 1))
            accuracy["\(intended.rawValue)←\(typedIn.rawValue)"] = share
            report.append("\(intended.rawValue) набрано в \(typedIn.rawValue): \(right)/\(total) = \(String(format: "%.1f", share * 100))%  \(misses.joined(separator: ", "))")
        }
    }
    print(report.joined(separator: "\n"))
    #expect(accuracy["be←ru"]! >= 0.95, "be набрано в ru: \(accuracy["be←ru"]!)")
    #expect(accuracy["ru←be"]! >= 0.95, "ru набрано в be: \(accuracy["ru←be"]!)")
}

// Опечатки (решения владельца В26–В31, 2026-10-21). Примеры сверены со словарями прогоном; границы
// строгости — по замеру на чате владельца: короткое, с заглавной, «пропущенная буква» — не трогаем
@Test @MainActor func typoCorrectionIsStrict() throws {
    let (d, layouts) = try makeDetector(ownerLayoutIDs)
    func fix(_ word: String, _ language: Language = .ru) throws -> String? {
        d.typoCorrection(for: try #require(layouts[language]?.keystrokes(for: word)), typedIn: language)
    }
    #expect(try fix("руский") == "русский")
    #expect(try fix("класный,") == "классный,")
    #expect(try fix("приветт") == "привет")
    #expect(try fix("приевт") == "привет")      // проба владельца: на «-евт» слов почти нет
    #expect(try fix("каменты", .be) == nil)     // сленг: «-нты» — обычное окончание
    #expect(try fix("незнаю") == "не знаю")
    #expect(try fix("белаурскую", .be) == "беларускую")
    #expect(try fix("Беларусь") == nil)          // слово словаря
    #expect(try fix("щас") == nil)               // короткое: «ас» рядом
    #expect(try fix("пасьля", .be) == nil)       // тарашкевіца, не опечатка
    #expect(try fix("збаіць", .be) == nil)       // сленг: «-іць» — обычное окончание, «забіць» не подставляем
    #expect(try fix("невідавочны", .be) == nil)  // «не» с прилагательным — слитно
    #expect(d.hyphenated("кто", "то", in: .ru))
    #expect(d.hyphenated("по", "русски", in: .ru))
    #expect(!d.hyphenated("по", "доски", in: .ru))
    #expect(!d.hyphenated("это", "то", in: .ru))
    #expect(d.hyphenated("хто", "небудзь", in: .be))
    #expect(!d.hyphenated("так", "што", in: .be))
}

@Test @MainActor func neighborKeyTypoOnlyIntoUsersWords() throws {
    // проба владельца 2026-10-21: «теперт» — «т» рядом с «ь»; решение владельца — только в слова из его текстов
    let (plain, layouts) = try makeDetector(ownerLayoutIDs)
    let keys = try #require(layouts[.ru]?.keystrokes(for: "теперт"))
    #expect(plain.typoCorrection(for: keys, typedIn: .ru) == nil)  // словаря текстов нет — не трогаем
    var d = plain
    d.vocabulary = Set(d.vocabularyWords(in: "Теперь всё. Теперь точно, привет"))
    #expect(d.vocabulary == ["теперь"])  // от 6 букв и не меньше двух раз
    #expect(d.typoCorrection(for: keys, typedIn: .ru) == "теперь")
}

@Test @MainActor func ownerTyposOfOctober21() throws {
    // проба владельца 2026-10-21: «почемуто», «беспорядочныц» не исправлялись
    let (plain, layouts) = try makeDetector(ownerLayoutIDs)
    let ru = try #require(layouts[.ru])
    func fix(_ word: String, _ d: LanguageDetector) throws -> String? { d.typoCorrection(for: try #require(ru.keystrokes(for: word)), typedIn: .ru) }
    #expect(try fix("почемуто", plain) == "почему-то")
    #expect(try fix("Чтото", plain) == "Что-то")
    #expect(try fix("коечто", plain) == "кое-что")
    #expect(try fix("беспорядочныц", plain) == nil)  // промах — только в слова из текстов
    var d = plain
    d.vocabulary = ["беспорядочный"]
    #expect(try fix("беспорядочныц", d) == "беспорядочный")  // длинное слово: слом по окончанию «-ныц»
    // не та буква — любая, не только соседняя клавиша (решение владельца 2026-10-21)
    d.vocabulary = ["символов"]
    #expect(try fix("симполов", d) == "символов")
}


/// Замер опечаток на словах из чата (B21) — только по запросу: BLALB_TYPO_CORPUS — файл «число\tслово»,
/// BLALB_TYPO_LANG — ru или be, BLALB_VOCABULARY — слова из текстов владельца, BLALB_USER_WORDS — «Мои слова» и
/// выученные (по строке), BLALB_TYPO_OUT — куда записать «число\tслово\tисправление».
@Test(.enabled(if: ProcessInfo.processInfo.environment["BLALB_TYPO_CORPUS"] != nil)) @MainActor
func typoReplay() throws {
    let env = ProcessInfo.processInfo.environment
    let language = Language(rawValue: env["BLALB_TYPO_LANG"] ?? "ru") ?? .ru
    let userWords = try env["BLALB_USER_WORDS"].map { try String(contentsOfFile: $0, encoding: .utf8).split(separator: "\n").map(String.init) } ?? []
    var (d, layouts) = try makeDetector(ownerLayoutIDs, userWords: userWords)
    if let path = env["BLALB_VOCABULARY"] {
        d.vocabulary = Set(try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n").map(String.init))
    }
    var out = ""
    for line in try String(contentsOfFile: try #require(env["BLALB_TYPO_CORPUS"]), encoding: .utf8).split(separator: "\n") {
        let parts = line.split(separator: "\t")
        guard parts.count == 2, let keys = layouts[language]?.keystrokes(for: String(parts[1])),
              let fixed = d.typoCorrection(for: keys, typedIn: language) else { continue }
        // где набранное перестаёт быть началом слова и бывает ли его окончание — для подбора строгости
        let word = String(parts[1])
        let breakAt = (3...max(3, min(word.count, 8))).first { !d.isPrefix(String(word.prefix($0)), in: language) }.map { $0 - 1 } ?? -1
        out += "\(parts[0])\t\(word)\t\(fixed)\t\(breakAt)\t\(d.endingPossible(word, in: language))\n"
    }
    try out.write(toFile: try #require(env["BLALB_TYPO_OUT"]), atomically: true, encoding: .utf8)
}

@Test @MainActor func shortWordNeighborKeyTypoIntoUsersWords() throws {
    // проба владельца 2026-11-05 (B21): «есои» вместо «если» — «о» рядом с «л». Решение владельца после замера на его
    // чатах: короткое слово (4–5 букв) — только соседняя клавиша и только в слово из его текстов
    let (plain, layouts) = try makeDetector(ownerLayoutIDs)
    let ru = try #require(layouts[.ru])
    func fix(_ word: String, _ d: LanguageDetector) throws -> String? { d.typoCorrection(for: try #require(ru.keystrokes(for: word)), typedIn: .ru) }
    #expect(try fix("есои", plain) == nil)  // «если» ещё не знакомо
    var d = plain
    d.vocabulary = Set(d.vocabularyWords(in: "Если что, пиши. Если нет — ладно"))
    #expect(d.vocabulary.contains("если"))  // знакомые слова — от 4 букв
    #expect(try fix("есои", d) == "если")
    #expect(try fix("есхи", d) == nil)      // «х» не рядом с «л»: короткое слово — только соседняя клавиша
    d.vocabulary.insert("клавиши")
    #expect(try fix("клавтши", d) == "клавиши")
    // на наборе: «если», дважды набранное без исправлений, становится знакомым
    var s = TypingSession(detector: plain, layouts: layouts, current: .ru)
    s.correctTypos = true
    for key in try #require(ru.keystrokes(for: "если")) { _ = s.key(key) }
    _ = s.separator(" ")
    for key in try #require(ru.keystrokes(for: "если")) { _ = s.key(key) }
    _ = s.separator(" ")
    #expect(s.takeLearned().contains("если"))
}

// Слово вне словарей — по невозможной тройке букв (выбор владельца 2026-11-08). Примеры — промахи из журнала владельца,
// которые он исправлял ⌥: «шызще» — повод исследования, gmail, ERP, KPI — с 29.10 по 08.11. Латиница → кириллица —
// «Тиктокер» вместо промаха журнала с матом: тесты уходят в открытый репозиторий.
@Test(arguments: [
    ("шызще", Language.ru, Language.en, "ispot"),  // «шыз», «ызщ», «зще» в русском не бывает
    ("пьфшд", .ru, .en, "gmail"),
    ("УКЗ", .ru, .en, "ERP"),                      // короткие ПРОПИСНЫЕ кириллицей — трогаются
    ("ЛЗШ", .ru, .en, "KPI"),
    ("Nbrnjrth", .en, .ru, "Тиктокер"),
])
@MainActor
func impossibleWordGoesToThePossibleVariant(typed: String, current: Language, expected: Language, text: String) throws {
    let (detector, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    let keys = try #require(layouts[current]?.keystrokes(for: typed))
    #expect(detector.correction(for: keys, typedIn: current) == nil)  // словарь молчит: ни одного слова
    let target = detector.impossibleCorrection(for: keys, typedIn: current)
    #expect(target == expected)
    #expect(target.flatMap { layouts[$0]?.text(for: keys) } == text)
}

// Каждое из них без своего фильтра переключилось бы (замер на чатах 2026-11-08): короткие латинские ПРОПИСНЫЕ —
// аббревиатуры («DNS» → «ВТЫ»), опечатка словарного слова («Вырашыу» — «вырашыў», не «Dshfise»), регистр как у кода.
// Скептик 2026-11-08: «неулупіў» — «не» слитно с глаголом, это правит typoCorrection («не улупіў»), а не «ytekegbo»;
// «ОГЭ» — «э» в «США международной» мёртвый апостроф, вариант «JU» короче набранного (R21).
@Test(arguments: [("DNS", Language.en), ("RTX", .en), ("Вырашыу", .be), ("гіфкі", .be), ("KBDiteF", .en),
                  ("ghbdtn", .en),  // словарный вариант — решает correction, не это правило
                  ("неулупіў", .be), ("ОГЭ", .ru)])
@MainActor
func impossibleWordRuleLeavesAlone(typed: String, current: Language) throws {
    let (detector, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    let keys = try #require(layouts[current]?.keystrokes(for: typed))
    #expect(detector.impossibleCorrection(for: keys, typedIn: current) == nil)
}

@Test @MainActor func learnedWordStopsImpossibleRule() throws {
    let (fresh, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    let keys = try #require(layouts[.be]?.keystrokes(for: "ШІ"))
    // новый пользователь: «ШІ» → «IB» (замер на чате «Беларускі ШІ» — 279 раз)
    #expect(fresh.impossibleCorrection(for: keys, typedIn: .be) == .en)
    // учёбу слов правило не отсекает: «ші» из своих текстов выучится, и правило замолчит
    #expect(fresh.learnableWords(in: "ШІ ШІ ші").contains("ші"))
    let (learned, _) = try makeDetector(ownerLayoutIDs, pcPunctuation: true, userWords: ["ші"])
    #expect(learned.impossibleCorrection(for: keys, typedIn: .be) == nil)
}

@Test @MainActor func impossibleWordRuleSkipsLongTokens() throws {
    // зажатая клавиша или склейка — не слово; потолок в 40 знаков держит обработчик нажатий быстрым (скептик 2026-11-08:
    // 300 букв — 140 мс)
    let (detector, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    let ru = try #require(layouts[.ru])
    let forty = try #require(ru.keystrokes(for: String(repeating: "шызще", count: 8)))
    #expect(detector.impossibleCorrection(for: forty, typedIn: .ru) == .en)
    let longer = try #require(ru.keystrokes(for: String(repeating: "шызще", count: 9)))
    #expect(detector.impossibleCorrection(for: longer, typedIn: .ru) == nil)
}

@Test @MainActor func impossibleWordPrefersSentenceLanguage() throws {
    // «панамара» одинакова и возможна в ru и be: без языка предложения — порядок языков, с ним — он
    let (detector, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    let keys = try #require(layouts[.en]?.keystrokes(for: "gfyfvfhf"))
    #expect(detector.impossibleCorrection(for: keys, typedIn: .en) == .ru)
    #expect(detector.impossibleCorrection(for: keys, typedIn: .en, preferring: .be) == .be)
}

@Test func trigramsOfText() {
    #expect(LanguageDetector.trigrams(of: "Сям’я") == ["^ся", "сям", "ям'", "м'я", "'я$"])
    // цифры, дефис и двойной апостроф делят слова
    #expect(LanguageDetector.trigrams(of: "a''b 2x-y") == ["^a$", "^b$", "^x$", "^y$"])
}
