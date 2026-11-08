import Foundation
import Testing
@testable import LitaraCore

/// Набирает строку: пробел и Enter — разделители, остальное — нажатия клавиш, на которых эти
/// буквы стоят в раскладке сеанса В НАЧАЛЕ набора (пальцы не знают о переключении на лету).
/// Возвращает действия, накопленные на всех нажатиях и разделителях.
@MainActor
private func type(_ input: String, in session: inout TypingSession, layouts: [Language: KeyboardLayout]) throws -> [TypingSession.Action] {
    var actions: [TypingSession.Action] = []
    let keyboard = session.current
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

@MainActor
private func session(_ current: Language) throws -> (TypingSession, [Language: KeyboardLayout]) {
    let (detector, layouts) = try makeDetector()
    return (TypingSession(detector: detector, layouts: layouts, current: current), layouts)
}

@Test @MainActor func wrongLayoutWordIsRetyped() throws {
    var (s, layouts) = try session(.en)
    // на лету на третьей букве: «gh» на экране → «при»
    #expect(try type("ghbdtn ", in: &s, layouts: layouts) == [.replace(deleteCount: 2, text: "при"), .switchLayout(.ru)])
    #expect(s.current == .ru)
}

@Test @MainActor func impossibleWordIsRetypedOnSpace() throws {
    // повод — «шызще» владельца 2026-11-08: «ispot» нет в словаре, но в русском нет и «шыз», «ызщ», «зще»
    let (detector, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    var s = TypingSession(detector: detector, layouts: layouts, current: .ru)
    #expect(try type("шызще ", in: &s, layouts: layouts) == [.replace(deleteCount: 5, text: "ispot"), .switchLayout(.en)])
    #expect(s.lastDecision == "«шызще» [ru] → «ispot» [en]")
}

@Test @MainActor func impossibleWordKeepsSentenceLanguage() throws {
    // скептик 2026-11-08: в белорусском предложении слово вне словарей уходило в русскую раскладку, и дальше «і»
    // печаталась «и»; «панамара» одинакова и возможна в обеих
    let (detector, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    var s = TypingSession(detector: detector, layouts: layouts, current: .en)
    _ = try type("lpzreq ", in: &s, layouts: layouts)  // дзякуй
    #expect(s.current == .be)
    _ = try type("фззду ", in: &s, layouts: layouts)   // apple
    #expect(s.current == .en)
    #expect(try type("gfyfvfhf ", in: &s, layouts: layouts).last == .switchLayout(.be))
}

@Test @MainActor func rightWordIsLeftAlone() throws {
    var (s, layouts) = try session(.en)
    #expect(try type("hello world ", in: &s, layouts: layouts).isEmpty)
}

@Test @MainActor func singleLetterIsCorrectedAtOnce() throws {
    var (s, layouts) = try session(.en)
    // «c» → «с» сразу по пробелу (раньше ждало второго слова — замечание владельца 2026-10-21);
    // «z» здесь не годится: при включённом польском это польское слово «z»
    #expect(try type("c ", in: &s, layouts: layouts) == [.replace(deleteCount: 1, text: "с"), .switchLayout(.ru)])
    var (s2, _) = try session(.en)
    #expect(try type("a ", in: &s2, layouts: layouts).isEmpty)
}

@Test @MainActor func cyrillicSwitchRetypesWholeSentence() throws {
    var (s, layouts) = try session(.ru)
    // «мы» одинаково в обеих раскладках, «синия» — белорусское слово, набранное в русской
    // на лету на последней букве; стирается только отличающийся хвост «ини»
    #expect(try type("мы синия ", in: &s, layouts: layouts) == [.replace(deleteCount: 3, text: "інія"), .switchLayout(.be)])
}

@Test @MainActor func newSentenceIsNotTouched() throws {
    var (s, layouts) = try session(.ru)
    #expect(try type("мы. синия ", in: &s, layouts: layouts) == [.replace(deleteCount: 3, text: "інія"), .switchLayout(.be)])
    var (s2, _) = try session(.ru)
    #expect(try type("мы\nсиния ", in: &s2, layouts: layouts) == [.replace(deleteCount: 3, text: "інія"), .switchLayout(.be)])
}

@Test @MainActor func bracketsAreSeparateSentenceAndRestoreLayout() throws {
    var (s, layouts) = try session(.ru)
    let actions = try type("мы (синия) ", in: &s, layouts: layouts)
    // слово со скобкой впереди решает пробел; стирается хвост «иния)»
    #expect(actions == [.replace(deleteCount: 5, text: "інія)"), .switchLayout(.be), .switchLayout(.ru)])
    #expect(s.current == .ru)
}

@Test @MainActor func closedBracketsStayOnScreenWhenOuterSentenceIsRetyped() throws {
    var (s, layouts) = try session(.ru)
    _ = try type("мы (синия) ", in: &s, layouts: layouts)
    // скобки — отдельное предложение: их содержимое не переводится, но стирается и печатается как было
    // предложение переводится целиком, но совпадающее начало «мы (сінія) мы с» не стирается
    #expect(try type("мы синия ", in: &s, layouts: layouts) == [.replace(deleteCount: 3, text: "інія"), .switchLayout(.be)])
}

@Test @MainActor func wordWithDeadKeyIsCorrected() throws {
    let (detector, defaults) = try makeDetector()
    var layouts = defaults
    layouts[.en] = try #require(KeyboardLayout.available().first { $0.id == "com.apple.keylayout.USInternational-PC" })
    var s = TypingSession(detector: detector, layouts: layouts, current: .en)
    // v ' h — в русской это «мэр»; апостроф здесь мёртвый, на экране «v'h» — раскладка знает это от системы
    for code: UInt16 in [9, 39, 4] { _ = s.key(Keystroke(code: code)) }
    #expect(s.separator(" ") == [.replace(deleteCount: 3, text: "мэр"), .switchLayout(.ru)])
}

@Test @MainActor func autoCorrectOffLeavesWordAlone() throws {
    var (s, layouts) = try session(.en)
    s.autoCorrect = false
    #expect(try type("ghbdtn ", in: &s, layouts: layouts).isEmpty)
    #expect(s.current == .en)
}

@Test @MainActor func wordIsCorrectedOnTheFlyFromThirdLetter() throws {
    var (s, layouts) = try session(.en)
    // «gh» ещё может быть английским (ghost), «ghb» — нет, а «при» — русское начало
    #expect(try type("gh", in: &s, layouts: layouts).isEmpty)
    #expect(try type("b", in: &s, layouts: layouts) == [.replace(deleteCount: 2, text: "при"), .switchLayout(.ru)])
    // дальше слово набирается уже в русской раскладке, пробел ничего не меняет
    #expect(try type("вет ", in: &s, layouts: layouts).isEmpty)
}

@Test @MainActor func unknownWordIsCaughtByItsStart() throws {
    // проба владельца 2026-10-21: «косячок» нет в словаре, по пробелу не узнавалось
    var (s, layouts) = try session(.en)
    #expect(try type("rjc", in: &s, layouts: layouts) == [.replace(deleteCount: 2, text: "кос"), .switchLayout(.ru)])
}

/// Набор «по экрану»: слово языка L набирается нажатиями в раскладке S (и в своей), действия
/// сеанса применяются к модели экрана; верно, если на экране слово L и пробел. Ловит и ошибку
/// подсчёта стираемых символов, и лишнее исправление правильно набранного слова.
@Test @MainActor func corpusOnScreen() throws {
    let (detector, layouts) = try makeDetector()
    var report: [String] = []
    var share: [String: Double] = [:]
    for intended in Language.allCases {
        let url = try #require(Bundle.module.url(forResource: intended.rawValue, withExtension: "txt", subdirectory: "Fixtures"))
        let words = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
        for typedIn in Language.allCases {
            var right = 0, total = 0, early = 0
            var misses: [String] = []
            for word in words {
                guard let keys = layouts[intended]?.keystrokes(for: word) else { continue }
                total += 1
                var s = TypingSession(detector: detector, layouts: layouts, current: typedIn)
                var screen = ""
                func apply(_ actions: [TypingSession.Action]) {
                    for case let .replace(n, text) in actions { screen = String(screen.dropLast(n)) + text }
                }
                for key in keys {
                    let before = s.current
                    let actions = s.key(key)
                    if actions.isEmpty { screen += layouts[before]?.chars[key] ?? "" } else { apply(actions); early += 1 }
                }
                apply(s.separator(" "))
                screen += " "
                if screen == word + " " { right += 1 } else if misses.count < 3 { misses.append("\(word)→\(screen)") }
            }
            share["\(intended.rawValue)←\(typedIn.rawValue)"] = Double(right) / Double(max(total, 1))
            report.append("\(intended.rawValue) в \(typedIn.rawValue): \(right)/\(total) на лету \(early)  \(misses.joined(separator: ", "))")
        }
    }
    print(report.joined(separator: "\n"))
    for language in Language.allCases {
        #expect(share["\(language.rawValue)←\(language.rawValue)"]! >= 0.99, "своё слово в своей раскладке: \(language)")
    }
    #expect(share["be←ru"]! >= 0.95)
    #expect(share["ru←be"]! >= 0.95)
}

@Test @MainActor func hotkeyCyclesLastWordAndBack() throws {
    var (s, layouts) = try session(.en)
    _ = try type("hello ", in: &s, layouts: layouts)
    #expect(s.cycleWord() == [.replace(deleteCount: 6, text: "руддщ "), .switchLayout(.ru)])
    #expect(s.cycleWord() == [.replace(deleteCount: 2, text: "ў "), .switchLayout(.be)])
    #expect(s.cycleWord() == [.replace(deleteCount: 6, text: "hello "), .switchLayout(.en)])
}

@Test @MainActor func hotkeyFirstPressUndoesAutoCorrection() throws {
    var (s, layouts) = try session(.en)
    _ = try type("ghbdtn ", in: &s, layouts: layouts)   // исправлено на лету в «привет»
    #expect(s.cycleWord() == [.replace(deleteCount: 7, text: "ghbdtn "), .switchLayout(.en)])
}

@Test @MainActor func hotkeyChangesCaseOfLastWord() throws {
    var (s, layouts) = try session(.en)
    _ = try type("hello ", in: &s, layouts: layouts)
    #expect(s.changeCase() == [.replace(deleteCount: 6, text: "HELLO ")])
    #expect(s.changeCase() == [.replace(deleteCount: 6, text: "hello ")])
}

@Test @MainActor func exceptionsAreNeverCorrected() throws {
    // без исключения «ghbdtn» исправляется (на лету); с исключением — остаётся как набрано
    var (plain, layouts) = try session(.en)
    #expect(!(try type("ghbdtn ", in: &plain, layouts: layouts)).isEmpty)
    var (s, _) = try session(.en)
    s.exceptions = ["GHBDTN"]
    #expect(try type("ghbdtn ", in: &s, layouts: layouts).isEmpty)
}

@Test @MainActor func rememberedWordProtectsItsFormsOnTheFly() throws {
    // проба владельца 2026-10-23: «вуф» на лету уходило в «dea»; запомненное после откатов «вуфирму»
    // закрывает начало слова — и другие его формы
    var (plain, layouts) = try session(.ru)
    #expect(!(try type("вуфирму ", in: &plain, layouts: layouts)).isEmpty)
    var (s, _) = try session(.ru)
    s.exceptions = ["вуфирму"]
    #expect(try type("вуфирму ", in: &s, layouts: layouts).isEmpty)
    #expect(try type("вуфирме ", in: &s, layouts: layouts).isEmpty)
}

@Test @MainActor func bracketKeyThatIsALetterElsewhereIsNotABracket() throws {
    // «[jhjij» — «хорошо» в английской раскладке: «[» в русской — буква «х», а не скобка
    var (s, layouts) = try session(.en)
    #expect(try type("[jh", in: &s, layouts: layouts) == [.replace(deleteCount: 2, text: "хор"), .switchLayout(.ru)])
}

@Test @MainActor func cyrillicSwitchIgnoresSentenceLanguage() throws {
    // проба владельца 2026-10-21: русская фраза про тарашкевицу — «тарашкевицу» остаётся русским и в русской фразе
    let (detector, layouts) = try makeDetector(ownerLayoutIDs)
    var s = TypingSession(detector: detector, layouts: layouts, current: .ru)
    #expect(try type("Добавить тарашкевицу ", in: &s, layouts: layouts).isEmpty)
    #expect(s.current == .ru)
    // русское слово в белорусском предложении — на лету, как в начале фразы: раскладку решает слово (B24,
    // принцип владельца 2026-11-06; до него белорусская фраза держала раскладку до пробела)
    var be = TypingSession(detector: detector, layouts: layouts, current: .be)
    _ = try type("прывітанне ", in: &be, layouts: layouts)
    var actions: [TypingSession.Action] = []
    for ch in "привет " {
        if ch == " " { actions += be.separator(" ") } else {
            actions += be.key(try #require(layouts[.ru]?.keystrokes(for: String(ch))?.first))
        }
    }
    #expect(actions == [.replace(deleteCount: 0, text: "и"), .switchLayout(.ru)])
}

@Test @MainActor func surnameDecidesLikeAloneAfterRussianText() throws {
    // проба владельца 2026-10-21: русская фраза, пауза, затем фамилия на «дасни» — она на лету уходила в
    // белорусскую, и до 2026-11-06 её держал язык прежнего текста. Принцип владельца 2026-11-06 (B24): раскладку решает
    // слово — фамилии нет в русском словаре, «дасні-» бывает только в белорусском, и она уходит, как в начале фразы.
    // Цена выбрана владельцем по замеру; держит «Мои слова» (исключение) и откат ⌥ (R6)
    let (detector, layouts) = try makeDetector(ownerLayoutIDs)
    var alone = TypingSession(detector: detector, layouts: layouts, current: .ru)
    let first = try type("дасницкому ", in: &alone, layouts: layouts)
    var s = TypingSession(detector: detector, layouts: layouts, current: .ru)
    #expect(try type("Доброе утро. По дасницкому ", in: &s, layouts: layouts) == first)
    #expect(s.current == alone.current)
    // своё слово (исключение) не трогается и на лету
    var own = TypingSession(detector: detector, layouts: layouts, current: .ru)
    own.exceptions = ["дасницкому"]
    #expect(try type("Доброе утро. По дасницкому ", in: &own, layouts: layouts).isEmpty)
    #expect(own.current == .ru)
}

@Test @MainActor func resetSaysWhetherItErasesAnything() throws {
    // B5: журнал пишет сброс, только когда тот что-то стёр, — иначе стрелки и клики шли бы строкой на нажатие
    var (s, layouts) = try session(.en)
    #expect(!s.hasState)
    _ = try type("hel", in: &s, layouts: layouts)
    #expect(s.hasState)
    s.reset()
    #expect(!s.hasState)
    _ = try type("hello ", in: &s, layouts: layouts)
    #expect(s.hasState)  // законченное слово ещё ждёт хоткея
}

@Test @MainActor func singleLetterWordBeforeCorrectedWordStays() throws {
    // проба владельца 2026-10-22: «был в wfirm», «это и API» — «цаш» на лету ушло в «wfi», «ФЗШ» — в «API», и
    // стоявшие перед ними «в» и «и» стали «d» и «b». Однобуквенное идёт за словом, только если в своей
    // раскладке оно не слово, а в новой — слово («z ghbdtn» → «я привет»)
    let (detector, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    func screen(_ input: String, from start: Language) throws -> String {
        var s = TypingSession(detector: detector, layouts: layouts, current: start)
        var text = ""
        func apply(_ actions: [TypingSession.Action]) {
            for case let .replace(deleteCount, add) in actions { text = String(text.dropLast(deleteCount)) + add }
        }
        for ch in input {
            if ch == " " { apply(s.separator(" ")); text += " "; continue }
            let key = try #require(layouts[start]?.keystrokes(for: String(ch))?.first)
            let before = s.current
            let actions = s.key(key)
            if actions.isEmpty { text += layouts[before]?.text(for: [key]) ?? "" } else { apply(actions) }
        }
        return text
    }
    #expect(try screen("я был в руддщ ", from: .ru) == "я был в hello ")
    #expect(try screen("это и ФЗШ ", from: .ru) == "это и API ")
    #expect(try screen("z ghbdtn ", from: .en) == "я привет ")
    #expect(try screen("1/ ghbdtn ", from: .en) == "1. привет ")
    // после английского слова раскладка английская, и «и» печатается «b»: русское «и» и белорусское «і» — ничья
    // между кириллицами, её решает язык текста (docs/spec.md: однобуквенные исправляются по пробелу)
    #expect(try screen("это ФЗШ и ", from: .ru) == "это API и ")
    #expect(try screen("гэта ФЗШ і ", from: .be) == "гэта API і ")
}

@Test @MainActor func wordTypedTwiceBecomesKnownForTypos() throws {
    // решение владельца 2026-10-22: «разбирвться» не исправлялось — «разбираться» нет в словаре его текстов.
    // Слово, дважды набранное без ошибки, становится знакомым, и не та буква исправляется в него
    let (detector, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    var s = TypingSession(detector: detector, layouts: layouts, current: .ru)
    s.correctTypos = true
    #expect(try type("разбирвться ", in: &s, layouts: layouts).isEmpty)
    #expect(try type("разбираться разбираться ", in: &s, layouts: layouts).isEmpty)
    #expect(try type("разбирвться ", in: &s, layouts: layouts) == [.replace(deleteCount: 5, text: "аться")])
}

@Test @MainActor func namesAndCitiesAreInDictionaries() throws {
    // решение владельца 2026-10-22: имена и города достаточно держать в словарях. «Илона» в русском
    // словаре не было, а белорусское «Ілон» склоняется — «илона» по пробелу уходило в «ілона»
    let (detector, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    for text in ["Илона ", "Илоны ", "илоне "] {
        var s = TypingSession(detector: detector, layouts: layouts, current: .ru)
        #expect(try type(text, in: &s, layouts: layouts).isEmpty, "\(text)")
        #expect(s.current == .ru, "\(text)")
    }
    #expect(detector.isWord("Ilona", in: .en))
    // тень чужого слова не добавляется: «Ши» сделало бы русским белорусское «ШІ», набранное в русской раскладке
    #expect(!detector.isWord("Ши", in: .ru))
}

@Test @MainActor func twoLettersAfterSignDoNotDecideOnTheFly() throws {
    // чат «Беларускі ШІ» 2026-10-21: «"Сл» — три нажатия, но две буквы; в английском «ck» — слово, и
    // «"Словы"» уходило в «@Ck», оттуда в русскую. «ШІ-» — две буквы и дефис. Апостроф — белорусская
    // буква: «ад'» — три буквы, как «адъ» в русской
    let (detector, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    for text in ["\"Словы\" ", "\"Слухай\" ", "ШІ-кантэнту ", "ад'ездіў "] {
        var s = TypingSession(detector: detector, layouts: layouts, current: .be)
        #expect(try type(text, in: &s, layouts: layouts).isEmpty, "\(text)")
        #expect(s.current == .be, "\(text)")
    }
}

@Test @MainActor func selectionCyclesThroughLayoutsAndBack() throws {
    // проба владельца 2026-10-21: выделенный текст хоткей не трогал. «ghbdtn vbh 🙂» набрано в
    // английской: первым — русский (больше слов), третье нажатие возвращает исходный текст, эмодзи как есть
    let (detector, layouts) = try makeDetector(ownerLayoutIDs)
    var s = TypingSession(detector: detector, layouts: layouts, current: .ru)
    let original = "ghbdtn vbh 🙂"
    var screen = ""  // выделение стирается первым напечатанным символом
    func apply(_ actions: [TypingSession.Action]) {
        for case let .replace(deleteCount, text) in actions { screen = String(screen.dropLast(deleteCount)) + text }
    }
    apply(s.cycleSelection(original))
    #expect(screen == "привет мир 🙂")
    #expect(s.current == .ru)
    apply(s.cycleWord())
    #expect(s.current == .be)
    apply(s.cycleWord())
    #expect(screen == original)
    #expect(s.current == .en)
    // выделение со строками не переводится: перевод строки в чате — «отправить»
    #expect(s.cycleSelection("ghbdtn\nvbh").isEmpty)
}

@Test @MainActor func typosAreFixedAndUndoneByHotkey() throws {
    // решения владельца В26–В31: исправляется только слово, первое ⌥ возвращает набранное; выключатель
    let (detector, layouts) = try makeDetector(ownerLayoutIDs)
    var s = TypingSession(detector: detector, layouts: layouts, current: .ru)
    // «это» — только русское: без него на «класн» раскладка ушла бы в белорусскую («класны»)
    #expect(try type("это класный ", in: &s, layouts: layouts).isEmpty)  // выключено по умолчанию
    s.correctTypos = true
    #expect(try type("это класный ", in: &s, layouts: layouts) == [.replace(deleteCount: 3, text: "сный")])
    #expect(s.cycleWord() == [.replace(deleteCount: 5, text: "ный ")])
    #expect(try type("невидел ", in: &s, layouts: layouts) == [.replace(deleteCount: 5, text: " видел")])
    var h = TypingSession(detector: detector, layouts: layouts, current: .ru)
    h.correctTypos = true
    #expect(try type("кто то ", in: &h, layouts: layouts) == [.replace(deleteCount: 3, text: "-то")])
    #expect(h.cycleWord() == [.replace(deleteCount: 4, text: " то ")])
}

@Test @MainActor func unknownRussianWordDoesNotSilentlySwitchToBelarusian() throws {
    // находка 2026-10-21: «класный» начинается как белорусское «класны» — на «класн» раскладка молча
    // уходила в белорусскую (тот же класс, что «тарашкевицу»); теперь кириллица так не переключается
    let (detector, layouts) = try makeDetector(ownerLayoutIDs)
    var s = TypingSession(detector: detector, layouts: layouts, current: .ru)
    #expect(try type("класный ", in: &s, layouts: layouts).isEmpty)
    #expect(s.current == .ru)
}

@Test @MainActor func ownReplacementsIgnoreLayoutButNotCase() throws {
    // docs/spec.md, решения владельца 2026-10-21: «что = на что» после пробела; «что» — слово или фраза,
    // раскладка не важна, регистр важен; «на что» — как записано
    let (detector, layouts) = try makeDetector(ownerLayoutIDs)
    func screen(_ input: String, from language: Language) throws -> (String, TypingSession) {
        var s = TypingSession(detector: detector, layouts: layouts, current: language)
        s.replacements = [Replacement(what: "мск", with: "Москва", ignoreCase: true), Replacement(what: "Прык скок", with: "Прыг Ског"),
                          Replacement(what: "Адский сатона", with: "АцКиЙ сОтОнА")]
        var text = ""
        for ch in input {
            let actions = ch == " " ? s.separator(" ") : s.key(try #require(layouts[language]?.keystrokes(for: String(ch))?.first))
            for case let .replace(n, t) in actions { text = String(text.dropLast(n)) + t }
            if actions.isEmpty || ch == " " { text.append(ch) }
        }
        return (text, s)
    }
    var (text, s) = try screen("мск ", from: .ru)
    #expect(text == "Москва ")
    for case let .replace(n, t) in s.cycleWord() { text = String(text.dropLast(n)) + t }
    #expect(text == "мск ")  // ⌥ — как набрано
    #expect(try screen("vcr ", from: .en).0 == "Москва ")  // раскладка — нет
    (text, s) = try screen("Прык скок ", from: .ru)
    #expect(text == "Прыг Ског ")
    for case let .replace(n, t) in s.cycleWord() { text = String(text.dropLast(n)) + t }
    #expect(text == "Прык скок ")  // ⌥ — вся фраза как набрана
    #expect(try screen("Адский сатона ", from: .ru).0 == "АцКиЙ сОтОнА ")
    #expect(try screen("адский сатона ", from: .ru).0 == "адский сатона ")  // регистр важен
    #expect(try screen("Мск ", from: .ru).0 == "Москва ")  // галочка у строки — в любом регистре
}

@Test @MainActor func rollbackOfAutoCorrectionIsReported() throws {
    // запоминание исправлений (docs/spec.md): ⌥, вернувший автоисправленное слово к набранному, — откат
    let (detector, layouts) = try makeDetector(ownerLayoutIDs)
    var s = TypingSession(detector: detector, layouts: layouts, current: .en)
    _ = try type("ghbdtn ", in: &s, layouts: layouts)  // на экране «привет »
    _ = s.cycleWord()
    #expect(s.lastRollback == "ghbdtn")
    _ = s.cycleWord()
    #expect(s.lastRollback == nil)  // дальше — круг раскладок, не откат
    var t = TypingSession(detector: detector, layouts: layouts, current: .ru)
    t.correctTypos = true
    _ = try type("это класный ", in: &t, layouts: layouts)
    _ = t.cycleWord()
    #expect(t.lastRollback == "класный")
}

@Test @MainActor func transliterationHotkeyAndUndo() throws {
    // docs/spec.md: последнее слово или выделение — латиницей, как в паспорте; ⌥ возвращает набранное
    let (detector, layouts) = try makeDetector(ownerLayoutIDs)
    var s = TypingSession(detector: detector, layouts: layouts, current: .ru)
    _ = try type("привет ", in: &s, layouts: layouts)
    #expect(s.transliterate(selection: nil) == [.replace(deleteCount: 7, text: "privet ")])
    #expect(s.cycleWord() == [.replace(deleteCount: 7, text: "привет ")])
    #expect(s.transliterate(selection: "Канстанцін Берсенеў") == [.replace(deleteCount: 0, text: "Kanstantsin Berseneu")])
}

@Test @MainActor func backspaceAfterSpaceReopensTheWord() throws {
    // проба владельца 2026-10-21: ⌫ после пробела сбрасывал сеанс, и ⌥ предыдущее слово уже не менял
    let (detector, layouts) = try makeDetector(ownerLayoutIDs)
    var s = TypingSession(detector: detector, layouts: layouts, current: .en)
    _ = try type("ghbdtn ", in: &s, layouts: layouts)  // на экране «привет »
    #expect(s.current == .ru)
    s.backspace()  // стёрт пробел — «привет» снова недописанное
    #expect(s.cycleWord() == [.replace(deleteCount: 6, text: "ghbdtn"), .switchLayout(.en)])
    // решение хоткея держится: пробел его не отменяет
    #expect(s.separator(" ").isEmpty)
}

@Test @MainActor func mixedSelectionIsFirstBroughtToOneLayout() throws {
    // проба владельца 2026-10-21: латинское слово среди русских становилось «saµe» — латиница
    // бралась с ⌥ «Русской – ПК». Теперь у слова своя раскладка, первое нажатие — вся фраза в одной
    // (русской: в ней больше слов), дальше круг; белорусская даёт тот же текст, что русская, — один раз
    let (detector, layouts) = try makeDetector(ownerLayoutIDs)
    var s = TypingSession(detector: detector, layouts: layouts, current: .ru)
    let original = "как save отработает"
    var screen = ""
    func apply(_ actions: [TypingSession.Action]) {
        for case let .replace(deleteCount, text) in actions { screen = String(screen.dropLast(deleteCount)) + text }
    }
    apply(s.cycleSelection(original))
    #expect(screen == "как ыфму отработает")
    apply(s.cycleWord())
    #expect(screen == "rfr save jnhf,jnftn")
    apply(s.cycleWord())
    #expect(screen == original)
}

@Test @MainActor func wholeWordBeatsSentenceContext() throws {
    // проба владельца 2026-10-21: белорусские слова в русской раскладке среди русских слов терялись —
    // «выпраўляе» и «перакласці» есть в белорусском словаре, «выпращляе» и «перакласци» нет в русском
    let (detector, layouts) = try makeDetector(ownerLayoutIDs)
    var s = TypingSession(detector: detector, layouts: layouts, current: .ru)
    #expect(try type("работает выпращляе ", in: &s, layouts: layouts)
        == [.replace(deleteCount: 0, text: "ў"), .switchLayout(.be)])  // на лету, как в начале фразы (B24)
    var t = TypingSession(detector: detector, layouts: layouts, current: .ru)
    // «перакладае» пишется так же и в русской — текст верен, раскладка уходит в белорусскую; «сможет» — обратно
    #expect(try type("А если перакладае то сможет ли перакласци ", in: &t, layouts: layouts)
        == [.switchLayout(.be), .switchLayout(.ru), .replace(deleteCount: 1, text: "і"), .switchLayout(.be)])
}

@Test @MainActor func sameTextWordOfOtherLanguageSwitchesLayout() throws {
    // проба владельца 2026-10-21: «прымай», «выдатна» в русской раскладке пишутся так же, текст верен, но
    // раскладка оставалась русской — дальше «і» печаталась «и» (docs/spec.md: слово только другого языка)
    let (detector, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    var s = TypingSession(detector: detector, layouts: layouts, current: .ru)
    #expect(try type("прымай ", in: &s, layouts: layouts) == [.switchLayout(.be)])
    // и в русском предложении: раскладку решает слово, а не прежние слова (B24, принцип владельца 2026-11-06)
    var t = TypingSession(detector: detector, layouts: layouts, current: .ru)
    _ = try type("отлично ", in: &t, layouts: layouts)
    #expect(try type("выдатна ", in: &t, layouts: layouts) == [.switchLayout(.be)])
    // «я» — и белорусское: в белорусской раскладке остаётся (замер на чате «Беларускі ШІ»: 583 раза уводило)
    var b = TypingSession(detector: detector, layouts: layouts, current: .be)
    #expect(try type("я ", in: &b, layouts: layouts).isEmpty)
}

@Test @MainActor func wholeSentenceStillConvertsWhenNothingIsExclusive() throws {
    // «мы и синия» в русской раскладке — белорусское предложение: «и» → «і» вместе с «сінія»
    var (s, layouts) = try session(.ru)
    #expect(try type("мы и синия ", in: &s, layouts: layouts) == [.replace(deleteCount: 6, text: "і сінія"), .switchLayout(.be)])
}

@Test @MainActor func userWordsAreKnown() throws {
    // ZUS нет в словарях: «ягы» в русской раскладке не исправлялось (проба владельца 2026-10-21)
    let (plain, layouts) = try makeDetector()
    let keys = try #require(layouts[.en]?.keystrokes(for: "zus"))
    #expect(plain.correction(for: keys, typedIn: .ru) == nil)
    var filters: [Language: WordFilter] = [:]
    for language in Language.allCases { filters[language] = WordFilter.bundled(language) }
    let withWords = LanguageDetector(layouts: layouts, filters: filters, userWords: ["ZUS", "дупу"])
    #expect(withWords.correction(for: keys, typedIn: .ru) == .en)
}

@Test @MainActor func learnsOnlyUnknownRealWords() throws {
    let (detector, _) = try makeDetector()
    let text = "кринжово тут кринжово. ghbdtn и ghbdtn. привет привет. разово. iban iban"
    // «кринжово» дважды и вне словарей — берём («косячок» не годится: он есть в украинском);
    // «ghbdtn» — набрано не в той раскладке; «привет» уже известно; «разово» встретилось один раз;
    // «iban» — латиница не учится (решение владельца 2026-10-21: из чатов — ссылки, ники, сокращения)
    #expect(detector.learnableWords(in: text) == ["кринжово"])
}

@Test @MainActor func lowercaseMatchesCapitalizedButNotAbbreviation() throws {
    // имена в чатах пишут строчными: «london» — «London»; «nj» — не «NJ»
    let (detector, _) = try makeDetector()
    #expect(detector.isWord("london", in: .en))
    #expect(!detector.isWord("nj", in: .en))
}

@Test @MainActor func stretchedVowelIsAnInterjection() throws {
    // «ffff» — растянутое «аааа» в английской раскладке (проба владельца 2026-10-21)
    var (s, layouts) = try session(.en)
    #expect(try type("ffff ", in: &s, layouts: layouts) == [.replace(deleteCount: 4, text: "аааа"), .switchLayout(.ru)])
    let (detector, _) = try makeDetector()
    #expect(detector.isWord("ooo", in: .en) && !detector.isWord("ммм", in: .ru))
}

@Test @MainActor func hotkeyDecisionIsFinalForTheWord() throws {
    // проба владельца 2026-10-21: «шифт» → «iban» на лету, хоткеем вернул, а пробел снова сделал «iban»
    var (s, layouts) = try session(.en)
    #expect(!(try type("ghb", in: &s, layouts: layouts)).isEmpty)      // на лету в «при»
    #expect(s.cycleWord() == [.replace(deleteCount: 3, text: "ghb"), .switchLayout(.en)])
    #expect(try type("dtn ", in: &s, layouts: layouts).isEmpty)        // ни на лету, ни пробелом
}

@Test @MainActor func abbreviationsWithDots() throws {
    // «т.е.» в английской раскладке — «n/t/» (проба владельца 2026-10-21)
    var (s, layouts) = try session(.en)
    #expect(try type("n/t/ ", in: &s, layouts: layouts) == [.replace(deleteCount: 4, text: "т.е."), .switchLayout(.ru)])
}

@Test @MainActor func statisticsCountLikePunto() throws {
    // docs/spec.md, критерии этапа 5: слова, автопереключения, ручные исправления, откаты (+ опечатки)
    let (detector, layouts) = try makeDetector(ownerLayoutIDs)
    var s = TypingSession(detector: detector, layouts: layouts, current: .en)
    _ = try type("hello ghbdtn ", in: &s, layouts: layouts)  // «привет» — на лету
    _ = s.cycleWord()  // откат к «ghbdtn»
    _ = s.cycleWord()  // дальше круг — не исправление и не откат
    var expected = TypingStats()
    expected.words = 2
    expected.autoSwitches = 1
    expected.rollbacks = 1
    #expect(s.takeStats() == expected)
    #expect(s.takeStats() == TypingStats())  // взятое обнуляется

    var m = TypingSession(detector: detector, layouts: layouts, current: .en)
    _ = try type("hello ", in: &m, layouts: layouts)
    _ = m.cycleWord()  // само не исправлялось — ручное исправление
    _ = m.cycleWord()
    m.backspace()  // ⌫ снова открыл слово — пробел посчитает его заново
    _ = m.separator(" ")
    _ = m.cycleSelection("ghbdtn")
    var manual = TypingStats()
    manual.words = 1
    manual.manualFixes = 2
    #expect(m.takeStats() == manual)

    var t = TypingSession(detector: detector, layouts: layouts, current: .ru)
    t.correctTypos = true
    _ = try type("это класный кто то ", in: &t, layouts: layouts)  // опечатка и дефис
    _ = t.cycleWord()  // дефис назад — откат
    var typos = TypingStats()
    typos.words = 4
    typos.typoFixes = 2
    typos.rollbacks = 1
    #expect(t.takeStats() == typos)
}

@Test @MainActor func belarusianPunctuationIsRussianPC() throws {
    // проба владельца 2026-10-21: ⌥ на «.» давал «/» и переключал в белорусскую — круг брал знак самой
    // раскладки Apple (на клавише «/» там «/»), а blalb печатает в белорусской знаки «Русской – ПК» («.»)
    let (detector, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    var s = TypingSession(detector: detector, layouts: layouts, current: .ru)
    _ = try type(".", in: &s, layouts: layouts)
    #expect(s.cycleWord() == [.replace(deleteCount: 1, text: "/"), .switchLayout(.en)])  // белорусская даёт ту же «.»
    // набранное в белорусской — теми же клавишами в английской: «.» — клавиша «/», а не ⇧7 («&»)
    var b = TypingSession(detector: detector, layouts: layouts, current: .be)
    _ = try type("дом.", in: &b, layouts: layouts)
    #expect(b.cycleWord() == [.replace(deleteCount: 4, text: "ljv/"), .switchLayout(.en)])
}

@Test @MainActor func wordWithDeadKeyIsCorrectedAndConverted() throws {
    // проба владельца 2026-10-21: «Это» в «США международной – ПК» — «"nj» не исправлялось ни само, ни ⌥ на выделении
    let (detector, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    let keys = [Keystroke(code: 39, shift: true), Keystroke(code: 45), Keystroke(code: 38)]
    var s = TypingSession(detector: detector, layouts: layouts, current: .en)
    var actions = keys.flatMap { s.key($0) }
    actions += s.separator(" ")
    #expect(actions == [.replace(deleteCount: 2, text: "Это"), .switchLayout(.ru)])  // на лету: на экране «"n»
    var t = TypingSession(detector: detector, layouts: layouts, current: .en)
    #expect(t.cycleSelection("\"nj") == [.replace(deleteCount: 0, text: "Это"), .switchLayout(.ru)])
}

@Test @MainActor func slashesInLatinAreAnEllipsis() throws {
    // проба владельца 2026-10-21: «///» в английской — «///» должно быть троеточием; раскладка не меняется
    let (detector, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    var s = TypingSession(detector: detector, layouts: layouts, current: .en)
    let slash = Keystroke(code: 44)
    for _ in 0..<3 { _ = s.key(slash) }
    #expect(s.separator(" ") == [.replace(deleteCount: 3, text: "...")])
    #expect(s.current == .en)
    #expect(s.cycleWord() == [.replace(deleteCount: 4, text: "/// ")])  // ⌥ — как набрано
}

@Test @MainActor func optionLayerVariantsAreSkipped() throws {
    // B4, журнал 2026-10-21: «ыфмуl» (l — на ⌥L «Русской – ПК») по ⌥ давало белорусское «ыфму∆»
    let (detector, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    let ru = try #require(layouts[.ru]), be = try #require(layouts[.be])
    let optionL = Keystroke(code: 37, option: true)
    #expect(ru.chars[optionL] == "l")
    #expect(be.chars[optionL] == "∆")
    let keys = try #require(ru.keystrokes(for: "ыфму")) + [optionL]
    #expect(!detector.options(for: keys, typedIn: .ru).contains { $0.language == .be })
}

@Test @MainActor func keypadSignBeforeWrongLayoutWordIsFixed() throws {
    // B15, неделя этапа 5: «/save» набирался в русской раскладке с «/» цифрового блока — 13 из 81 ручного
    // исправления. Цифрового блока в таблице раскладки не было: «/» сеанс не видел, слово «набрано нечисто»
    let (detector, layouts) = try makeDetector(ownerLayoutIDs, pcPunctuation: true)
    let slash = Keystroke(code: 75)
    #expect(layouts[.ru]?.text(for: [slash]) == "/")
    var s = TypingSession(detector: detector, layouts: layouts, current: .ru)
    var actions = s.key(slash)
    for ch in "ыфму" { actions += s.key(try #require(layouts[.ru]?.keystrokes(for: String(ch))?.first)) }
    actions += s.separator(" ")
    #expect(actions == [.replace(deleteCount: 2, text: "sav"), .switchLayout(.en)])
    #expect(s.current == .en)
    // цифровой блок только читается: свои замены и выученные слова набираются основным
    #expect(layouts[.en]?.keystrokes(for: "/") == [Keystroke(code: 44)])
    #expect(layouts[.en]?.keystrokes(for: "+1") == [Keystroke(code: 24, shift: true), Keystroke(code: 18)])
}

@Test @MainActor func typedOpenersSurviveAutoClosingEditors() throws {
    // B19, проба владельца 2026-11-04 в Notepad++ (autoCloseBrackets): выделение « save я хотел open зразумеў », ⌥ ×10.
    // Круг шёл через английский («хотел» → «[jntk»), редактор на каждую «[» ставил «]» за курсор, и «]» копились
    let (detector, layouts) = try makeDetector(ownerLayoutIDs)
    let pairs: [Character: Character] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'", "`": "`"]
    let original = " save я хотел open зразумеў "
    for autoClose in [false, true] {
        var s = TypingSession(detector: detector, layouts: layouts, current: .be)
        var before = "", after = ""  // текст до и после курсора; выделение стирается первым напечатанным знаком
        func apply(_ actions: [TypingSession.Action]) {
            for case let .replace(deleteCount, text) in actions {
                for press in TypingSession.keypresses(deleting: deleteCount, typing: text) {
                    guard case .text(let typed) = press else { before.removeLast(); continue }
                    for ch in typed {
                        // автозакрытие: вставленная редактором закрывающая перепечатывается, на открывающую — своя закрывающая
                        if autoClose, after.first == ch, pairs.values.contains(ch) { after.removeFirst(); before.append(ch); continue }
                        before.append(ch)
                        if autoClose, let closer = pairs[ch] { after.insert(closer, at: after.startIndex) }
                    }
                }
            }
        }
        apply(s.cycleSelection(original))
        var english = false, back = 0
        for _ in 0..<9 {
            apply(s.cycleWord())
            if s.lastDecision?.contains("[en]") == true { english = true; #expect((before + after).contains("[jntk")) }
            if s.lastDecision?.contains("как было") == true { back += 1; #expect(before + after == original, "автозакрытие: \(autoClose)") }
        }
        #expect(english && back >= 2, "круг дважды прошёл через английский и вернулся")
    }
}

@Test @MainActor func editErasesSuggestionSelectedAfterCaret() throws {
    // B40, проба владельца 2026-11-07 в Spotlight: `ghbdtn` → «gпривет». Spotlight помнил запрос «ghbdtn» и за набранным
    // держал выделенную подсказку — первый Backspace правки стирал её, а не букву. После стирания подсказка не возвращается
    func spotlight(_ suggestionAware: Bool) throws -> String {
        var (s, layouts) = try session(.en)
        var before = "", selected = ""  // текст до курсора и выделенная подсказка за ним
        func suggest() { selected = "ghbdtn".hasPrefix(before) ? String("ghbdtn".dropFirst(before.count)) : "" }
        for ch in "ghbdtn" {
            let key = try #require(layouts[.en]?.keystrokes(for: String(ch))?.first)
            let shown = layouts[s.current]?.text(for: [key]) ?? ""
            let actions = s.key(key)
            guard !actions.isEmpty else { selected = ""; before += shown; suggest(); continue }
            for case let .replace(deleteCount, text) in actions {
                let presses = TypingSession.keypresses(deleting: deleteCount, typing: text,
                                                       suggestionAfterCaret: suggestionAware && !selected.isEmpty)
                for press in presses {
                    switch press {
                    case .forwardDelete: selected = ""
                    case .backspace: if selected.isEmpty { before.removeLast() } else { selected = "" }
                    case .text(let typed): selected = ""; before += typed
                    }
                }
            }
        }
        return before + selected
    }
    #expect(try spotlight(false) == "gпривет", "без поправки — как у владельца")
    #expect(try spotlight(true) == "привет")
    // правка выделенного (ничего не стирается) печатается поверх выделения — лишнего Backspace нет
    #expect(TypingSession.keypresses(deleting: 0, typing: "x", suggestionAfterCaret: true) == [.text("x")])
}

@Test func suggestionGoneBeforeEditLosesNoCharacter() {
    // B43, R16: поле ответило «за курсором подсказка», а она исчезла до первого нажатия правки (приложение сменило её само
    // или ещё не обработало прежнее нажатие). Лишний Backspace стёр бы знак перед словом; ⌦ без выделения в конце поля
    // не стирает ничего (поле AppKit, опыт 2026-11-07: «погода ghbd» + ⌦ — без изменений, + ⌫ — «погода ghb»)
    func edit(_ presses: [TypingSession.Keypress], suggestionGone: Bool) -> String {
        var before = "погода ghbd", selected = suggestionGone ? "" : "tn"
        for press in presses {
            switch press {
            case .forwardDelete: selected = ""
            case .backspace: if selected.isEmpty { before.removeLast() } else { selected = "" }
            case .text(let typed): selected = ""; before += typed
            }
        }
        return before + selected
    }
    let presses = TypingSession.keypresses(deleting: 4, typing: "прив", suggestionAfterCaret: true)
    #expect(presses.first == .forwardDelete)
    #expect(edit(presses, suggestionGone: false) == "погода прив")
    #expect(edit(presses, suggestionGone: true) == "погода прив")
    // поправка B40 стирала подсказку Backspace'ом: исчезни подсказка — терялся пробел
    let backspaceFirst = Array(repeating: TypingSession.Keypress.backspace, count: 5) + [.text("прив")]
    #expect(edit(backspaceFirst, suggestionGone: true) == "погодаприв")
}

@Test @MainActor func fixHotkeyLeavesSuggestionSelectedAfterCaret() throws {
    // B42, R17: автопереключение выключено, в Spotlight набрано «ghbd», за ним выделенная подсказка «tn» (Spotlight помнит
    // «ghbdtn»). ⌥ читал выделение поля и правил подсказку — «ghbdет»; теперь правит набранное, подсказку стирает первой
    func spotlightFix(_ suggestionAware: Bool) throws -> String {
        var (s, layouts) = try session(.en)
        s.autoCorrect = false
        var before = "", selected = ""
        for ch in "ghbd" {
            let key = try #require(layouts[.en]?.keystrokes(for: String(ch))?.first)
            #expect(s.key(key).isEmpty)
            before += layouts[.en]?.text(for: [key]) ?? ""
        }
        selected = "tn"
        let target = s.selectionToEdit(selected, suggestionAfterCaret: suggestionAware)
        let actions = target.map { s.cycleSelection($0) } ?? s.cycleWord()
        for case let .replace(deleteCount, text) in actions {
            for press in TypingSession.keypresses(deleting: deleteCount, typing: text, suggestionAfterCaret: !selected.isEmpty) {
                switch press {
                case .forwardDelete: selected = ""
                case .backspace: if selected.isEmpty { before.removeLast() } else { selected = "" }
                case .text(let typed): selected = ""; before += typed
                }
            }
        }
        return before + selected
    }
    #expect(try spotlightFix(false) == "ghbdет", "без поправки ⌥ правит подсказку")
    #expect(try spotlightFix(true) == "прив")
    // выделение без набранного слова — выделение пользователя, даже если это хвост поля
    let (fresh, _) = try session(.en)
    #expect(fresh.selectionToEdit("tn", suggestionAfterCaret: true) == "tn")
}

@Test @MainActor func layoutFollowsWordNotSentence() throws {
    // принцип владельца 2026-11-06 (B24): часть предложения можно набирать в любой раскладке, это общее правило:
    // одно и то же слово в одной раскладке решается одинаково в начале фразы и после слов другого языка.
    // Русские слова вне словаря («запасик», «андроид») уходят в белорусскую — цена, выбранная владельцем по замеру
    let (detector, layouts) = try makeDetector(ownerLayoutIDs)
    func screen(_ input: String) throws -> (String, Language) {
        var s = TypingSession(detector: detector, layouts: layouts, current: .ru)
        var text = ""
        func apply(_ actions: [TypingSession.Action]) {
            for case let .replace(deleteCount, add) in actions { text = String(text.dropLast(deleteCount)) + add }
        }
        for ch in input {
            if ch == " " { apply(s.separator(" ")); text += " "; continue }
            let key = try #require(layouts[.ru]?.keystrokes(for: String(ch))?.first)
            let before = s.current
            let actions = s.key(key)
            if actions.isEmpty { text += layouts[before]?.text(for: [key]) ?? "" } else { apply(actions) }
        }
        return (text, s.current)
    }
    for word in ["прывитанне", "нацисни", "тольки", "выдатна", "запасик", "андроид", "привет", "класный"] {
        let alone = try screen(word + " ")
        for context in ["привет ", "если взять ", "мама "] {
            let after = try screen(context + word + " ")
            #expect(after.0.hasSuffix(alone.0) && after.1 == alone.1, "«\(context)\(word)»: \(after) — одно слово: \(alone)")
        }
    }
    #expect(try screen("привет прывитанне ") == ("привет прывітанне ", .be))
    #expect(try screen("привет ") == ("привет ", .ru))
}

@Test @MainActor func belarusianWordAfterRussianSwitchesWhenStemIsNotRussian() throws {
    // жалобы владельца 2026-11-06 (B22): «привет прывитанне», «если взять save то нацисни литару» — белорусские слова в
    // русской раскладке после русских остались русскими: окончания «-нне», «-сни», «-ару» в русском бывают. Основа —
    // нет: «прыв-», «нацисн-», «литар-»
    let (detector, layouts) = try makeDetector(ownerLayoutIDs)
    var s = TypingSession(detector: detector, layouts: layouts, current: .ru)
    #expect(try type("привет прывитанне ", in: &s, layouts: layouts).last == .switchLayout(.be), "\(s.lastDecision ?? "")")
    #expect(s.current == .be)
    s = TypingSession(detector: detector, layouts: layouts, current: .ru)
    #expect(try type("если взять нацисни ", in: &s, layouts: layouts).last == .switchLayout(.be), "\(s.lastDecision ?? "")")
    #expect(try type("літару ", in: &s, layouts: layouts).isEmpty)
    #expect(s.current == .be)
}

@Test @MainActor func belarusianFixtureSwitchesAfterRussianWord() throws {
    // R11 (B23): запрет на решении по пробелу приняли по одной стороне — что он останавливает; что он не пропускал
    // (половину белорусских слов после русского), видно не было. Тест обеих сторон на тестовом наборе: белорусское
    // слово, набранное в русской раскладке, после русского слова решается так же, как в начале фразы (B24)
    let (detector, layouts) = try makeDetector(ownerLayoutIDs)
    let ru = try #require(layouts[.ru]), be = try #require(layouts[.be])
    let url = try #require(Bundle.module.url(forResource: "be", withExtension: "txt", subdirectory: "Fixtures"))
    let words = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
    func switches(_ keys: [Keystroke], after context: String) -> Bool {
        var s = TypingSession(detector: detector, layouts: layouts, current: .ru)
        for key in ru.keystrokes(for: context) ?? [] { _ = s.key(key) }
        if !context.isEmpty { _ = s.separator(" ") }
        var actions: [TypingSession.Action] = []
        for key in keys { actions += s.key(key) }
        actions += s.separator(" ")
        return actions.contains(.switchLayout(.be))
    }
    var moved = 0, alone = 0, afterRussian = 0, differ: [String] = []
    for word in words {
        guard let keys = be.keystrokes(for: word), detector.correction(for: keys, typedIn: .ru) == .be else { continue }
        moved += 1
        let a = switches(keys, after: ""), b = switches(keys, after: "привет")
        if a { alone += 1 }
        if b { afterRussian += 1 }
        if a != b, differ.count < 5 { differ.append(word) }
    }
    print("тестовый набор be в русской раскладке: детектор переводит \(moved), уходит в начале фразы \(alone), после русского \(afterRussian)")
    #expect(moved > 100)
    #expect(alone == afterRussian && differ.isEmpty, "по-разному: \(differ)")
    #expect(Double(afterRussian) >= 0.95 * Double(moved))
}

@Test @MainActor func letterTurningIntoSymbolIsNotAWord() throws {
    // жалоба владельца 2026-11-06 (B26, R13): слово не содержит спецсимволов. На клавишах «х ъ б ю ж ё» русской
    // в английской — знаки; буква набранного, ставшая знаком, срезалась как край слова: «,sret» — «sret», начало
    // английского. Журнал с 2026-10-23: 12 таких решений, все ложные
    let (detector, layouts) = try makeDetector(ownerLayoutIDs)
    for word in ["быкуе ", "ютуб ", "Вглубю "] {  // каждое падало до починки B26 (e24e181)
        var s = TypingSession(detector: detector, layouts: layouts, current: .ru)
        #expect(try type(word, in: &s, layouts: layouts).isEmpty, "\(word) \(s.lastDecision ?? "")")
        #expect(s.current == .ru)
    }
    // знак, набранный знаком, апостроф и запятая последним нажатием — как прежде
    let ru = try #require(layouts[.ru]), en = try #require(layouts[.en])
    #expect(detector.correction(for: try #require(ru.keystrokes(for: "руддщб")), typedIn: .ru) == .en)  // «hello,»
    #expect(detector.correction(for: try #require(en.keystrokes(for: "k.,jq")), typedIn: .en) == .ru)   // «любой»
    #expect(detector.correction(for: try #require(ru.keystrokes(for: "вщтэе")), typedIn: .ru) == .en)   // «don't»
}

@Test @MainActor func erasingCorrectionAndRetypingCountsAsRollback() throws {
    // владелец 2026-11-06 (B27): «некада» много раз исправлялось на «некуда», программа не
    // училась — он стирал исправленное и набирал снова, без ⌥. Решение владельца: стёр исправленное и набрал те же
    // клавиши — отказ, как ⌥: слово остаётся как набрано, третий такой — в «Мои слова»
    var (detector, layouts) = try makeDetector(ownerLayoutIDs)
    detector.vocabulary = ["некуда"]
    var s = TypingSession(detector: detector, layouts: layouts, current: .ru)
    s.correctTypos = true
    func erase(_ count: Int) { for _ in 0..<count { s.backspace() } }
    #expect(try !type("некада ", in: &s, layouts: layouts).isEmpty)  // «некуда»: опечатка
    _ = s.takeStats()
    erase(7)                                                           // пробел и шесть букв
    #expect(try type("некада ", in: &s, layouts: layouts).isEmpty, "\(s.lastDecision ?? "")")
    #expect(s.lastRollback == "некада")
    #expect(s.takeStats().rollbacks == 1)
    // поправил исправленное обратно в набранное: «некуда» — стёр «уда», набрал «ада»
    #expect(try !type("некада ", in: &s, layouts: layouts).isEmpty)
    erase(4)
    #expect(try type("ада ", in: &s, layouts: layouts).isEmpty, "\(s.lastDecision ?? "")")
    #expect(s.lastRollback == "некада")
    // стёр и набрал другое — не отказ
    #expect(try !type("некада ", in: &s, layouts: layouts).isEmpty)
    erase(7)
    _ = try type("никогда ", in: &s, layouts: layouts)
    #expect(s.lastRollback == nil)
    // набрал то же, не стирая, — исправляется, как прежде
    #expect(try !type("некада ", in: &s, layouts: layouts).isEmpty)
    #expect(s.lastRollback == nil)
}

@Test @MainActor func apostropheOnRussianYoKeyIsALetter() throws {
    // «вс’» (2026-11-05): в «Белорусской» на клавише русской «ё» — «’»; край слова срезался как знак, проверялось «вс».
    // В русских словах апострофа не бывает (владелец)
    let (detector, layouts) = try makeDetector(ownerLayoutIDs)
    #expect(!detector.isWord("вс’", in: .be))
    // после белорусского слова — на лету, третьей клавишей: раскладку решает слово (B24)
    var s = TypingSession(detector: detector, layouts: layouts, current: .be)
    _ = try type("літару ", in: &s, layouts: layouts)
    let actions = try type("вс’ ", in: &s, layouts: layouts)
    #expect(actions == [.replace(deleteCount: 0, text: "ё"), .switchLayout(.ru)], "\(actions) \(s.lastDecision ?? "")")
}

/// Замер перехода из русской фразы в белорусскую (B22) — только по запросу: BLALB_SWITCH_CORPUS — файл «число\tслово»,
/// BLALB_SWITCH_LANG — в какой раскладке слово набирается правильно (ru или be), BLALB_USER_WORDS — «Мои слова» и
/// выученные, BLALB_SWITCH_OUT — куда записать признаки. Слово набирается в русской раскладке после «привет»
/// (с BLALB_SWITCH_EMPTY — в начале фразы).
@Test(.enabled(if: ProcessInfo.processInfo.environment["BLALB_SWITCH_CORPUS"] != nil)) @MainActor
func switchReplay() throws {
    let env = ProcessInfo.processInfo.environment
    let language = Language(rawValue: env["BLALB_SWITCH_LANG"] ?? "be") ?? .be
    let userWords = try env["BLALB_USER_WORDS"].map { try String(contentsOfFile: $0, encoding: .utf8).split(separator: "\n").map(String.init) } ?? []
    let (d, layouts) = try makeDetector(ownerLayoutIDs, userWords: userWords)
    let ru = try #require(layouts[.ru]), be = try #require(layouts[.be])
    let hello = try #require(ru.keystrokes(for: "привет"))
    var out = ""
    for line in try String(contentsOfFile: try #require(env["BLALB_SWITCH_CORPUS"]), encoding: .utf8).split(separator: "\n") {
        let parts = line.split(separator: "\t")
        guard parts.count == 2, let keys = layouts[language]?.keystrokes(for: String(parts[1])) else { continue }
        var s = TypingSession(detector: d, layouts: layouts, current: .ru)
        // BLALB_SWITCH_EMPTY — слово в начале фразы, без «привет»
        if env["BLALB_SWITCH_EMPTY"] == nil { for key in hello { _ = s.key(key) }; _ = s.separator(" ") }
        var actions: [TypingSession.Action] = []
        for key in keys { actions += s.key(key) }
        actions += s.separator(" ")
        let switched = actions.contains(.switchLayout(.be))
        let ruText = ru.text(for: keys), beText = be.text(for: keys)
        // где русское прочтение перестаёт быть началом русского слова
        let breakAt = (3...max(3, min(ruText.count, 8))).first { !d.isPrefix(String(ruText.prefix($0)), in: .ru) }.map { $0 - 1 } ?? -1
        let correction = d.correction(for: keys, typedIn: .ru)?.rawValue ?? "-"
        out += "\(parts[0])\t\(ruText)\t\(beText)\t\(switched)\t\(correction)\t\(d.endingPossible(ruText, in: .ru))\t\(breakAt)\n"
    }
    try out.write(toFile: try #require(env["BLALB_SWITCH_OUT"]), atomically: true, encoding: .utf8)
}


