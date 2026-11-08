import Foundation
import Testing
@testable import LitaraCore

// Противник переименования blalb → Litara, раунд 2. Свои домены и временные папки; настоящие не трогаются.

private func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("litara-adv-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Новый журнал существует, но не читается (права 000): moveLog принимает ошибку чтения за «файла нет» и
/// атомарной записью заменяет его одним старым журналом — записи Litara потеряны.
/// Вид: дефект
@Test func adversaryRenameR2UnreadableNewLogIsNotReplaced() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let old = dir.appendingPathComponent("old/decisions.log"), new = dir.appendingPathComponent("new/decisions.log")
    try FileManager.default.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("old line\n".utf8).write(to: old)
    try Data("litara line\n".utf8).write(to: new)
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: new.path)
    SettingsMigration.moveLog(from: old, to: new)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: new.path)
    let text = String(decoding: (try? Data(contentsOf: new)) ?? Data(), as: UTF8.self)
    #expect(text.contains("litara line"), "записи нового журнала потеряны, в файле: \(text.debugDescription)")
}

/// Новый журнал — символическая ссылка (appendLog пишет через неё): moveLog заменяет ссылку обычным файлом,
/// цель ссылки остаётся без старых записей.
/// Вид: дефект
@Test func adversaryRenameR2SymlinkedNewLogKeepsLink() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let old = dir.appendingPathComponent("old.log"), target = dir.appendingPathComponent("target.log")
    let new = dir.appendingPathComponent("new/decisions.log")
    try FileManager.default.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("old line\n".utf8).write(to: old)
    try Data("litara line\n".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: new, withDestinationURL: target)
    SettingsMigration.moveLog(from: old, to: new)
    let text = String(decoding: (try? Data(contentsOf: target)) ?? Data(), as: UTF8.self)
    #expect(text.contains("old line"), "цель ссылки не получила старый журнал: \(text.debugDescription)")
}

/// Старый журнал оборван без перевода строки (вылет посреди записи): последняя строка склеивается с первой новой.
/// Вид: дефект
@Test func adversaryRenameR2OldLogWithoutNewlineDoesNotGlueLines() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let old = dir.appendingPathComponent("old.log"), new = dir.appendingPathComponent("new/decisions.log")
    try FileManager.default.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("2026-01-01T00:00:00Z слово-оборв".utf8).write(to: old)
    try Data("2026-02-02T00:00:00Z новая\n".utf8).write(to: new)
    SettingsMigration.moveLog(from: old, to: new)
    let lines = String(decoding: try Data(contentsOf: new), as: UTF8.self).split(separator: "\n")
    #expect(lines.count == 2, "строки склеились: \(lines)")
}

/// «Забыть выученные» в Litara, затем откат на blalb, где выучено одно слово: возвращаются все слова, забытые
/// в Litara, и слово, удалённое из «Моих слов». Данные не различают «удалил в Litara» и «никогда не было».
/// Вид: rule_choice — нет входа «когда удалено»; варианты: (а) как сейчас — воскресает всё прежнее, цена: забытое
/// возвращается без спроса; (б) хранить в Litara список удалённых слов — цена: ещё один ключ и его рост;
/// (в) добавлять только слова, которых не было в прежнем снимке — цена: снимок слов вместо отпечатка.
@Test func adversaryRenameR2ForgottenWordsStayForgotten() throws {
    let oldName = temporaryDefaultsName("old"), newName = temporaryDefaultsName("new")
    let old = try #require(UserDefaults(suiteName: oldName)), new = try #require(UserDefaults(suiteName: newName))
    defer { removeTemporaryDefaults(oldName, newName) }
    old.set(["один", "два"], forKey: "learnedWords")
    old.set(["ZUS", "GPT"], forKey: "exceptions")
    SettingsMigration.migrate(new, from: oldName)
    new.set([String](), forKey: "learnedWords")               // «Забыть выученные»
    new.set(["GPT"], forKey: "exceptions")                    // удалил ZUS из «Моих слов»
    old.set(["один", "два", "три"], forKey: "learnedWords")   // blalb выучил одно слово
    SettingsMigration.migrate(new, from: oldName)
    let learned = new.stringArray(forKey: "learnedWords") ?? []
    let exceptions = new.stringArray(forKey: "exceptions") ?? []
    #expect(!learned.contains("один") && !learned.contains("два"), "забытые слова вернулись: \(learned)")
    #expect(!exceptions.contains("ZUS"), "удалённое из «Моих слов» вернулось: \(exceptions)")
}
