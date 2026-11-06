import Foundation
import Testing
@testable import LitaraCore

// Противник переименования blalb → Litara (B34). Домены — свои на каждый тест, настоящие dev.blalb.app и
// io.github.nugnii.litara не трогаются.

/// Откат на blalb и обратно: владелец ставит Litara, уходит на blalb 0.28.0 (build/blalb-0.28.0.dmg лежит рядом),
/// набирает там, возвращается на Litara. Выученное в blalb после первого переноса не должно пропасть.
/// Вид: rule_choice — однократный перенос (флаг `migratedFromBlalb`) выбран сознательно, SettingsMigrationTests.swift:19–21
/// утверждает обратное этому тесту.
@Test func adversaryRenameRollbackKeepsWordsLearnedInBlalb() throws {
    let oldName = "litara-adv-\(UUID().uuidString)", newName = "litara-adv-\(UUID().uuidString)"
    let old = try #require(UserDefaults(suiteName: oldName)), new = try #require(UserDefaults(suiteName: newName))
    defer { old.removePersistentDomain(forName: oldName); new.removePersistentDomain(forName: newName) }
    old.set(["запасик", "гітхаб"], forKey: "learnedWords")
    SettingsMigration.migrate(new, from: oldName)                              // первый запуск Litara
    new.set(["запасик", "гітхаб", "літара"], forKey: "learnedWords")           // Litara выучила своё
    old.set(["запасик", "гітхаб", "бульбаш"], forKey: "learnedWords")          // откат: blalb выучил своё
    SettingsMigration.migrate(new, from: oldName)                              // снова Litara
    let words = Set(new.stringArray(forKey: "learnedWords") ?? [])
    #expect(words.contains("бульбаш"), "выученное в blalb после первого переноса пропало: \(words.sorted())")
    #expect(words.contains("літара"))
}
