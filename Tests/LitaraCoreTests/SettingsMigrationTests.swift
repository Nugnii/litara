import Foundation
import Testing
@testable import LitaraCore

@Test func settingsMigrateFromOldIdentifier() throws {
    // B34: при переименовании blalb → Litara настройки, выученные слова и статистика лежат под прежним идентификатором
    // (dev.blalb.app) — переносятся один раз; уже заданное в Litara не перезаписывается
    let oldName = "litara-test-old-\(UUID().uuidString)", newName = "litara-test-new-\(UUID().uuidString)"
    let old = try #require(UserDefaults(suiteName: oldName)), new = try #require(UserDefaults(suiteName: newName))
    defer { old.removePersistentDomain(forName: oldName); new.removePersistentDomain(forName: newName) }
    old.set(["запасик", "гітхаб"], forKey: "learnedWords")
    old.set("be", forKey: "interfaceLanguage")
    old.set(true, forKey: "logDecisions")
    new.set("en", forKey: "interfaceLanguage")  // уже выбрано в Litara — остаётся
    #expect(SettingsMigration.migrate(new, from: oldName) == 2)
    #expect(new.stringArray(forKey: "learnedWords") == ["запасик", "гітхаб"])
    #expect(new.bool(forKey: "logDecisions"))
    #expect(new.string(forKey: "interfaceLanguage") == "en")
    // второй раз настройки не переносятся, а слова, выученные blalb после переезда (откат и возврат), дописываются
    old.set(["запасик", "гітхаб", "новое"], forKey: "learnedWords")
    old.set(false, forKey: "logDecisions")
    #expect(SettingsMigration.migrate(new, from: oldName) == 0)
    #expect(new.stringArray(forKey: "learnedWords") == ["запасик", "гітхаб", "новое"])
    #expect(new.bool(forKey: "logDecisions"))
    // забытое в Litara не возвращается, пока blalb свои списки не менял
    new.set(["новое"], forKey: "learnedWords")
    SettingsMigration.migrate(new, from: oldName)
    #expect(new.stringArray(forKey: "learnedWords") == ["новое"])
}

@Test func decisionLogMovesFromOldName() throws {
    // B34: журнал blalb (в нём набранные слова) переезжает к журналу Litara, прежний файл удаляется
    let files = FileManager.default
    let dir = files.temporaryDirectory.appendingPathComponent("litara-log-\(UUID().uuidString)")
    defer { try? files.removeItem(at: dir) }
    let old = dir.appendingPathComponent("blalb/decisions.log"), new = dir.appendingPathComponent("Litara/decisions.log")
    try files.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("старое\n".utf8).write(to: old)
    SettingsMigration.moveLog(from: old, to: new)
    #expect(try String(contentsOf: new, encoding: .utf8) == "старое\n")
    #expect(!files.fileExists(atPath: old.path))
    // blalb писал снова (откат) — его строки дописываются в конец, записанное Litara не переписывается
    try Data("ещё".utf8).write(to: old)
    try Data("старое\nновое".utf8).write(to: new)
    SettingsMigration.moveLog(from: old, to: new)
    #expect(try String(contentsOf: new, encoding: .utf8) == "старое\nновое\nещё\n")
    SettingsMigration.moveLog(from: old, to: new)  // прежнего нет — ничего не меняется
    #expect(try String(contentsOf: new, encoding: .utf8) == "старое\nновое\nещё\n")
}
