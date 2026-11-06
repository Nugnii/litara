import Testing
@testable import LitaraCore

// Раскладки по умолчанию из docs/spec.md: ПК-варианты, ABC для английского, «Польская Pro».
let defaultLayoutIDs: [Language: String] = [
    .ru: "RussianWin", .be: "Byelorussian", .uk: "Ukrainian-PC", .en: "ABC", .pl: "PolishPro",
]

/// Набор языков владельца (en — «США международная – ПК», be, ru — «Русская – ПК»).
let ownerLayoutIDs: [Language: String] = [.en: "USInternational-PC", .be: "Byelorussian", .ru: "RussianWin"]

@MainActor
func makeDetector(_ ids: [Language: String] = defaultLayoutIDs, pcPunctuation: Bool = false, userWords: [String] = []) throws -> (LanguageDetector, [Language: KeyboardLayout]) {
    let all = KeyboardLayout.available()
    var layouts: [Language: KeyboardLayout] = [:]
    var filters: [Language: WordFilter] = [:]
    var prefixes: [Language: WordFilter] = [:]
    var checks: [Language: WordFilter] = [:]
    for (language, id) in ids {
        layouts[language] = try #require(all.first { $0.id == "com.apple.keylayout.\(id)" })
        filters[language] = try #require(WordFilter.bundled(language))
        prefixes[language] = try #require(WordFilter.bundledPrefixes(language))
        checks[language] = WordFilter.bundledCheck(language)
    }
    // как в приложении: белорусская со знаками «Русской – ПК»
    if pcPunctuation, let be = layouts[.be], let ru = layouts[.ru] { layouts[.be] = be.withPunctuation(of: ru) }
    return (LanguageDetector(layouts: layouts, filters: filters, prefixes: prefixes, checks: checks, userWords: userWords), layouts)
}
