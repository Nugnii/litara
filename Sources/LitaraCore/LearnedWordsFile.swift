import Foundation

/// Выученные слова для передачи другому человеку (решение владельца 2026-11-06, B28): JSON
/// `{"format": "litara-learned-words", "version": 1, "words": […]}`. Только выученные — без словаря текстов, «Моих слов»
/// и своих замен. Импорт добавляет к своим.
public enum LearnedWordsFile {
    public static let format = "litara-learned-words"
    /// Файлы, выгруженные до переименования (0.28.0, B34), — тоже принимаются.
    static let legacyFormats: Set<String> = ["blalb-learned-words"]

    private struct Payload: Codable {
        var format: String
        var version: Int
        var words: [String]
    }

    public static func encode(_ words: [String]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Payload(format: format, version: 1, words: words.filter(isWord).sorted()))
    }

    /// Слова из файла; не файл слов Litara — `nil`. Файл приходит от другого человека: берутся только слова (`isWord`),
    /// строчными и без повторов.
    public static func decode(_ data: Data) -> [String]? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data), payload.format == format || legacyFormats.contains(payload.format) else { return nil }
        let words = payload.words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter(isWord)
        return Array(Set(words)).sorted()
    }

    /// Свои слова плюс импортированные; `added` — сколько новых.
    public static func merge(_ mine: [String], _ imported: [String]) -> (words: [String], added: Int) {
        let have = Set(mine)
        let new = Set(imported).subtracting(have)
        return ((mine + new).sorted(), new.count)
    }

    /// Слово, как их выучивает Litara: буквы, апостроф, дефис, до 64 знаков, не латиница (латинские выученные не хранятся).
    static func isWord(_ s: String) -> Bool {
        (1...64).contains(s.count) && s.contains(where: \.isLetter)
            && s.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" || $0 == "-" }) && !LanguageDetector.isLatin(s)
    }
}
