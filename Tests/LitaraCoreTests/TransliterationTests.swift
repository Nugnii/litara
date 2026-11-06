import Testing
@testable import LitaraCore

// docs/spec.md: как в паспорте, без диакритики; примеры владельца — первые два
@Test(arguments: [
    ("Канстанцін Берсенеў", nil, "Kanstantsin Berseneu"),
    ("привет", nil, "privet"),
    ("Щукин, Юрий!", nil, "Shchukin, Iurii!"),
    ("Гомель і Мінск", nil, "Homel i Minsk"),     // «і» в тексте — белорусский и для «Гомель»
    ("Гродна", Language.be, "Hrodna"),            // без «і/ў» решает раскладка
    ("Гродна", Language.ru, "Grodna"),
    ("сям'я", Language.be, "siamia"),
    ("Київ", nil, "Kyiv"),
    ("ЖЖУК", nil, "ZHZHUK"),
    ("blalb 0.3", nil, "blalb 0.3"),
] as [(String, Language?, String)])
func passportTransliteration(cyrillic: String, language: Language?, latin: String) {
    #expect(Transliteration.latin(cyrillic, language: language) == latin)
}
