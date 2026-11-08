import Foundation

/// Решает, в какой раскладке на самом деле набрано слово: нажатия переводятся во все включённые
/// раскладки, а словари говорят, где получилось настоящее слово.
public struct LanguageDetector: Sendable {
    /// Вариант текста: какой язык его даёт и есть ли такое слово в словаре этого языка.
    public struct Option: Sendable, Equatable {
        public let language: Language
        public let text: String
        public let isWord: Bool
    }

    private let layouts: [Language: KeyboardLayout]
    private let filters: [Language: WordFilter]
    private let prefixes: [Language: WordFilter]
    /// Проверочные фильтры (`WordFilter.bundledCheck`) — языки, где исправляются опечатки.
    private let checks: [Language: WordFilter]
    /// Свой словарь: слова пользователя и выученные из текстов — по языкам, в чьей раскладке они
    /// набираются; строчными. И их начала — для исправления на лету.
    private let userWords: [Language: Set<String>]
    private let userPrefixes: [Language: Set<String>]
    /// Тройки букв, которые встречаются в словах языка (`trigrams(of:)` по словарю, `bundledTrigrams`).
    private let trigrams: [Language: Set<String>]
    /// Слова из текстов пользователя (встреченные не меньше двух раз, строчными): не та буква
    /// исправляется только в них (решение владельца 2026-10-21). Пусто — такой промах не исправляется.
    public var vocabulary: Set<String> = []

    /// `prefixes` — фильтры начал слов (`WordFilter.prefixRange`); без них исправления на лету нет.
    /// `userWords` — свой словарь («ZUS», «дупу»): известны там, где набираются одной раскладкой.
    /// `trigrams` — тройки букв языков (`bundledTrigrams`); без них `impossibleCorrection` молчит.
    public init(layouts: [Language: KeyboardLayout], filters: [Language: WordFilter],
                prefixes: [Language: WordFilter] = [:], checks: [Language: WordFilter] = [:], userWords: [String] = [],
                trigrams: [Language: Set<String>] = [:]) {
        self.layouts = layouts
        self.filters = filters
        self.prefixes = prefixes
        self.checks = checks
        self.trigrams = trigrams
        var words: [Language: Set<String>] = [:], starts: [Language: Set<String>] = [:]
        for word in userWords.map({ $0.lowercased() })
        where word.count >= 2 && word.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "-" }) {
            for (language, layout) in layouts where layout.keystrokes(for: word) != nil {
                words[language, default: []].insert(word)
                let chars = Array(word)
                for n in WordFilter.prefixRange where n <= chars.count {
                    starts[language, default: []].insert(String(chars[..<n]))
                }
            }
        }
        self.userWords = words
        self.userPrefixes = starts
    }

    /// Во что превратятся нажатия в каждой включённой раскладке, кроме текущей и совпадающих с ней
    /// по тексту. Сначала настоящие слова; при равенстве — порядок `Language.allCases`.
    public func options(for keystrokes: [Keystroke], typedIn current: Language) -> [Option] {
        let typed = layouts[current]?.text(for: keystrokes)
        // нажатие с ⌥, давшее букву там, где набирали (латиница на ⌥ «Русской – ПК»), в варианте даёт знак
        // («∆») — такого текста никто не хотел (B4, журнал 2026-10-21: «ыфмуl» → «ыфму∆»)
        let letterOnOption = keystrokes.filter { $0.option && layouts[current]?.chars[$0]?.first?.isLetter == true }
        var byText: [String: Option] = [:]
        var order: [String] = []
        for language in Language.allCases where language != current {
            guard let text = layouts[language]?.text(for: keystrokes), text != typed, !text.isEmpty,
                  letterOnOption.allSatisfy({ layouts[language]?.chars[$0]?.first?.isLetter == true }) else { continue }
            let option = Option(language: language, text: text, isWord: isWord(text, in: language))
            if let existing = byText[text] {
                if !existing.isWord && option.isWord { byText[text] = option }
            } else {
                byText[text] = option
                order.append(text)
            }
        }
        let all = order.compactMap { byText[$0] }
        return all.filter(\.isWord) + all.filter { !$0.isWord }
    }

    /// Язык, в который надо исправить слово, или `nil` — оставить как набрано.
    ///
    /// Исправляем, только когда набранное не слово, а настоящее слово получается ровно в одном
    /// варианте. Два разных настоящих слова — неоднозначность, её решает хоткей.
    public func correction(for keystrokes: [Keystroke], typedIn current: Language) -> Language? {
        guard let typed = layouts[current]?.text(for: keystrokes) else { return nil }
        guard !isWord(typed, in: current) else { return nil }
        // текст уже верен, но слово другого языка, чья раскладка даёт тот же текст: белорусское «прымай»
        // в русской раскладке (проба владельца 2026-10-21) — раскладка переходит на этот язык, иначе
        // следующая «і» напечатается «и» (docs/spec.md: кириллица ↔ кириллица по слову другого языка)
        let sameText = layouts.filter { $0.value.text(for: keystrokes) == typed }.keys
        let sameTextWords = sameText.filter { isWord(typed, in: $0) }
        if !sameTextWords.isEmpty { return sameTextWords.count == 1 ? sameTextWords.first : nil }
        let words = options(for: keystrokes, typedIn: current).filter {
            $0.isWord && lettersStayLetters(keystrokes, from: current, to: $0.language, wordEnd: true)
        }
        // слово целиком сильнее слова со срезанным краем: «вс’» в белорусской — русское «всё», а не английское «dc»
        // с «§» по краю (B20, 2026-11-05)
        let whole = words.filter { Self.core($0.text).count == $0.text.count }
        if words.count > 1, whole.count == 1 { return whole[0].language }
        guard words.count == 1 else { return nil }
        return words[0].language
    }

    /// Слово вне словарей (docs/spec.md, выбор владельца 2026-11-08 по замеру): набранное невозможно — в нём есть
    /// тройка букв, которой нет ни в одном слове языков, где оно так пишется («шызще»: «шыз», «ызщ», «зще»), а в
    /// другой письменности ровно один вариант возможен целиком («ispot»). Только где `correction` молчит: ни
    /// набранное, ни варианты — не слова. Отдельно от `correction`: учёба слов (`learnableWords`) этим правилом не
    /// отсекается — выученное «ші» и держит «ШІ» от «IB».
    ///
    /// ponytail: замер на журнале владельца (11 дней) — 6 из 22 промахов вне словаря, тронуто 2 слова из 9 808;
    /// ложное держит откат ⌥ (третий кладёт слово в «Мои слова»). Строже — частотная модель (замер: меньше ловит).
    /// `preferred` — язык предложения: из языков с тем же вариантом (ru и be) берётся он, иначе в белорусском предложении
    /// раскладка уходила в русскую и «і» печаталась «и» (скептик 2026-11-08: «fltwt» → «адеце» [ru]).
    public func impossibleCorrection(for keystrokes: [Keystroke], typedIn current: Language,
                                     preferring preferred: Language? = nil) -> Language? {
        guard let typed = layouts[current]?.text(for: keystrokes) else { return nil }
        let word = Self.core(typed)
        let letters = word.filter(\.isLetter)
        // ponytail: до 40 знаков — `nearWord` растёт квадратично, а решение идёт в обработчике нажатий (скептик
        // 2026-11-08: зажатая клавиша, 300 букв — 140 мс); длиннее — не слово
        guard letters.count >= 2, word.count <= 40, let first = letters.first else { return nil }
        // регистр обычный — строчными, ПРОПИСНЫМИ или с заглавной: «KBDiteF» — код, а не слово
        let upper = letters.allSatisfy(\.isUppercase)
        guard upper || letters.dropFirst().allSatisfy(\.isLowercase) && (first.isLowercase || first.isUppercase) else { return nil }
        let latin = Self.isLatin(typed)
        // короткие латинские ПРОПИСНЫЕ — аббревиатуры (DNS, EBRD): английских троек в них нет
        if upper, latin, letters.count <= 4 { return nil }
        let sameText = layouts.filter { $0.value.text(for: keystrokes) == typed }.keys
        guard !sameText.contains(where: { isWord(typed, in: $0) }),
              sameText.allSatisfy({ language in
                  trigrams[language].map { table in Self.trigrams(of: typed).contains { !table.contains($0) } } ?? false
              }),
              // опечатка словарного слова («превет») — не чужая раскладка; и всё, что правит `typoCorrection`: «не»
              // слитно с глаголом — правка не в одну букву («неулупіў» → «не улупіў», а не «ytekegbo»)
              !sameText.contains(where: { nearWord(String(word), in: $0) || typoCorrection(for: keystrokes, typedIn: $0) != nil })
        else { return nil }
        let options = options(for: keystrokes, typedIn: current)
        guard !options.contains(where: \.isWord) else { return nil }
        var possible: [String: Language] = [:]
        for option in options where Self.isLatin(option.text) != latin
            && Self.core(option.text).allSatisfy({ $0.isLetter || $0.isNumber || "-'’./@_:".contains($0) }) {
            // текст бывает у нескольких раскладок (ru и be без «і», «ў»): возможен хотя бы в одном языке
            let grams = Self.trigrams(of: option.text)
            let language = ((preferred.map { [$0] } ?? []) + Language.allCases).first { language in
                !sameText.contains(language) && layouts[language]?.text(for: keystrokes) == option.text
                    // мёртвая клавиша варианта («э» — апостроф «США международной») печатает не то, что в тексте:
                    // «ОГЭ» → «JU», третья буква пропадает (R21)
                    && layouts[language]?.renders(keystrokes) == true
                    && lettersStayLetters(keystrokes, from: current, to: language, wordEnd: true)
                    && trigrams[language].map { table in grams.allSatisfy(table.contains) } == true
            }
            if let language { possible[option.text] = language }
        }
        return possible.count == 1 ? possible.first?.value : nil
    }

    /// В одной правке от словарного слова — буква лишняя, пропущена, не та или соседние переставлены; от 4 букв.
    /// Правок сотни, и ложные «да» одного фильтра копятся: слово должны знать два — проверочный, а где его нет (en,
    /// uk, pl) — фильтр начал (слово до 8 букв — само себе начало). С одним фильтром сверка с замером 2026-11-08:
    /// 216 из 3 533 переключений латиницы не случились — соседом оказывались «Kwjuj», «bqcnt».
    func nearWord(_ word: String, in language: Language) -> Bool {
        let w = Array(word.lowercased())
        guard w.count >= 4, let filter = filters[language] else { return false }
        let alphabet = Self.alphabets[language] ?? []
        func known(_ chars: [Character]) -> Bool {
            guard chars.count > 1, chars != w else { return false }
            let lower = String(chars)
            return [lower, lower.prefix(1).uppercased() + lower.dropFirst()].contains { form in
                guard filter.contains(form) else { return false }
                if let check = checks[language] { return check.contains(WordFilter.checkMarker + form) }
                return prefixes[language]?.contains(String(form.prefix(WordFilter.prefixRange.upperBound))) ?? true
            }
        }
        for i in 0...w.count {
            var c = w
            if i < w.count {
                c.remove(at: i); if known(c) { return true }
                if i + 1 < w.count { c = w; c.swapAt(i, i + 1); if known(c) { return true } }
                for ch in alphabet where ch != w[i] { c = w; c[i] = ch; if known(c) { return true } }
            }
            for ch in alphabet { c = w; c.insert(ch, at: i); if known(c) { return true } }
        }
        return false
    }

    /// Тройки букв слов текста, строчными, с границами слова «^» и «$»: «Сям’я» → «^ся», «сям», «ям'», «м'я», «'я$».
    /// Слово — буквы с апострофом внутри; цифры, дефис и знаки его делят. Так же их считает сборщик (`dictgen --trigrams`).
    public static func trigrams(of text: String) -> [String] {
        var result: [String] = [], run: [Character] = [], apostrophe = false
        func flush() {
            let p: [Character] = ["^"] + run + ["$"]
            if !run.isEmpty { for i in 0...(p.count - 3) { result.append(String(p[i..<i + 3])) } }
            run = []; apostrophe = false
        }
        for ch in text.lowercased() {
            let ch: Character = ch == "’" ? "'" : ch
            if ch.isLetter {
                if apostrophe { run.append("'"); apostrophe = false }
                run.append(ch)
            } else if ch == "'", !run.isEmpty, !apostrophe {
                apostrophe = true
            } else {
                flush()
            }
        }
        flush()
        return result
    }

    /// Тройки букв языка, собранные scripts/build_dictionaries.sh из его словаря и имён.
    public static func bundledTrigrams(_ language: Language) -> Set<String>? {
        guard let url = Bundle.module.url(forResource: language.rawValue, withExtension: "trigrams", subdirectory: "Resources"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return Set(text.split(separator: "\n").map(String.init))
    }

    /// Исправление на лету: язык, в который надо исправить недописанное слово, или `nil`.
    ///
    /// Решает начало слова (с третьей буквы, docs/spec.md): невозможно ни в одном языке, где оно
    /// пишется так же, и возможно ровно в одном другом варианте. Начала длиннее
    /// `WordFilter.prefixRange` неизвестны — их решает пробел.
    public func earlyCorrection(for keystrokes: [Keystroke], typedIn current: Language) -> Language? {
        // порог — по нажатиям: мёртвая клавиша на экране ничего не печатает, но буквой была
        guard let typed = layouts[current]?.text(for: keystrokes),
              WordFilter.prefixRange.contains(keystrokes.count) else { return nil }
        // последнее нажатие мёртвое здесь (ę, ń на Option в английской) — человек имел в виду
        // раскладку, где оно буква: «верный текст» здесь не решает
        let lastDead = keystrokes.last.map { layouts[current]?.chars[$0] == nil } ?? false
        let sameText = layouts.filter { $0.value.text(for: keystrokes) == typed }.keys
        if !lastDead, sameText.contains(where: { isPrefix(typed, in: $0) }) {
            // текст верен; раскладку — на язык, где он возможен: en и pl пишут основные буквы одинаково,
            // а диакритика «Польской Pro» на Option в английской раскладке — мёртвые клавиши
            // Кириллица так не переключается: незнакомое русское слово с белорусским началом («класный» —
            // «класны») молча уводило раскладку, и дальше «и» печаталась «і». Текст верен — решит пробел
            guard !isPrefix(typed, in: current), !current.isCyrillic else { return nil }
            return Language.allCases.first { $0 != current && sameText.contains($0) && isPrefix(typed, in: $0) }
        }
        var candidates: [String: Language] = [:]
        for language in Language.allCases where !sameText.contains(language) {
            guard let text = layouts[language]?.text(for: keystrokes), isPrefix(text, in: language),
                  lettersStayLetters(keystrokes, from: current, to: language, wordEnd: false) else { continue }
            if candidates[text] == nil { candidates[text] = language }
        }
        return candidates.count == 1 ? candidates.first?.value : nil
    }

    /// Буква набранного осталась буквой в варианте (R13, B26). Знак по краю срезается, чтобы «(привет)» и «"Сл» были
    /// словами, но буква, ставшая знаком, — не рамка: «быкуе» → «,sret», «ютуб» → «.ne,» (владелец 2026-11-06: слово
    /// не содержит спецсимволов; журнал с 2026-10-23 — 12 таких решений, все ложные). Апостроф — буква («вщтэе» →
    /// «don't»); по пробелу последнее нажатие может стать знаком препинания после слова («руддщб» → «hello,»).
    /// Круг ⌥ это не проверяет: там выбирает человек.
    private func lettersStayLetters(_ keystrokes: [Keystroke], from current: Language, to language: Language,
                                    wordEnd: Bool) -> Bool {
        guard let from = layouts[current], let to = layouts[language] else { return true }
        for (i, key) in keystrokes.enumerated() where from.chars[key]?.first?.isLetter == true {
            guard let ch = to.chars[key]?.first, !ch.isLetter, ch != "'", ch != "’" else { continue }
            if wordEnd, i == keystrokes.count - 1, ",.;:!?".contains(ch) { continue }
            return false
        }
        return true
    }

    /// Исправление опечатки (docs/spec.md, решения владельца 2026-10-21): весь набранный текст со знаками
    /// по краям — или `nil`. Строго: набранного нет в словаре ни одного языка, ни в какой раскладке,
    /// а правка — удвоить или убрать букву, вставить пропущенную, убрать лишнюю, переставить соседние,
    /// отделить «не» — даёт ровно одно словарное слово. Два варианта — не трогаем.
    public func typoCorrection(for keystrokes: [Keystroke], typedIn language: Language) -> String? {
        guard checks[language] != nil, let alphabet = Self.alphabets[language],
              let typed = layouts[language]?.text(for: keystrokes) else { return nil }
        let word = Self.core(typed)
        // регистр как набран: ВСЁ ПРОПИСНЫМИ или с заглавной
        func cased(_ fixed: String) -> String {
            let text = word.allSatisfy({ !$0.isLowercase }) ? fixed.uppercased()
                : word.first?.isUppercase == true ? fixed.prefix(1).uppercased() + fixed.dropFirst() : fixed
            return String(typed[..<word.startIndex]) + text + String(typed[word.endIndex...])
        }
        // частица слитно (вид «дефис с частицей», проба владельца 2026-10-21: «почемуто» → «почему-то»):
        // список точный, поэтому и для коротких («чтото»)
        if let hyphenated = mergedParticle(word.lowercased(), in: language), !isWord(typed, in: language) {
            return cased(hyphenated)
        }
        // ponytail: строгость по замеру на чате владельца (2026-10-21): от 6 букв — у коротких слов и сленга
        // словарный сосед есть почти всегда («таску» → «таксу», «турба» → «труба»); слово с заглавной —
        // обычно имя («Ллама», «Сямашка») — не трогаем. Промах по соседней клавише — от 4 букв («есои» → «если»,
        // решение владельца 2026-11-05, B21)
        guard word.count >= 4, word.first?.isLowercase == true, word.allSatisfy({ $0.lowercased().count == 1 && alphabet.contains(Character($0.lowercased())) })
        else { return nil }
        let short = word.count < 6
        let sameText = layouts.filter { $0.value.text(for: keystrokes) == typed }.keys
        guard !sameText.contains(where: { isWord(typed, in: $0) }),
              !options(for: keystrokes, typedIn: language).contains(where: \.isWord) else { return nil }
        let lower = Array(word.lowercased())
        var found = Set<String>()
        func consider(_ candidate: [Character]) {
            let text = String(candidate)
            if confirmed(text, in: language) { found.insert(text) }
        }
        let endingExists = checks[language]?.contains(WordFilter.endingMarker + String(lower.suffix(3))) == true
        // удвоенная согласная (не последняя буква: «телеграм» — не «телеграмм»), повтор любой буквы,
        // соседние переставлены (не первые две: «даданне» — не «адданне»), «не» слитно с глаголом — от 6 букв
        for i in lower.indices where !short {
            // и не перед последней буквой: «мадэлю» → «мадэллю» — творительный падеж, а не опечатка (в чате
            // владельца эта форма встретилась 15 раз)
            if i + 2 < lower.count, !Self.vowels[language, default: []].contains(lower[i]), lower[i].isLetter {
                var doubled = lower; doubled.insert(lower[i], at: i); consider(doubled)
            }
            if i + 1 < lower.count {
                if lower[i] == lower[i + 1] { var single = lower; single.remove(at: i); consider(single) }
                // перестановка: от 8 букв — всегда; короче — только если окончание набранного невозможно в
                // языке: «приевт» — на «-евт» слов нет (проба владельца 2026-10-21). У сленга окончание
                // обычное: «каменты» → «каметны», «збаіць» → «забіць» были ложными (замер на чате)
                if i > 0, lower.count >= 8 || !endingExists {
                    var swapped = lower; swapped.swapAt(i, i + 1); consider(swapped)
                }
            }
        }
        // не та буква (проба владельца 2026-10-21: «теперт» → «теперь», «симполов» → «символов»).
        // Слово ломается там, где ошиблись: начало становится невозможным на этой букве или не дальше двух
        // после неё («атрф…», «симпол…» — «симпо» ещё начало «симпозиума»). Новые слова и сленг ломаются в
        // другом месте или нигде («агучка» → «анучка», «стартап» → «стартам»: без этого замер на чатах дал
        // втрое больше ложных, чем верных)
        let breakAt = (WordFilter.prefixRange.lowerBound...min(lower.count, WordFilter.prefixRange.upperBound))
            .first { !isPrefix(String(lower.prefix($0)), in: language) }.map { $0 - 1 }
        // длиннее фильтра начал: слом виден по окончанию — набранное кончается так, как слова не кончаются
        // («беспорядочныц», проба владельца 2026-10-21) — промах ищется в последних трёх буквах
        let endBroken = breakAt == nil && lower.count > WordFilter.prefixRange.upperBound && !endingExists
        // и только в слово из текстов пользователя (решение владельца 2026-10-21). Замер на одном из чатов:
        // соседняя клавиша — 17 из 17 верных; любая буква — около 58 верных и 15 ложных («третим» → «третий»),
        // владелец выбрал любую; без словаря текстов — половина ложных («денюжка» → «дерюжка»)
        if let layout = layouts[language], breakAt != nil || endBroken {
            for i in lower.indices where i > 0 && ((breakAt.map { i <= $0 && i >= $0 - 2 } ?? false) || (endBroken && i >= lower.count - 3)) {
                guard layout.keystrokes(for: String(lower[i])) != nil else { continue }
                let neighbors = layout.neighbors(of: lower[i])
                // любая буква, а не только соседняя клавиша («симполов» → «символов», решение владельца
                // 2026-10-21; замер на чате: +44 исправления, ~38 верных — ⌥ и «не исправлять» после 3 откатов)
                for near in alphabet where near != lower[i] {
                    // гласная на гласную в конце — другая форма слова («голаса» — не «голасе»), не промах
                    let vowels = Self.vowels[language, default: []]
                    if i == lower.count - 1, vowels.contains(lower[i]), vowels.contains(near) { continue }
                    var missed = lower; missed[i] = near
                    // в слово из текстов пользователя; короткое (4–5 букв) — только соседняя клавиша («есои» → «если»,
                    // B21). В любое словарное слово — замер 2026-11-05 на чатах владельца: верных 1 на 3 ложных
                    if vocabulary.contains(String(missed)), !short || neighbors.contains(near) { consider(missed) }
                }
            }
        }
        // «не» отделяется только от глагола: «неякасна», «невідавочны» слитно — верно
        let rest = String(lower.dropFirst(2))
        // «-ае» бывает и у прилагательного («недасяжнае»): есть форма на «-ы» — прилагательное, слитно
        let adjective = rest.hasSuffix("ае") && confirmed(String(rest.dropLast(2)) + "ы", in: language)
        if !short, lower.starts(with: ["н", "е"]), !adjective, Self.verbEndings[language]?.contains(where: rest.hasSuffix) == true,
           confirmed(rest, in: language) {
            found.insert("не " + rest)
        }
        // ponytail: «любая пропущенная или лишняя буква» (В27 «д») не исправляется — замер на чате
        // владельца 2026-10-21: 1113 исправлений на 35 779 слов, почти все ложные («промт» → «пром»,
        // «падкаст» → «падкат», «ютубе» → «тубе»): у новых слов и сленга сосед в одну букву есть почти всегда
        guard found.count == 1, let fixed = found.first else { return nil }
        return cased(fixed)
    }

    /// Частица, написанная слитно: «почемуто» → «почему-то», «коечто» → «кое-что»; белорусский — по словарю
    /// («хтонебудзь» → «хто-небудзь»). `word` — строчными.
    func mergedParticle(_ word: String, in language: Language) -> String? {
        switch language {
        case .ru:
            for particle in ["то", "либо", "нибудь"] where word.hasSuffix(particle) {
                let stem = String(word.dropLast(particle.count))
                if Self.questionWords.contains(stem) { return stem + "-" + particle }
            }
            for prefix in ["кое", "кой"] where word.hasPrefix(prefix) && Self.questionWords.contains(String(word.dropFirst(prefix.count))) {
                return prefix + "-" + word.dropFirst(prefix.count)
            }
            return nil
        case .be:
            // только частицы: составные слова («плэйліст» — «плэй-ліст» по словарю) многие пишут слитно (замер на чате)
            guard checks[.be] != nil else { return nil }
            if word.hasSuffix("небудзь"), word.count > 7, confirmed(String(word.dropLast(7)) + "-небудзь", in: .be) {
                return String(word.dropLast(7)) + "-небудзь"
            }
            if word.hasPrefix("абы"), word.count > 3, confirmed("абы-" + word.dropFirst(3), in: .be) { return "абы-" + word.dropFirst(3) }
            return nil
        default:
            return nil
        }
    }

    /// Слово, с которым согласны оба фильтра (или свой словарь), — для опечаток, где вариантов сотни.
    func confirmed(_ word: String, in language: Language) -> Bool {
        if userWords[language]?.contains(word) == true { return true }
        return Self.forms(Substring(word)).contains {
            filters[language]?.contains($0) == true && checks[language]?.contains(WordFilter.checkMarker + $0) == true
        }
    }

    /// Дефис с частицей (docs/spec.md): «кто то» → «кто-то». Русский — по правилам (дефисных слов в
    /// словаре нет): -то, -либо, -нибудь после вопросительного слова; кое- перед ним; по- + «-ски».
    /// Белорусский — по словарю: «хто-небудзь», «па-беларуску».
    public func hyphenated(_ first: String, _ second: String, in language: Language) -> Bool {
        let a = first.lowercased(), b = second.lowercased()
        guard checks[language] != nil, !a.isEmpty, !b.isEmpty,
              a.allSatisfy(\.isLetter), b.allSatisfy(\.isLetter) else { return false }
        switch language {
        case .ru:
            if Self.questionWords.contains(a), ["то", "либо", "нибудь"].contains(b) { return true }
            if ["кое", "кой"].contains(a), Self.questionWords.contains(b) { return true }
            // «русски» в словаре есть само по себе; признак наречия — прилагательное «русский» (а «доски» — нет)
            return a == "по" && (b.hasSuffix("ски") || b.hasSuffix("цки")) && isWord(b + "й", in: .ru)
        case .be:
            // ponytail: «так-што» в словаре есть, но «так што» (= «так что») пишется раздельно (замер на чате)
            return a + "-" + b != "так-што" && confirmed(a + "-" + b, in: .be)
        default:
            return false
        }
    }

    // ponytail: список ручной — вопросительные слова со всеми падежами; «из-за», «во-первых» не берём:
    // «во вторых рядах» пишется раздельно, а «из за» в решении владельца нет
    static let questionWords: Set<String> = [
        "кто", "кого", "кому", "кем", "ком", "что", "чего", "чему", "чем", "где", "куда", "откуда", "когда",
        "как", "какой", "какого", "какому", "каким", "каком", "какая", "какую", "какое", "какие", "каких",
        "какими", "чей", "чьего", "чьему", "чьим", "чьём", "чья", "чьей", "чью", "чьё", "чьи", "чьих", "чьими",
        "почему", "зачем", "сколько", "скольких", "отчего",
    ]

    // ponytail: глагол узнаётся по окончанию — части речи в словаре нет; прошедшее, настоящее, инфинитив
    static let verbEndings: [Language: [String]] = [
        .ru: ["л", "ла", "ло", "ли", "ю", "ешь", "ет", "ем", "ете", "ут", "ют", "ишь", "ит", "им", "ите", "ат", "ят",
              "ть", "ться", "лся", "лась", "лось", "лись", "юсь", "ется", "ются", "ится", "ятся", "атся"],
        .be: ["ў", "ла", "ло", "лі", "ю", "еш", "е", "ем", "еце", "уць", "юць", "іш", "іць", "ім", "іце", "аць", "яць",
              "ць", "цца", "ўся", "лася", "лося", "ліся", "юся", "ецца", "юцца", "іцца"],
    ]

    static let alphabets: [Language: [Character]] = [
        .ru: Array("абвгдеёжзийклмнопрстуфхцчшщъыьэюя"),
        .be: Array("абвгдеёжзійклмнопрстуўфхцчшыьэюя'"),
        // en, uk, pl — только для `nearWord`: опечатки в них не исправляются (docs/spec.md)
        .uk: Array("абвгґдеєжзиіїйклмнопрстуфхцчшщьюя'"),
        .en: Array("abcdefghijklmnopqrstuvwxyz'"),
        .pl: Array("aąbcćdeęfghijklłmnńoópqrsśtuvwxyzźż"),
    ]

    /// Начало слова без знаков впереди: «(пр» → «пр». Сзади не срезается — знак в одной раскладке
    /// бывает буквой в другой.
    static func leading(_ text: String) -> Substring {
        var s = Substring(text)
        while let first = s.first, first.isPunctuation { s = s.dropFirst() }
        return s
    }

    /// Начало короче трёх букв не решает (docs/spec.md: «с третьей буквы»). Порог на лету считается по
    /// нажатиям, а знак впереди срезается: «"Сл» — три нажатия и две буквы. Начал из двух букв в фильтре
    /// нет, а целые слова есть («ck», «hf» в английском) — «"Сл» уводило белорусскую в «@Ck», а оттуда
    /// в русскую (чат «Беларускі ШІ» 2026-10-21: 13 из 20 ложных уходов на лету — слова в кавычках).
    func isPrefix(_ text: String, in language: Language) -> Bool {
        let start = Self.leading(text)
        guard start.filter({ $0.isLetter || $0 == "'" }).count >= WordFilter.prefixRange.lowerBound,
              start.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "-" }) else { return false }
        let lower = start.lowercased()
        if userPrefixes[language]?.contains(lower) == true || userWords[language]?.contains(lower) == true { return true }
        return Self.forms(start).contains { prefixes[language]?.contains($0) == true || filters[language]?.contains($0) == true }
    }

    /// Бывают ли в языке слова с таким окончанием (три последние буквы); без проверочного фильтра — «да»: сказать нечего.
    func endingPossible(_ text: String, in language: Language) -> Bool {
        guard let check = checks[language] else { return true }
        return check.contains(WordFilter.endingMarker + String(Self.core(text).lowercased().suffix(3)))
    }

    /// Слова из текста, которых не хватает словарям: встретились не меньше `minCount` раз (в общем чате `group` —
    /// вдвое больше), их нет ни в одном словаре и они не набраны не в той раскладке («ghbdtn» в переписке — не слово).
    public func learnableWords(in text: String, group: String = "", minCount: Int = 2) -> [String] {
        Self.wordCounts(text, group: group).filter { $0.value >= 2 * minCount }.keys.filter { candidate in
            // латиница не учится (решение владельца 2026-10-21): из чатов это ссылки, ники и сокращения,
            // и они превращали русский сленг вне словаря в латиницу («шифт» → «iban»).
            // ponytail: польский сленг так тоже не выучится — понадобится, сделать выбор языков обучения
            guard !Self.isLatin(candidate) else { return false }
            let typeable = layouts.compactMap { language, layout in layout.keystrokes(for: candidate).map { (language, $0) } }
            guard !typeable.isEmpty, !typeable.contains(where: { isWord(candidate, in: $0.0) }) else { return false }
            return !typeable.contains { correction(for: $0.1, typedIn: $0.0) != nil }
        }.sorted()
    }

    /// Знакомые слова из текстов — в них исправляется «не та буква» (решение владельца
    /// 2026-10-21): словарные слова от 4 букв (B21), встреченные не меньше `minCount` раз (в общем чате `group` —
    /// вдвое больше); строчными.
    public func vocabularyWords(in text: String, group: String = "", minCount: Int = 2) -> [String] {
        Self.wordCounts(text, group: group).filter { word, count in
            count >= 2 * minCount && word.count >= 4 && Language.allCases.contains { isWord(word, in: $0) }
        }.keys.sorted()
    }

    /// Счёт слов, где слово из общего чата весит вдвое меньше: там пишут многие, и чужие опечатки повторяются —
    /// оттуда слово берётся с 4 раз, а не с 2 (решение владельца 2026-11-02, B17). Порог — `2 * minCount`.
    private static func wordCounts(_ text: String, group: String) -> [String: Int] {
        wordCounts(group).merging(wordCounts(text).mapValues { $0 * 2 }, uniquingKeysWith: +)
    }

    /// Слова текста (строчными, без апострофа и дефиса по краям) и сколько раз каждое встретилось.
    private static func wordCounts(_ text: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        var word = ""
        func flush() {
            let core = word.trimmingCharacters(in: CharacterSet(charactersIn: "'-")).lowercased()
            if core.count >= 2 { counts[core, default: 0] += 1 }
            word = ""
        }
        for ch in text {
            if ch.isLetter || ((ch == "'" || ch == "-") && !word.isEmpty) { word.append(ch) } else { flush() }
        }
        flush()
        return counts
    }

    /// Однобуквенные слова — явным списком: словари считают словом каждую букву (название буквы),
    /// и «z» никогда не стало бы «я». ponytail: список ручной; появятся жалобы — сверять с частотами.
    static let singleLetterWords: [Language: Set<String>] = [
        .en: ["a", "I", "i"],
        .ru: ["а", "в", "и", "к", "о", "с", "у", "я"],
        // «я» и «о» — и белорусские: без них «я» в белорусской раскладке уводило её в русскую (замер на чате
        // «Беларускі ШІ» 2026-10-21: 583 раза на 63 043 слова)
        .be: ["а", "і", "у", "ў", "з", "ж", "я", "о"],
        .uk: ["а", "в", "з", "і", "й", "у", "я", "о", "ж"],
        .pl: ["a", "i", "o", "u", "w", "z"],
    ]

    /// Как слово ищется в словаре, где регистр сохранён: как набрано, строчными и с заглавной.
    /// Строчное совпадает с именем («iban» — «Iban», «london» — «London»: в чатах имена пишут
    /// строчными), но не с аббревиатурой из одних заглавных («nj» — не «NJ»).
    static func forms(_ word: Substring) -> [String] {
        let lower = word.lowercased()
        return [String(word), lower, lower.prefix(1).uppercased() + lower.dropFirst()]
    }

    /// Слово с латинской буквой (а не кирилличное).
    public static func isLatin(_ word: String) -> Bool {
        word.unicodeScalars.contains { ("a"..."z").contains($0) || ("A"..."Z").contains($0) || (0x00C0...0x024F).contains($0.value) }
    }

    /// Сокращения с точками внутри (без последней точки — её срезает `core`): точка не буква, и
    /// словарь их не знает.
    static let abbreviations: [Language: Set<String>] = [
        .ru: ["т.е", "т.к", "т.д", "т.п", "т.н", "т.ч", "т.о", "и.о", "н.э"],
        .be: ["г.зн", "т.зв", "г.д"],
        .uk: ["т.д", "т.п", "т.ч", "т.я"],
        .en: ["e.g", "i.e", "a.m", "p.m"],
        .pl: ["m.in"],
    ]

    /// Гласные языков — для растянутых междометий («аааа», «ooo»).
    static let vowels: [Language: Set<Character>] = [
        .ru: Set("аеёиоуыэюя"), .be: Set("аеёіоуыэюя"), .uk: Set("аеєиіїоуюя"),
        .en: Set("aeiou"), .pl: Set("aeiouyąęó"),
    ]

    /// Слово без знаков по краям: «привет,» → «привет», «(hello)» → «hello». Нажатия переводятся
    /// целиком, со знаками: на клавишах «, . ; ' [ ]» английской стоят русские буквы б ю ж э х ъ,
    /// так что знак в одной раскладке — буква в другой («k.,jq» → «любой»).
    ///
    /// Срезаются только знаки препинания: символ вроде «≈» (Option в английской на месте польской «ź»)
    /// остаётся, иначе «fred≈» превращалось в английское «fred» и польское слово не исправлялось.
    static func core(_ text: String) -> Substring {
        var s = Substring(text)
        while let first = s.first, first.isPunctuation { s = s.dropFirst() }
        while let last = s.last, last.isPunctuation { s = s.dropLast() }
        return s
    }

    // В словарях только буквы, апостроф и дефис: строку с «,» или «\» фильтр не спрашиваем —
    // иначе его ложные «да» превращают мусор вроде «,ercjdst» в слово.
    /// Есть ли такое слово в языке: словарь (с учётом регистра), однобуквенные — по списку, свой словарь.
    public func isWord(_ text: String, in language: Language) -> Bool {
        let word = Self.core(text)
        if word.contains(".") { return Self.abbreviations[language]?.contains(word.lowercased()) == true }
        guard !word.isEmpty, word.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "-" }) else { return false }
        if word.count > 1, userWords[language]?.contains(word.lowercased()) == true { return true }
        if word.count == 1 {
            return Self.singleLetterWords[language].map { $0.contains(String(word)) || $0.contains(word.lowercased()) } ?? false
        }
        // растянутая гласная — междометие («аааа», «ооо»): в словарях её нет
        let lower = word.lowercased()
        if let first = lower.first, lower.allSatisfy({ $0 == first }), Self.vowels[language]?.contains(first) == true {
            return true
        }
        return Self.forms(word).contains { filters[language]?.contains($0) == true }
    }
}
