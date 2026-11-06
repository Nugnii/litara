import Foundation
import Testing
@testable import LitaraCore

// Слова сверены со списками, развёрнутыми из словарей hunspell (scripts/expand_hunspell.py).
@Test(arguments: [
    (Language.ru, ["привет", "мама", "домами", "сделаешь", "ёлка"], ["прівет", "сінія", "дзякуй"]),
    (.be, ["дзякуй", "прывітанне", "сінія", "сям'я", "і", "ёсць"], ["привет", "прівет", "щи"]),
    (.uk, ["привіт", "сім'я", "їжак", "ґанок"], ["привет", "ы"]),
    (.pl, ["żółw", "żółwia", "dziękuję"], ["zolw", "ghbdtn"]),
    (.en, ["hello", "don't", "running", "children"], ["ghbdtn", "руддщ"]),
])
func bundledFilterKnowsItsWords(language: Language, words: [String], foreign: [String]) throws {
    let filter = try #require(WordFilter.bundled(language))
    for word in words { #expect(filter.contains(word), "\(language): \(word)") }
    for word in foreign { #expect(!filter.contains(word), "\(language): \(word)") }
}

@Test func falsePositiveRateStaysNearDesign() throws {
    let filter = try #require(WordFilter.bundled(.ru))
    var rng = SplitMix64(seed: 2026)
    let letters = Array("абвгдеёжзийклмнопрстуфхцчшщъыьэюя")
    let trials = 20_000
    let hits = (0..<trials).filter { _ in
        filter.contains(String((0..<7).map { _ in letters[Int(rng.next() % UInt64(letters.count))] }))
    }.count
    // замысел — 0,1%; случайные 7 букв почти никогда не слово
    #expect(Double(hits) / Double(trials) < 0.003, "ложных «да»: \(hits) из \(trials)")
}

// Свойство сериализации — восстановленный фильтр отвечает ровно как исходный. Абсолютное «нет»
// на крошечном фильтре не проверяем: при двух словах в нём 39 бит, и ложное «да» — лотерея.
@Test func serializationRoundTrips() throws {
    let original = WordFilter(words: ["мама", "тата"], count: 2)
    let restored = try #require(WordFilter(data: original.serialized()))
    let probes = ["мама", "тата", "дзед", "баба", "hello", "żółw", "сям'я", ""]
    #expect(probes.map(restored.contains) == probes.map(original.contains))
    #expect(restored.contains("мама") && restored.contains("тата"))
    #expect(WordFilter(data: Data("junk".utf8)) == nil)
}

private struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }
}
