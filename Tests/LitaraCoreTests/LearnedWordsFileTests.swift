import Foundation
import Testing
@testable import LitaraCore

@Test func learnedWordsFileRoundTripAndMerge() throws {
    // B28, решение владельца 2026-11-06: выученные слова — JSON другому человеку, импорт добавляет к его словам
    let data = try LearnedWordsFile.encode(["запасик", "абба", "дасницкий"])
    #expect(LearnedWordsFile.decode(data) == ["абба", "дасницкий", "запасик"])
    let text = try #require(String(data: data, encoding: .utf8))
    #expect(text.contains("\"format\" : \"litara-learned-words\""))
    // файл, выгруженный до переименования (B34), — принимается
    #expect(LearnedWordsFile.decode(Data("{\"format\": \"blalb-learned-words\", \"version\": 1, \"words\": [\"абба\"]}".utf8)) == ["абба"])
    // чужой файл — не файл слов Litara
    #expect(LearnedWordsFile.decode(Data("{\"words\": [\"абба\"]}".utf8)) == nil)
    #expect(LearnedWordsFile.decode(Data("[\"абба\"]".utf8)) == nil)
    #expect(LearnedWordsFile.decode(Data("не json".utf8)) == nil)
    // из файла берутся только слова: строчными, без пробелов по краям, без повторов, без латиницы и мусора
    let foreign = Data("""
    {"format": "blalb-learned-words", "version": 1,
     "words": [" Запасик ", "запасик", "hello", "/start", "", "12345", "<script>", "п'ять", "а-та-та", "\(String(repeating: "ы", count: 65))"]}
    """.utf8)
    #expect(LearnedWordsFile.decode(foreign) == ["а-та-та", "запасик", "п'ять"])
    // импорт добавляет: свои остаются, новых — сколько добавилось
    let merged = LearnedWordsFile.merge(["абба", "вуфирмы"], ["абба", "запасик"])
    #expect(merged.words == ["абба", "вуфирмы", "запасик"])
    #expect(merged.added == 1)
}
