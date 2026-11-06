import Foundation

/// Переезд с прежнего имени приложения (B34: blalb → Litara, `dev.blalb.app` → новый идентификатор). Состояние blalb
/// лежит не только в настройках: ещё журнал решений и запись автозапуска (её включает приложение по `migrate > 0`).
/// Прежнее не удаляется, кроме журнала, — откат к старой сборке найдёт свои настройки.
public enum SettingsMigration {
    /// Списки слов: выученные, словарь текстов, «Мои слова». Слова, которые blalb выучил уже после переезда (откат на
    /// старую сборку и обратно), добавляются к спискам Litara (решение владельца 2026-11-06).
    public static let wordLists = ["learnedWords", "vocabulary", "exceptions"]

    /// Настройки переносятся один раз, уже заданное не перезаписывается; списки слов дополняются из прежнего домена,
    /// когда он изменился с прошлого раза. Возвращает, сколько настроек перенесено при первом переезде (0 — уже
    /// переносили или переносить нечего).
    @discardableResult
    public static func migrate(_ defaults: UserDefaults, from old: String, flag: String = "migratedFromBlalb") -> Int {
        let domain = defaults.persistentDomain(forName: old) ?? [:]
        var moved = 0
        if !defaults.bool(forKey: flag) {
            for (key, value) in domain where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
                moved += 1
            }
            defaults.set(true, forKey: flag)
        }
        // ponytail: снимок списков blalb целиком (~70 тыс. слов, ~1 МБ в настройках) — по нему видно, что blalb выучил
        // с прошлого раза; забытое и удалённое в Litara в снимке уже есть и не возвращается (решение владельца
        // 2026-11-06). blalb удалён насовсем — снимок не меняется и не растёт
        for key in wordLists {
            let theirs = domain[key] as? [String] ?? [], seenKey = flag + "Seen." + key
            let seen = defaults.stringArray(forKey: seenKey) ?? []
            guard theirs != seen else { continue }
            let ours = defaults.stringArray(forKey: key) ?? []
            // без учёта регистра: «Мои слова» в приложении регистр не различают
            var skip = Set((seen + ours).map { $0.lowercased() })
            let added = theirs.filter { skip.insert($0.lowercased()).inserted }
            if !added.isEmpty { defaults.set(ours + added, forKey: key) }
            defaults.set(theirs, forKey: seenKey)
        }
        // статистика — прирост blalb с прошлого раза (решение владельца 2026-11-06): набранное при откате считается
        // за тот же срок, что и вылеты blalb. В первый переезд счётчики уже перенесены целиком — снимок только ставится
        let theirStats = domain["stats"] as? [String: Int] ?? [:], statsKey = flag + "Seen.stats"
        if let seen = defaults.dictionary(forKey: statsKey) as? [String: Int], theirStats != seen {
            var ours = defaults.dictionary(forKey: "stats") as? [String: Int] ?? [:]
            for (counter, value) in theirStats where value > seen[counter, default: 0] {
                ours[counter, default: 0] += value - seen[counter, default: 0]
            }
            defaults.set(ours, forKey: "stats")
        }
        defaults.set(theirStats, forKey: statsKey)
        return moved
    }

    /// Журнал решений под прежним именем (в нём набранные слова) переезжает к новому — личный текст не остаётся там,
    /// куда подсказка уже не ведёт. Сначала прежний файл переименовывается: если blalb ещё пишет, дальше он пишет в
    /// новый файл под прежним именем (его заберёт следующий запуск), а переименованный принадлежит только переносу.
    /// Не переименовался (нет прав) — ничего не трогается. Нового журнала нет — файл переезжает целиком; есть — строки
    /// дописываются в его конец, записанное не переписывается: не прочитался, ссылка, оборванная строка — записи
    /// Litara целы.
    public static func moveLog(from old: URL, to new: URL) {
        let files = FileManager.default, moving = old.appendingPathExtension("moving")
        // ponytail: оборвался между дописыванием и удалением — следующий запуск допишет ещё раз (окно — миллисекунды)
        if !files.fileExists(atPath: moving.path) {
            guard files.fileExists(atPath: old.path), (try? files.moveItem(at: old, to: moving)) != nil else { return }
        }
        try? files.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard files.fileExists(atPath: new.path) else { try? files.moveItem(at: moving, to: new); return }
        guard var lines = try? Data(contentsOf: moving) else { return }
        if !lines.isEmpty {
            let newline = UInt8(ascii: "\n")
            guard let handle = try? FileHandle(forUpdating: new) else { return }
            defer { try? handle.close() }
            if lines.last != newline { lines.append(newline) }
            guard let end = try? handle.seekToEnd() else { return }
            if end > 0 {
                guard (try? handle.seek(toOffset: end - 1)) != nil, let last = try? handle.read(upToCount: 1) else { return }
                if last.first != newline { lines.insert(newline, at: 0) }
            }
            guard (try? handle.write(contentsOf: lines)) != nil else { return }
        }
        try? files.removeItem(at: moving)
    }
}
