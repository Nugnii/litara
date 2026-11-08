import Foundation
import Testing
@testable import LitaraCore

// Противник переименования blalb → Litara, раунд 3. Свои домены и временные папки; настоящие не трогаются.

private func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("litara-adv-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func occurrences(_ needle: String, in text: String) -> Int {
    text.components(separatedBy: needle).count - 1
}

/// Прежний журнал дописан к новому, но удалить его не вышло (папка blalb без права записи, файл с флагом uchg): moveLog
/// оставляет его «до следующего запуска» — и следующий запуск дописывает те же строки ещё раз. Каждый запуск Litara —
/// ещё одна копия журнала blalb.
/// Вид: дефект (проверка починки 42987fa)
@Test func adversaryRenameR3UndeletableOldLogIsNotAppendedTwice() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let oldDir = dir.appendingPathComponent("blalb"), new = dir.appendingPathComponent("Litara/decisions.log")
    let old = oldDir.appendingPathComponent("decisions.log")
    try FileManager.default.createDirectory(at: oldDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("2026-10-30T10:00:00Z строка blalb\n".utf8).write(to: old)
    try Data("2026-11-06T10:00:00Z строка Litara\n".utf8).write(to: new)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: oldDir.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: oldDir.path) }
    SettingsMigration.moveLog(from: old, to: new)  // запуск 1
    SettingsMigration.moveLog(from: old, to: new)  // запуск 2
    SettingsMigration.moveLog(from: old, to: new)  // запуск 3
    let text = String(decoding: try Data(contentsOf: new), as: UTF8.self)
    // починка (передача переименованием): прежний файл не переименовать — перенос его не трогает; строки не
    // повторяются, прежний журнал цел и переедет, когда папка станет доступна
    #expect(occurrences("строка blalb", in: text) <= 1, "строка blalb в журнале Litara \(occurrences("строка blalb", in: text)) раз: \(text.debugDescription)")
    #expect(FileManager.default.fileExists(atPath: old.path) || occurrences("строка blalb", in: text) == 1)
}

/// Прежний журнал пуст (владелец стёр содержимое вместо удаления файла — подсказка «выключите и удалите»): строк в нём
/// нет, а к журналу Litara дописывается пустая строка без отметки времени.
/// Вид: дефект
@Test func adversaryRenameR3EmptyOldLogAddsNoBlankLine() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let old = dir.appendingPathComponent("blalb/decisions.log"), new = dir.appendingPathComponent("Litara/decisions.log")
    try FileManager.default.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: old)
    try Data("2026-11-06T10:00:00Z строка Litara\n".utf8).write(to: new)
    SettingsMigration.moveLog(from: old, to: new)
    let text = String(decoding: try Data(contentsOf: new), as: UTF8.self)
    #expect(text == "2026-11-06T10:00:00Z строка Litara\n", "журнал Litara после пустого журнала blalb: \(text.debugDescription)")
}

/// blalb запущен (оба приложения живы: автозапуск blalb после отката) и пишет журнал, пока Litara при запуске переносит
/// его: строки, дописанные blalb между чтением и удалением прежнего файла, пропадают — их нет ни в новом журнале,
/// ни в прежнем. Писатель повторяет Settings.appendLog: открыть, в конец, записать, закрыть; нет файла — создать.
/// Вид: дефект
@Test func adversaryRenameR3BlalbWritingDuringMoveLosesNoLines() throws {
    final class Writer: @unchecked Sendable {
        let lock = NSLock()
        var stop = false, written = 0
    }
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let old = dir.appendingPathComponent("blalb/decisions.log"), new = dir.appendingPathComponent("Litara/decisions.log")
    try FileManager.default.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
    // журнал blalb за недели отладки
    try Data(String(repeating: "2026-10-21T10:00:00Z выучено на наборе: «слово»\n", count: 300_000).utf8).write(to: old)
    try Data("2026-11-06T10:00:00Z строка Litara\n".utf8).write(to: new)
    let writer = Writer(), done = DispatchSemaphore(value: 0)
    let oldPath = old
    DispatchQueue.global().async {
        var i = 0
        while !writer.lock.withLock({ writer.stop }) {
            let data = Data("2026-11-06T10:00:01Z blalb-\(i)-конец\n".utf8)
            if let handle = try? FileHandle(forWritingTo: oldPath) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: oldPath)
            }
            i += 1
            writer.lock.withLock { writer.written = i }
        }
        done.signal()
    }
    while writer.lock.withLock({ writer.written }) < 50 { usleep(100) }
    SettingsMigration.moveLog(from: old, to: new)
    usleep(20_000)
    writer.lock.withLock { writer.stop = true }
    done.wait()
    let count = writer.lock.withLock { writer.written }
    let text = String(decoding: try Data(contentsOf: new), as: UTF8.self)
        + String(decoding: (try? Data(contentsOf: old)) ?? Data(), as: UTF8.self)
    let present = Set(text.split(separator: "\n").filter { $0.hasSuffix("-конец") }.map(String.init))
    let lost = (0..<count).filter { !present.contains("2026-11-06T10:00:01Z blalb-\($0)-конец") }
    let none = lost.isEmpty
    #expect(none, "из \(count) строк blalb пропало \(lost.count): первая \(lost.first ?? -1), последняя \(lost.last ?? -1)")
}

/// «Мои слова» — без учёта регистра (TypingSession.exceptions строчными; Sources/Litara/AppDelegate.swift:378 и импорт
/// Punto в SettingsView.swift:237 не добавляют слово, если оно есть в другом регистре). В Litara после переезда добавлено
/// «ZUS»; в blalb (откат) того же слова нет — три отката «zus» добавляют «zus». Возврат на Litara: «Мои слова» — «ZUS»
/// и «zus», две строки одного слова.
/// Вид: дефект
@Test func adversaryRenameR3ExceptionDifferingByCaseIsNotDuplicated() throws {
    let oldName = temporaryDefaultsName("old"), newName = temporaryDefaultsName("new")
    let old = try #require(UserDefaults(suiteName: oldName)), new = try #require(UserDefaults(suiteName: newName))
    defer { removeTemporaryDefaults(oldName, newName) }
    old.set(["GPT"], forKey: "exceptions")
    SettingsMigration.migrate(new, from: oldName)
    new.set(["GPT", "ZUS"], forKey: "exceptions")   // добавил в Litara
    old.set(["GPT", "zus"], forKey: "exceptions")   // blalb после трёх откатов
    SettingsMigration.migrate(new, from: oldName)
    let exceptions = new.stringArray(forKey: "exceptions") ?? []
    #expect(exceptions.filter { $0.lowercased() == "zus" }.count == 1, "«Мои слова»: \(exceptions)")
}

/// Файл слов, выгруженный Litara, — blalb 0.28.0 (откат; или другой человек на blalb 0.28.0, B28) его не примет:
/// там `decode` требует `format == "blalb-learned-words"` (git show 802d2d2:Sources/BlalbCore/LearnedWordsFile.swift:24).
/// Litara старый формат читает, старый blalb новый — нет.
/// Вид: rule_choice — нет входа «кто будет читать файл». Решение владельца 2026-11-06 (вопрос с пунктами): как сейчас —
/// blalb заменяется Litara, файл Litara — `litara-learned-words`, файлы blalb Litara принимает. Тест закрепляет правило.
@Test func adversaryRenameR3LitaraExportReadableByBlalb() throws {
    let data = try LearnedWordsFile.encode(["слово"])
    let format = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["format"] as? String
    #expect(format == "litara-learned-words")
    let legacy = Data(#"{"format": "blalb-learned-words", "version": 1, "words": ["слово"]}"#.utf8)
    #expect(LearnedWordsFile.decode(legacy) == ["слово"])
}

/// Статистика «с <даты>» (SettingsView.swift:340–352) после отката и возврата: вылеты blalb за время отката считаются
/// (Settings.crashCount — «и отчёты прежнего имени»), а слова и исправления, набранные в blalb за то же время, — нет:
/// `stats` переносится один раз. Счётчики за один и тот же период взяты из разных источников.
/// Вид: rule_choice (проверка починки 3af024e — тот же класс «сделанное в blalb после переезда», вход — статистика) —
/// нет входа «сколько было у blalb в момент переезда»; варианты: (а) как сейчас — набранное при откате пропадает из
/// статистики, цена: «слов с 21 октября» меньше, чем набрано, при вылетах за весь срок; (б) снимок `stats` blalb при
/// переезде и добавление прироста, цена: ещё один ключ; (в) не считать вылеты blalb после переезда, цена: правка
/// crashCount и потеря вылетов blalb за время отката.
@Test func adversaryRenameR3StatsTypedInBlalbAfterMoveAreCounted() throws {
    let oldName = temporaryDefaultsName("old"), newName = temporaryDefaultsName("new")
    let old = try #require(UserDefaults(suiteName: oldName)), new = try #require(UserDefaults(suiteName: newName))
    defer { removeTemporaryDefaults(oldName, newName) }
    old.set(["words": 1000, "autoSwitches": 100], forKey: "stats")
    SettingsMigration.migrate(new, from: oldName)
    new.set(["words": 1500, "autoSwitches": 150], forKey: "stats")   // набрал в Litara
    old.set(["words": 1300, "autoSwitches": 130], forKey: "stats")   // откат: набрал в blalb
    SettingsMigration.migrate(new, from: oldName)                    // вернулся на Litara
    let stats = new.dictionary(forKey: "stats") as? [String: Int] ?? [:]
    #expect(stats["words"] == 1800, "слов в статистике Litara: \(stats["words"] ?? -1), набрано с начала счёта 1800")
}
