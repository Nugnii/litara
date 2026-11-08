import Foundation

/// Сеанс набора: копит нажатия и на границе слова решает, что стереть и что напечатать заново.
///
/// Правила из docs/spec.md:
/// - латиница ↔ кириллица — исправляется слово (и стоящие прямо перед ним однобуквенные: «z ghbdtn» → «я привет»);
/// - кириллица ↔ кириллица — исправляется всё текущее предложение;
/// - текст в кавычках и скобках — отдельное предложение; после закрывающей набор продолжается
///   в раскладке, которая была до открывающей.
///
/// Буфер обмена не используется: экран меняется только действиями `replace`.
/// Своя замена (docs/spec.md, решения владельца 2026-10-21): «что» — слово или фраза → «на что» как записано.
public struct Replacement: Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var what: String
    public var with: String
    /// Срабатывать в любом регистре «что» — галочка у строки; без неё регистр важен.
    public var ignoreCase: Bool

    public init(what: String, with: String, ignoreCase: Bool = false) {
        self.what = what
        self.with = with
        self.ignoreCase = ignoreCase
    }
}

public struct TypingSession {
    public enum Action: Equatable, Sendable {
        /// Стереть столько символов перед курсором и напечатать текст. Сам разделитель (пробел,
        /// Enter) ещё не напечатан — он идёт после действий.
        case replace(deleteCount: Int, text: String)
        case switchLayout(Language)
    }

    private struct Token {
        var keys: [Keystroke]
        var language: Language
        var separator: String
        /// Раскладка, в которой слово набрано на самом деле: к ней возвращает круг хоткея.
        var typedIn: Language
        /// Из закрытых кавычек или скобок: отдельное предложение — стирается и печатается как было.
        var frozen = false
        /// Решено хоткеем — само не исправляется, и после ⌫ тоже.
        var decided = false
        /// Исправлена опечатка: нажатия, как было набрано, — первое ⌥ возвращает их.
        var typo: [Keystroke]?
        /// Пробел перед словом стал дефисом («кто-то») — первое ⌥ возвращает пробел.
        var hyphen = false
        /// Своя замена: на экране этот текст вместо набранного — первое ⌥ возвращает набранное.
        var replaced: String?
    }

    public private(set) var current: Language
    /// Последнее решение строкой — для журнала отладки (настройка «Записывать решения»).
    public private(set) var lastDecision: String?
    /// Последний ⌥ вернул автоисправленное слово к набранному — набранное (строчными). Три таких
    /// отката одного слова — повод предложить «не исправлять» (docs/spec.md, запоминание исправлений).
    public private(set) var lastRollback: String?
    /// Исправленная опечатка, снова открытая ⌫, и она же, стёртая целиком, — нажатия, как было набрано. Тот же набор
    /// снова — отказ, как ⌥ (решение владельца 2026-11-06, B27: «некада» семь раз становилось «некуда»).
    /// ponytail: только опечатки; после смены раскладки те же клавиши дают другой текст — там отказ по ⌥
    private var reopenedTypo: [Keystroke]?
    private var erasedTypo: [Keystroke]?
    /// Статистика с прошлого `takeStats()`.
    public private(set) var stats = TypingStats()
    /// Автоопределение (настройка): выключено — слова не исправляются, предложение по-прежнему ведётся.
    public var autoCorrect = true
    /// «Исправлять опечатки» (настройка, docs/spec.md): ru и be, только однозначные случаи.
    public var correctTypos = false
    /// Исключения (настройка): слова, которые не исправляются никогда — ZUS, GPT, /save.
    /// Сравнение без регистра; пока слово может стать исключением, на лету оно не трогается.
    public var exceptions: Set<String> = [] {
        didSet { exceptions = Set(exceptions.map { $0.lowercased() }) }
    }
    /// Свои замены (настройка, docs/spec.md, решения владельца 2026-10-21): «что = на что» после пробела.
    /// «что» — слово или фраза («Прык скок = Прыг Ског»); раскладка не важна («мск» и «vcr» — одни и те же
    /// клавиши), регистр важен; «на что» вставляется как записано («АцКиЙ сОтОнА»).
    public var replacements: [Replacement] = [] {
        didSet {
            replacementIndex = [:]
            caseFreeIndex = [:]
            for rule in replacements where !rule.with.isEmpty {
                let words = rule.what.split(separator: " ").map(String.init)
                for layout in layouts.values {
                    let keys = words.compactMap { layout.keystrokes(for: $0) }
                    guard !words.isEmpty, keys.count == words.count else { continue }
                    if rule.ignoreCase { caseFreeIndex[keys.map { $0.map(Self.unshifted) }] = rule.with } else { replacementIndex[keys] = rule.with }
                }
            }
            longestReplacement = (Array(replacementIndex.keys) + Array(caseFreeIndex.keys)).map(\.count).max() ?? 0
        }
    }
    /// Нажатия слов «что» → «на что»: с учётом регистра и (галочка у строки) без — нажатия без Shift.
    private var replacementIndex: [[[Keystroke]]: String] = [:]
    private var caseFreeIndex: [[[Keystroke]]: String] = [:]
    private var longestReplacement = 0
    private static func unshifted(_ key: Keystroke) -> Keystroke { Keystroke(code: key.code, option: key.option) }
    private var detector: LanguageDetector
    /// Словарные слова, набранные без исправлений один раз: на втором наборе слово становится знакомым.
    /// ponytail: в памяти — перезапуск забывает единичные наборы; понадобится — хранить с ограничением.
    private var typedOnce: Set<String> = []
    /// Слова, ставшие знакомыми с прошлого `takeLearned()` — их сохраняет приложение.
    private var learned: [String] = []
    private let layouts: [Language: KeyboardLayout]
    private var keys: [Keystroke] = []
    /// Раскладка, в которой начато текущее слово.
    private var wordTypedIn: Language?
    /// Последнее законченное слово — его берут хоткеи, пока новое не начато.
    private var last: Token?
    /// Круг хоткея: порядок языков и где мы в нём; любое нажатие круг сбрасывает.
    private var cycle: (languages: [Language], index: Int)?
    /// Текущее слово решено хоткеем — само больше не исправляется (проба владельца 2026-10-21).
    private var wordDecided = false
    private var sentence: [Token] = []
    /// Язык последнего слова, которое бывает только в одной кириллице. Переживает конец предложения и
    /// сброс (клик, ⌘-сочетание): курсор потерян, а язык текста — нет. Решает только ничьи из латиницы
    /// (`textLanguage`, R4); переход между кириллицами он не держит — раскладку решает слово (B24). Ручная
    /// смена раскладки его стирает.
    private var sureLanguage: Language?
    /// Выделенный текст в круге хоткея: слово — нажатиями и своей раскладкой, пробелы и то, чего не
    /// набрать (эмодзи), — как есть. В круге `nil` — текст как был выделен. Любое нажатие круг сбрасывает.
    private enum Piece { case keys([Keystroke], Language), raw(String) }
    private var selection: (pieces: [Piece], cycle: [Language?], index: Int)?
    /// Внешние предложения и раскладка до открывающей кавычки или скобки.
    private var outer: [(sentence: [Token], language: Language)] = []

    private static let openers: Set<Character> = ["(", "[", "{", "«", "„", "\u{201C}"]
    private static let closers: Set<Character> = [")", "]", "}", "»", "\u{201C}", "\u{201D}"]
    private static let sentenceEnds: Set<Character> = [".", "!", "?", "…"]

    public init(detector: LanguageDetector, layouts: [Language: KeyboardLayout], current: Language) {
        self.detector = detector
        self.layouts = layouts
        self.current = current
    }

    /// Статистика с прошлого вызова; счёт начинается заново.
    /// Выученные на наборе слова с прошлого вызова (строчными); список начинается заново.
    public mutating func takeLearned() -> [String] {
        defer { learned = [] }
        return learned
    }

    public mutating func takeStats() -> TypingStats {
        defer { stats = TypingStats() }
        return stats
    }

    /// Нажатие внутри слова. Возвращает действия исправления на лету; тогда само нажатие на экран
    /// не попадает — его текст уже в `replace`.
    public mutating func key(_ keystroke: Keystroke) -> [Action] {
        if keys.isEmpty { wordTypedIn = current; wordDecided = false }
        cycle = nil
        selection = nil
        keys.append(keystroke)
        // последнее нажатие ещё не на экране — оно может быть мёртвой клавишей текущей раскладки
        guard autoCorrect, !wordDecided, layouts[current]?.renders(Array(keys.dropLast())) == true,
              let typed = layouts[current]?.text(for: keys), let first = typed.first,
              !exceptions.contains(where: { $0.hasPrefix(typed.lowercased()) }),
              let found = detector.earlyCorrection(for: keys, typedIn: current), case let target = textLanguage(over: found, keys: keys, whole: false),
              // слово со скобкой впереди — отдельное предложение, его решает пробел; но «[» английской —
              // буква «х» русской: скобка — только если остаётся скобкой и после перевода
              !(Self.openers.contains(first) && layouts[target]?.text(for: keys).first == first)
        else { return [] }
        let onScreen = layouts[current]?.text(for: Array(keys.dropLast())) ?? ""
        let tail = layouts[target]?.text(for: keys) ?? ""
        lastDecision = "на лету: «\(typed)» [\(current.rawValue)] → «\(tail)» [\(target.rawValue)]"
        stats.autoSwitches += 1
        return retype(target: target, typed: onScreen, tail: tail)
    }

    public mutating func backspace() {
        cycle = nil
        selection = nil
        guard keys.isEmpty else {
            keys.removeLast()
            if keys.isEmpty, let typed = reopenedTypo { erasedTypo = typed; reopenedTypo = nil }
            return
        }
        // стёрт разделитель после слова — слово снова недописанное: его берут хоткей и пробел (проба
        // владельца 2026-10-21: после ⌫ хоткей предыдущее слово не менял).
        // ponytail: стирание дальше начала этого слова не отслеживается — сеанс начинается заново
        guard let token = last, token.language == current, !token.frozen else { reset(); return }
        if let i = sentence.indices.last, sentence[i].keys == token.keys { sentence.removeLast() }
        if text(of: token).contains(where: \.isLetter) { stats.words -= 1 }  // пробел посчитает его снова
        keys = token.keys
        wordTypedIn = token.typedIn
        wordDecided = token.decided
        reopenedTypo = token.decided ? nil : token.typo
        last = nil
    }

    /// Клик мышью, стрелки, сочетания с ⌘, смена приложения: где курсор — уже неизвестно.
    public mutating func reset() {
        reopenedTypo = nil
        erasedTypo = nil
        keys = []
        sentence = []
        outer = []
        last = nil
        cycle = nil
        selection = nil
    }

    /// Сбросу есть что стирать: начатое слово, слово для хоткея, предложение, круг или выделение.
    public var hasState: Bool {
        !keys.isEmpty || last != nil || !sentence.isEmpty || !outer.isEmpty || cycle != nil || selection != nil
    }

    /// Пользователь сам переключил раскладку.
    public mutating func layoutChanged(to language: Language) {
        current = language
        sureLanguage = nil
        reset()
    }

    /// Граница слова: пробел, Enter или Tab. Возвращает действия, которые надо выполнить до того,
    /// как разделитель попадёт на экран.
    public mutating func separator(_ separator: String) -> [Action] {
        defer { if separator == "\n" { endSentence() } }
        cycle = nil
        selection = nil
        // пробел без слова (после ⌥, второй подряд) решения не принимает — журнал не повторяет прошлое
        lastDecision = nil
        guard !keys.isEmpty else { return [] }
        var token = Token(keys: keys, language: current, separator: separator, typedIn: wordTypedIn ?? current)
        // стёр исправленную опечатку и набрал то же (или поправил её обратно в набранное) — отказ, как ⌥: остаётся как
        // набрано, третий — в «Мои слова» (B27)
        let refused = !wordDecided && (erasedTypo == keys || reopenedTypo == keys)
        if refused { wordDecided = true }
        reopenedTypo = nil
        erasedTypo = nil
        lastRollback = nil
        token.decided = wordDecided
        keys = []
        var actions: [Action] = []

        // мёртвая клавиша (апостроф в «США международная – ПК») печатает не то, что видно по нажатиям:
        // сколько стирать — неизвестно, такое слово не трогаем
        let typedCleanly = layouts[current]?.renders(token.keys) == true
        let typedText = layouts[current]?.text(for: token.keys) ?? ""
        let isException = exceptions.contains(typedText.lowercased())
            || exceptions.contains(LanguageDetector.core(typedText).lowercased())
        defer { wordDecided = false }
        // целое слово есть в словаре одного языка и нет в другом — это сильнее предложения («работает home
        // выпращляе» → «выпраўляе», проба владельца 2026-10-21); исключение — белорусское из русского (ниже)
        // своя замена важнее исправлений: это правило пользователя (и при выключенном автоопределении)
        // своя замена — слово или фраза: последние слова предложения через пробел вместе с этим; длинная важнее
        var replacement: String?, phraseWords = 0
        if !wordDecided {
            for n in stride(from: min(longestReplacement - 1, sentence.count), through: 0, by: -1) {
                let before = sentence.suffix(n)
                guard before.allSatisfy({ $0.separator == " " && !$0.frozen && $0.replaced == nil }) else { continue }
                let typed = before.map { $0.typo ?? $0.keys } + [token.keys]
                if let text = replacementIndex[typed] ?? caseFreeIndex[typed.map { $0.map(Self.unshifted) }] {
                    replacement = text
                    phraseWords = n
                    break
                }
            }
        }
        // «///» в латинице — «...», набранное не в той раскладке (проба владельца 2026-10-21: «///» должно быть
        // троеточием); знаки о языке не говорят — раскладка не меняется, ⌥ возвращает набранное
        var ellipsis = false
        if replacement == nil, autoCorrect, !wordDecided, !current.isCyrillic, typedText.count >= 3,
           typedText.allSatisfy({ $0 == "/" }),
           layouts.contains(where: { $0.key.isCyrillic && $0.value.text(for: token.keys) == String(repeating: ".", count: typedText.count) }) {
            replacement = String(repeating: ".", count: typedText.count)
            ellipsis = true
        }
        // фраза: её начало уже на экране — стирается вместе со словом; ⌥ вернёт всю набранную фразу
        let phraseStart = sentence.suffix(phraseWords)
        let typedPhrase = phraseStart.map { text(of: $0) + $0.separator }.joined() + typedText
        if phraseWords > 0, let space = layouts[current]?.keystrokes(for: " ")?.first {
            token.keys = phraseStart.flatMap { ($0.typo ?? $0.keys) + [space] } + token.keys
            sentence.removeLast(phraseWords)
        }
        token.replaced = replacement
        let mayCorrect = replacement == nil && autoCorrect && typedCleanly && !isException && !wordDecided
        // слово вне словарей — по невозможной тройке букв, где словарь молчит (выбор владельца 2026-11-08)
        var target = mayCorrect ? (detector.correction(for: token.keys, typedIn: current)
            ?? detector.impossibleCorrection(for: token.keys, typedIn: current, preferring: textLanguage))
            .map { textLanguage(over: $0, keys: token.keys, whole: true) } ?? tieBetweenCyrillics(token.keys) : nil
        // Раскладку решает слово, а не прежние слова предложения (принцип владельца 2026-11-06, B24): часть фразы
        // пишется в любой раскладке. Запрет B20/B22 «из русской фразы — только явно белорусское» снят.
        // ponytail: русское слово вне словаря («запасик» → «запасік») уходит в белорусскую — цена, выбранная владельцем
        // по замеру; держит откат ⌥ (третий кладёт слово в «Мои слова», R6), лечится полнее русским словарём
        if let target { token.language = target }
        // опечатка (docs/spec.md): раскладка верна, а слова нет ни в одном словаре, и ровно одна правка
        // даёт словарное слово. Меняется только само слово; первое ⌥ возвращает набранное
        let mayFix = replacement == nil && target == nil && correctTypos && autoCorrect && typedCleanly && !isException && !wordDecided
        var typoFix: String?
        if mayFix, let fixed = detector.typoCorrection(for: token.keys, typedIn: current),
           let fixedKeys = layouts[current]?.keystrokes(for: fixed) {
            token.typo = token.keys
            token.keys = fixedKeys
            typoFix = fixed
        }
        let shown = text(of: token)
        if let first = shown.first, Self.openers.contains(first) {
            outer.append((sentence, current))
            sentence = []
        }
        // дефис с частицей: «кто то» → «кто-то» — предыдущее слово сразу перед этим, через пробел
        if mayFix, typoFix == nil, let i = sentence.indices.last, sentence[i].separator == " ", !sentence[i].frozen,
           sentence[i].language == current, !sentence[i].decided, sentence[i].typo == nil, shown.first?.isLetter == true,
           detector.hyphenated(text(of: sentence[i]), String(LanguageDetector.core(shown)), in: current) {
            sentence[i].separator = "-"
            token.hyphen = true
        }

        if typedText.contains(where: \.isLetter) { stats.words += 1 }
        if target != nil || ellipsis { stats.autoSwitches += 1 }
        if typoFix != nil || token.hyphen { stats.typoFixes += 1 }
        if refused { lastRollback = typedText.lowercased(); stats.rollbacks += 1 }
        lastDecision = "«\(typedPhrase)» [\(current.rawValue)] → " + (replacement.map { "«\($0)» (\(ellipsis ? "троеточие" : "замена"))" } ?? target.map { "«\(shown)» [\($0.rawValue)]" }
            ?? typoFix.map { "«\($0)» (опечатка)" } ?? (token.hyphen ? "через дефис" : isException ? "исключение" : refused ? "отказ: исправление стёрто, набрано снова" : "без изменений"))
        if let replacement {
            actions = Self.edit(from: typedPhrase, to: replacement)
        } else if let target {
            actions = retype(target: target, typed: layouts[current]?.text(for: token.keys) ?? "", tail: shown)
        } else if let typoFix {
            actions = Self.edit(from: typedText, to: typoFix)
        } else if token.hyphen {
            actions = Self.edit(from: " " + shown, to: "-" + shown)
        }
        sentence.append(token)
        last = token
        if token.language.isCyrillic, token.replaced == nil, detector.isWord(shown, in: token.language),
           !layouts.contains(where: { $0.key.isCyrillic && $0.key != token.language
               && detector.isWord($0.value.text(for: token.keys), in: $0.key) }) {
            sureLanguage = token.language
        }
        // учится на наборе (решение владельца 2026-10-22, «разбирвться» не исправлялось): словарное слово
        // от 4 букв (B21: «есои» → «если»), набранное в своей раскладке без исправлений дважды, становится знакомым —
        // в него исправляется не та буква. Только ru и be: опечатки исправляются только в них (docs/spec.md)
        let plain = LanguageDetector.core(shown).lowercased()
        if correctTypos, [.ru, .be].contains(token.language), token.language == token.typedIn, target == nil,
           typoFix == nil, replacement == nil, !token.hyphen, plain.count >= 4, plain.allSatisfy(\.isLetter),
           !detector.vocabulary.contains(plain), detector.isWord(plain, in: token.language) {
            if typedOnce.remove(plain) != nil {
                detector.vocabulary.insert(plain)
                learned.append(plain)
            } else {
                typedOnce.insert(plain)
            }
        }

        if let last = shown.last, Self.closers.contains(last), let saved = outer.popLast() {
            sentence = saved.sentence + sentence.map { var t = $0; t.frozen = true; return t }
            if saved.language != current {
                actions.append(.switchLayout(saved.language))
                current = saved.language
            }
        } else if let last = shown.last, Self.sentenceEnds.contains(last) {
            endSentence()
        }
        return actions
    }

    /// Хоткей «исправить»: слово — недописанное или последнее законченное — в следующий язык круга.
    /// Круг: показанный текст → настоящие слова → раскладка, где слово набрано (отмена
    /// автоисправления) → остальные; варианты с тем же текстом пропускаются. Раскладка переключается.
    public mutating func cycleWord() -> [Action] {
        lastRollback = nil
        // выделение, уже переведённое хоткеем, — на экране перед курсором: круг идёт дальше
        if keys.isEmpty, var state = selection {
            let old = render(state.pieces, in: state.cycle[state.index])
            state.index = (state.index + 1) % state.cycle.count
            selection = state
            // текст как был выделен — раскладка последнего слова: набор продолжится после него
            let target = state.cycle[state.index] ?? state.pieces.reversed().lazy.compactMap { piece -> Language? in
                if case .keys(_, let language) = piece { language } else { nil }
            }.first ?? current
            lastDecision = "выделение: → [\(state.cycle[state.index]?.rawValue ?? "как было")]"
            current = target
            return Self.edit(from: old, to: render(state.pieces, in: state.cycle[state.index])) + [.switchLayout(target)]
        }
        if !keys.isEmpty {
            guard let target = nextInCycle(keys: keys, shown: current, typedIn: wordTypedIn ?? current) else { return [] }
            // слово исправили на лету, а ⌥ вернул раскладку, в которой его набирали, — откат
            if !wordDecided, let typedIn = wordTypedIn, typedIn != current, target == typedIn {
                lastRollback = layouts[typedIn]?.text(for: keys).lowercased()
                stats.rollbacks += 1
            } else if !wordDecided {
                stats.manualFixes += 1
            }
            wordDecided = true
            let old = layouts[current]?.text(for: keys) ?? ""
            current = target
            lastDecision = "⌥: «\(old)» → «\(layouts[target]?.text(for: keys) ?? "")» [\(target.rawValue)]"
            return Self.edit(from: old, to: layouts[target]?.text(for: keys) ?? "") + [.switchLayout(target)]
        }
        // первое нажатие после исправления опечатки или дефиса — как было набрано (решение владельца В30)
        if var token = last, token.typo != nil || token.hyphen || token.replaced != nil {
            let i = sentence.indices.last.flatMap { sentence[$0].keys == token.keys ? $0 : nil }
            let joined = token.hyphen && (i ?? 0) > 0
            let old = (joined ? "-" : "") + text(of: token) + token.separator
            let autoFixed = !token.decided && (token.typo != nil || token.hyphen)  // своя замена — не автоисправление
            if let typed = token.typo {
                if !token.decided { lastRollback = layouts[token.language]?.text(for: typed).lowercased() }
                token.keys = typed; token.typo = nil
            }
            token.replaced = nil
            token.hyphen = false
            token.decided = true
            if let i { sentence[i] = token; if joined { sentence[i - 1].separator = " " } }
            last = token
            let actions = Self.edit(from: old, to: (joined ? " " : "") + text(of: token) + token.separator)
            lastDecision = "⌥: «\(old)» → как набрано"
            // дефис за концом предложения уже не отменить — тогда сразу круг раскладок
            if !actions.isEmpty {
                if autoFixed { stats.rollbacks += 1 }
                return actions
            }
        }
        guard var token = last,
              let target = nextInCycle(keys: token.keys, shown: token.language, typedIn: token.typedIn) else { return [] }
        let old = text(of: token) + token.separator
        // слово исправили сами, а ⌥ вернул раскладку, в которой его набирали, — откат
        if !token.decided, token.language != token.typedIn, target == token.typedIn {
            lastRollback = layouts[target]?.text(for: token.keys).lowercased()
            stats.rollbacks += 1
        } else if !token.decided {
            stats.manualFixes += 1
        }
        token.language = target
        token.decided = true
        replaceLast(with: token)
        current = target
        lastDecision = "⌥: «\(old)» → «\(text(of: token))» [\(target.rawValue)]"
        return Self.edit(from: old, to: text(of: token) + token.separator) + [.switchLayout(target)]
    }

    /// Хоткей «исправить» на выделенном тексте (docs/spec.md): первое нажатие приводит весь текст к
    /// одной раскладке, дальше он идёт по кругу раскладок до исходного (проба владельца 2026-10-21:
    /// «как save отработает»). Раскладка слова — где оно набирается проще всего: латиница есть и на ⌥
    /// «Русской – ПК», и «save» по ней превращалось в «saµe». Первым идёт язык, где больше настоящих
    /// слов. Перевод печатается поверх выделения (буфер обмена не нужен), дальше он перед курсором.
    public mutating func cycleSelection(_ text: String) -> [Action] {
        // ponytail: перевод строки печатался бы символом, а в строке чата это «отправить» —
        // выделение со строками не переводится; понадобится — печатать перевод строки как ⇧↩
        guard !text.contains(where: \.isNewline) else {
            lastDecision = "выделение: в нём перевод строки — не переводится"
            return []
        }
        let languages = Language.allCases.filter { layouts[$0] != nil }
        var pieces: [Piece] = []
        var run = ""
        func flush() {
            defer { run = "" }
            guard !run.isEmpty else { return }
            guard !run.first!.isWhitespace else { pieces.append(.raw(run)); return }
            // самое простое набранное; ничья — язык, где это слово, затем текущий, затем порядок языков
            let best = languages.compactMap { language in
                layouts[language]?.keystrokes(for: run).map { (language, $0, $0.reduce(0) { $0 + $1.effort }) }
            }.min { a, b in
                (a.2, detector.isWord(run, in: a.0) ? 0 : 1, a.0 == current ? 0 : 1) < (b.2, detector.isWord(run, in: b.0) ? 0 : 1, b.0 == current ? 0 : 1)
            }
            pieces.append(best.map { .keys($0.1, $0.0) } ?? .raw(run))
        }
        for ch in text {
            if let last = run.last, last.isWhitespace != ch.isWhitespace { flush() }
            run.append(ch)
        }
        flush()
        // ponytail: варианты ранжируются числом словарных слов, затем числом слов, набранных в этой
        // раскладке; ничья — порядок Language.allCases. Варианты с одинаковым текстом — один раз
        func score(_ language: Language) -> (Int, Int) {
            let words = render(pieces, in: language).split(whereSeparator: \.isWhitespace)
                .filter { detector.isWord(String($0), in: language) }.count
            let native = pieces.filter { if case .keys(_, language) = $0 { true } else { false } }.count
            return (words, native)
        }
        var seen: Set<String> = [text]
        let variants = languages.filter { seen.insert(render(pieces, in: $0)).inserted }
            .enumerated().sorted { a, b in
                let (sa, sb) = (score(a.element), score(b.element))
                return (sa.0, sa.1, -a.offset) > (sb.0, sb.1, -b.offset)
            }.map(\.element)
        guard let target = variants.first else {
            lastDecision = "выделение: «\(text)» — других вариантов нет"
            return []
        }
        reset()
        stats.manualFixes += 1
        selection = (pieces, [nil] + variants, 1)
        lastDecision = "выделение: «\(text)» → «\(render(pieces, in: target))» [\(target.rawValue)]"
        current = target
        return [.replace(deleteCount: 0, text: render(pieces, in: target)), .switchLayout(target)]
    }

    /// Текст выделения в раскладке `language`; `nil` — каждое слово в своей, как было выделено.
    private func render(_ pieces: [Piece], in language: Language?) -> String {
        pieces.map { piece in
            switch piece {
            case let .keys(keys, own): layouts[language ?? own]?.text(for: keys) ?? ""
            case .raw(let text): text
            }
        }.joined()
    }

    /// Хоткей «транслит» (docs/spec.md): выделенный текст или последнее слово — латиницей, как в
    /// паспорте. Слово помнит набранное (`Token.replaced`): первое ⌥ возвращает его.
    public mutating func transliterate(selection: String?) -> [Action] {
        cycle = nil
        if let selection {
            let latin = Transliteration.latin(selection, language: current)
            guard latin != selection else { return [] }
            reset()
            lastDecision = "транслит: «\(selection)» → «\(latin)»"
            return [.replace(deleteCount: 0, text: latin)]
        }
        if !keys.isEmpty {
            // недописанное слово становится последним — дальше его берёт ⌥
            let token = Token(keys: keys, language: current, separator: "", typedIn: wordTypedIn ?? current)
            keys = []
            sentence.append(token)
            last = token
        }
        guard var token = last else { return [] }
        let shown = text(of: token)
        let latin = Transliteration.latin(shown, language: token.language)
        guard latin != shown else { return [] }
        token.replaced = latin
        token.decided = true
        replaceLast(with: token)
        lastDecision = "транслит: «\(shown)» → «\(latin)»"
        return Self.edit(from: shown + token.separator, to: latin + token.separator)
    }

    /// Хоткей «регистр»: слово — недописанное или последнее — строчными ↔ прописными. Есть хоть
    /// одна строчная буква — всё прописными, иначе строчными. Меняется Shift у нажатий букв.
    public mutating func changeCase() -> [Action] {
        cycle = nil
        if !keys.isEmpty {
            wordDecided = true
            let old = layouts[current]?.text(for: keys) ?? ""
            keys = flipCase(keys, in: current)
            return Self.edit(from: old, to: layouts[current]?.text(for: keys) ?? "")
        }
        guard var token = last else { return [] }
        let old = text(of: token) + token.separator
        token.keys = flipCase(token.keys, in: token.language)
        replaceLast(with: token)
        return Self.edit(from: old, to: text(of: token) + token.separator)
    }

    private mutating func nextInCycle(keys: [Keystroke], shown: Language, typedIn: Language) -> Language? {
        if cycle == nil {
            let options = detector.options(for: keys, typedIn: shown)
            let words = options.filter(\.isWord).map(\.language)
            let rest = options.filter { !$0.isWord }.map(\.language)
            cycle = ([shown] + words + rest.filter { $0 == typedIn } + rest.filter { $0 != typedIn }, 0)
        }
        guard var state = cycle, state.languages.count > 1 else { return nil }
        state.index = (state.index + 1) % state.languages.count
        cycle = state
        return state.languages[state.index]
    }

    private func flipCase(_ keys: [Keystroke], in language: Language) -> [Keystroke] {
        let upper = (layouts[language]?.text(for: keys) ?? "").contains { $0.isLowercase }
        return keys.map { key in
            guard layouts[language]?.chars[key]?.first?.isLetter == true else { return key }
            return Keystroke(code: key.code, shift: upper, option: key.option)
        }
    }

    private mutating func replaceLast(with token: Token) {
        if let i = sentence.indices.last, sentence[i].keys == last?.keys { sentence[i] = token }
        last = token
    }

    /// Минимальная правка экрана: стереть отличающийся хвост и напечатать новый.
    static func edit(from old: String, to new: String) -> [Action] {
        let old = Array(old), new = Array(new)
        var common = 0
        while common < old.count, common < new.count, old[common] == new[common] { common += 1 }
        let deleteCount = old.count - common, text = String(new[common...])
        return deleteCount == 0 && text.isEmpty ? [] : [.replace(deleteCount: deleteCount, text: text)]
    }

    /// Нажатие правки: знак или Backspace.
    public enum Keypress: Equatable, Sendable { case text(String), backspace, forwardDelete }

    /// Выделенный текст, который правят ⌥ и транслит. Выделенный хвост поля за набранным словом (`suggestionAfterCaret` —
    /// ответ поля, R16) поставило приложение — подсказка Spotlight, адресной строки: клик, стрелки и ⌘-сочетания сеанс
    /// сбрасывают, и выделить самому, не сбросив набор, нельзя. Такое выделение не правится — правится набранное слово,
    /// а подсказку правка сотрёт первой (B42, R17; B40).
    public func selectionToEdit(_ selected: String?, suggestionAfterCaret: Bool) -> String? {
        hasState && suggestionAfterCaret ? nil : selected
    }

    /// Нажатия правки «стереть N и напечатать». Litara печатает как живой набор, и приложение с автозакрытием (Notepad++,
    /// VS Code) на «[» само ставит «]» за курсор — Litara о ней не знает, и она остаётся (B19, R9). Поэтому после
    /// открывающей — закрывающая и Backspace: с автозакрытием закрывающая перепечатывает вставленную, без него стирается.
    /// ponytail: автозакрытие без перепечатки закрывающей оставит «]», как и прежде, — не хуже
    /// `suggestionAfterCaret` — за курсором выделенная подсказка приложения (Spotlight, адресная строка): первый Backspace
    /// стёр бы её, а не знак (B40), поэтому первой идёт ⌦ — она стирает выделенный хвост, а если подсказка исчезла до
    /// нажатия (поле ответило раньше, B43), курсор в конце поля и ⌦ не стирает ничего; Backspace стёр бы знак перед
    /// словом. Без стирания (`count == 0`, правка выделенного) текст печатается поверх выделения — лишнего нажатия нет.
    public static func keypresses(deleting count: Int, typing text: String, suggestionAfterCaret: Bool = false) -> [Keypress] {
        (count > 0 && suggestionAfterCaret ? [.forwardDelete] : []) + Array(repeating: .backspace, count: count)
            + text.flatMap { ch -> [Keypress] in
            guard let closer = autoClosers[ch] else { return [.text(String(ch))] }
            return [.text(String(ch)), .text(String(closer)), .backspace]
        }
    }

    private static let autoClosers: [Character: Character] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'", "`": "`"]

    /// Исправление в `target`: предложение (или однобуквенные перед словом) и слово — `typed` его
    /// уже на экране — печатаются в `target`; стирается только отличающийся хвост. Раскладка
    /// переключается всегда, даже когда текст не изменился (en ↔ pl).
    private mutating func retype(target: Language, typed: String, tail: String) -> [Action] {
        var start = sentence.count
        if target.isCyrillic == current.isCyrillic {
            // всё предложение; переводятся слова в текущей раскладке, остальное печатается как было.
            // Но если в нём есть слово, которое бывает только в текущем языке («прывітанне»), —
            // предложение на этом языке, и исправляется одно слово (проба владельца 2026-10-21)
            if !hasWordOnlyIn(current, not: target) { start = 0 }
        } else {
            // однобуквенные прямо перед словом, которые сами не исправились («z ghbdtn» → «я привет», «1/ ghbdtn» →
            // «1. привет»), — кроме настоящих слов здесь: «был в wfirm», «это и API» превращались в «d wfirm»,
            // «b API» (проба владельца 2026-10-22; замер на русском чате — 139 испорченных однобуквенных)
            while start > 0, sentence[start - 1].language == current, !sentence[start - 1].frozen,
                  LanguageDetector.core(text(of: sentence[start - 1])).count == 1,
                  !detector.isWord(text(of: sentence[start - 1]), in: current) { start -= 1 }
        }
        let old = sentence[start...].map { text(of: $0) + $0.separator }.joined() + typed
        for i in start..<sentence.count where sentence[i].language == current && !sentence[i].frozen {
            sentence[i].language = target
        }
        let new = sentence[start...].map { text(of: $0) + $0.separator }.joined() + tail
        current = target
        return Self.edit(from: old, to: new) + [.switchLayout(target)]
    }

    /// Язык текста: последнего слова, которое бывает только в одной кириллице, иначе последнего кириллического
    /// слова предложения.
    private var textLanguage: Language? { sureLanguage ?? sentence.last { $0.language.isCyrillic }?.language }

    /// Ничья между кириллицами с одинаковым текстом (из латиницы «vfvf» — и русское, и белорусское «мама»)
    /// решалась порядком языков — русский первым, и белорусский текст, набранный в английской раскладке,
    /// уходил в русскую (замер на чате «Беларускі ШІ» 2026-10-22: «і» → «и» 14 раз): тот же текст — язык текста.
    /// Только набор из латиницы и только настоящая ничья: тот же текст — слово (по пробелу) или начало слова (на
    /// лету) и в языке текста; «прымай» в русской раскладке бывает только белорусским и уходит, как прежде.
    private func textLanguage(over target: Language, keys: [Keystroke], whole: Bool) -> Language {
        guard !current.isCyrillic, target.isCyrillic, let language = textLanguage, language != target,
              let text = layouts[language]?.text(for: keys), text == layouts[target]?.text(for: keys),
              whole ? detector.isWord(text, in: language) : detector.isPrefix(text, in: language) else { return target }
        return language
    }

    /// Ничья по пробелу, где оба варианта — настоящие слова разных кириллиц: «b» — русское «и» и белорусское «і»,
    /// «bkb» — «или» и «ілі». Решает язык текста (docs/spec.md: однобуквенные исправляются по пробелу; проба
    /// владельца 2026-10-22 «b API»); вариант латиницей — ничья не между кириллицами, её решает хоткей.
    private func tieBetweenCyrillics(_ keys: [Keystroke]) -> Language? {
        guard !current.isCyrillic, let language = textLanguage,
              !detector.isWord(layouts[current]?.text(for: keys) ?? "", in: current) else { return nil }
        let words = detector.options(for: keys, typedIn: current).filter(\.isWord)
        guard words.count > 1, words.allSatisfy({ $0.language.isCyrillic }) else { return nil }
        return words.contains { $0.language == language } || layouts[language].map { detector.isWord($0.text(for: keys), in: language) } == true
            ? language : nil
    }

    private func hasWordOnlyIn(_ language: Language, not other: Language) -> Bool {
        sentence.contains { token in
            guard token.language == language, !token.frozen, let otherLayout = layouts[other] else { return false }
            return detector.isWord(text(of: token), in: language)
                && !detector.isWord(otherLayout.text(for: token.keys), in: other)
        }
    }

    private mutating func endSentence() {
        sentence = []
    }

    private func text(of token: Token) -> String {
        token.replaced ?? layouts[token.language]?.text(for: token.keys) ?? ""
    }
}
