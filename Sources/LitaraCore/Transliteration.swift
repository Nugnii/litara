/// Транслит кириллицы в латиницу, как в паспорте, без диакритики (docs/spec.md):
/// «Канстанцін Берсенеў» → «Kanstantsin Berseneu», «привет» → «privet».
///
/// Язык — по буквам всего текста: і, ў — белорусский (г → h), ї, є, ґ — украинский (г → h, и → y);
/// иначе — раскладка, в которой текст набран (`language`), и по умолчанию русский (ICAO 9303, как в
/// загранпаспорте РФ). «Гродна» в белорусской раскладке — Hrodna, в русской — Grodna. Не кириллица — как есть.
/// ponytail: начальные формы украинского паспорта (Ye-, Yu-, Ya- в начале слова) не различаются —
/// всюду ie, iu, ia; понадобятся — правило по позиции в слове.
public enum Transliteration {
    public static func latin(_ text: String, language: Language? = nil) -> String {
        let table = text.contains(where: { "іўІЎ".contains($0) }) ? be
            : text.contains(where: { "їєґЇЄҐ".contains($0) }) ? uk
            : language == .be ? be : language == .uk ? uk : ru
        var result = ""
        var word = ""
        func flush() {
            for ch in word {
                let lower = Character(ch.lowercased())
                guard let latin = table[lower] ?? ru[lower] else { result.append(ch); continue }
                // заглавная: первая буква латиницы заглавной, а у слова из одних заглавных — все
                guard ch.isUppercase else { result += latin; continue }
                let allCaps = word.count > 1 && word.allSatisfy { !$0.isLowercase }
                result += allCaps ? latin.uppercased() : latin.prefix(1).uppercased() + latin.dropFirst()
            }
            word = ""
        }
        for ch in text {
            if ch.isLetter || ch == "'" || ch == "’" { word.append(ch) } else { flush(); result.append(ch) }
        }
        flush()
        return result
    }

    static let ru: [Character: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e", "ж": "zh", "з": "z", "и": "i",
        "й": "i", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t",
        "у": "u", "ф": "f", "х": "kh", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "shch", "ъ": "ie", "ы": "y",
        "ь": "", "э": "e", "ю": "iu", "я": "ia",
    ]
    /// Белорусский: г → h, і → i, ў → u, апостроф пропадает; остальное как в русском.
    static let be: [Character: String] = ["г": "h", "і": "i", "ў": "u", "'": "", "’": ""]
    /// Украинский паспорт: г → h, ґ → g, и → y, і → i, ї → i, є → ie, апостроф пропадает.
    static let uk: [Character: String] = ["г": "h", "ґ": "g", "и": "y", "і": "i", "ї": "i", "є": "ie", "'": "", "’": ""]
}
