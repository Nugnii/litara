import Foundation
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
    var trigrams: [Language: Set<String>] = [:]
    for (language, id) in ids {
        layouts[language] = try #require(all.first { $0.id == "com.apple.keylayout.\(id)" })
        filters[language] = try #require(WordFilter.bundled(language))
        prefixes[language] = try #require(WordFilter.bundledPrefixes(language))
        checks[language] = WordFilter.bundledCheck(language)
        trigrams[language] = try #require(LanguageDetector.bundledTrigrams(language))
    }
    // как в приложении: белорусская со знаками «Русской – ПК»
    if pcPunctuation, let be = layouts[.be], let ru = layouts[.ru] { layouts[.be] = be.withPunctuation(of: ru) }
    return (LanguageDetector(layouts: layouts, filters: filters, prefixes: prefixes, checks: checks, userWords: userWords,
                             trigrams: trigrams), layouts)
}

/// Временный домен настроек теста — путь во временной папке, а не имя: домен с именем оставляет в ~/Library/Preferences
/// пустой plist, и система дописывает его через секунды после сброса — удалить из теста нельзя (B37, опыт 2026-11-07).
/// ponytail: такие же пустые plist остаются во временной папке, пока её не очистит система
func temporaryDefaultsName(_ tag: String) -> String {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("litara-test-defaults")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("\(tag)-\(UUID().uuidString)").path
}

func removeTemporaryDefaults(_ names: String...) {
    for name in names { UserDefaults().removePersistentDomain(forName: name) }
}
