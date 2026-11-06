import AppKit
import LitaraCore
import Foundation
import ServiceManagement

/// Настройки Litara (UserDefaults).
enum Settings {
    /// Языки, в которых Litara исправляет; `nil` — ещё не выбирали: берутся включённые в macOS.
    static var languages: Set<Language>? {
        get { UserDefaults.standard.stringArray(forKey: "languages").map { Set($0.compactMap(Language.init(rawValue:))) } }
        set { UserDefaults.standard.set(newValue.map { $0.map(\.rawValue).sorted() }, forKey: "languages") }
    }

    /// Язык интерфейса; `nil` — как в системе.
    static var interfaceLanguage: Language? {
        get { UserDefaults.standard.string(forKey: "interfaceLanguage").flatMap(Language.init(rawValue:)) }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: "interfaceLanguage") }
    }

    static var autoDetect: Bool {
        get { UserDefaults.standard.object(forKey: "autoDetect") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoDetect") }
    }

    /// «Исправлять опечатки» — по умолчанию выключено (решение владельца В31): включается, когда замер
    /// покажет, что ложных исправлений нет.
    static var correctTypos: Bool {
        get { UserDefaults.standard.bool(forKey: "correctTypos") }
        set { UserDefaults.standard.set(newValue, forKey: "correctTypos") }
    }

    /// Короткий щелчок при автоисправлении (docs/spec.md: по умолчанию выключен).
    static var clickSound: Bool {
        get { UserDefaults.standard.bool(forKey: "clickSound") }
        set { UserDefaults.standard.set(newValue, forKey: "clickSound") }
    }

    /// Системный звук «Tink» — самый короткий щелчок из звуков macOS.
    @MainActor static func playClick() { NSSound(named: "Tink")?.play() }

    /// Флажки на значке вместо букв (docs/spec.md; RU — всегда буквами).
    /// Проверка обновлений раз в день (B33). Хранит Sparkle под своим ключом; по умолчанию — из Info.plist (включена).
    static var autoUpdate: Bool { UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") as? Bool ?? true }

    static var showFlags: Bool {
        get { UserDefaults.standard.bool(forKey: "showFlags") }
        set { UserDefaults.standard.set(newValue, forKey: "showFlags") }
    }

    /// «Заменить стандартный переключатель»: значок раскладки macOS скрыт, пока Litara запущен.
    static var replaceSystemSwitcher: Bool {
        get { UserDefaults.standard.bool(forKey: "replaceSystemSwitcher") }
        set { UserDefaults.standard.set(newValue, forKey: "replaceSystemSwitcher") }
    }

    /// Значок раскладки macOS в строке меню: настройка `com.apple.TextInputMenu visible`, её читает
    /// `TextInputMenuAgent` при запуске — агент перезапускается (launchd поднимает его сам).
    static func setSystemInputMenuVisible(_ visible: Bool) {
        UserDefaults(suiteName: "com.apple.TextInputMenu")?.set(visible, forKey: "visible")
        try? Process.run(URL(fileURLWithPath: "/usr/bin/killall"), arguments: ["TextInputMenuAgent"])
    }

    /// Выбранный вариант раскладки языка (docs/spec.md); нет — первая включённая в macOS.
    static var layoutVariants: [Language: String] {
        get {
            let stored = UserDefaults.standard.dictionary(forKey: "layoutVariants") as? [String: String] ?? [:]
            return Dictionary(uniqueKeysWithValues: stored.compactMap { key, id in Language(rawValue: key).map { ($0, id) } })
        }
        set { UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.rawValue, $0.value) }), forKey: "layoutVariants") }
    }

    /// Раскладки, которые добавил в macOS сам Litara (включённый язык без раскладки). Снятый язык
    /// убирает из системы только их: раскладки, бывшие до Litara, остаются — иначе одна галочка на
    /// английском оставила бы без латиницы (и без ввода пароля).
    static var addedLayouts: [String] {
        get { UserDefaults.standard.stringArray(forKey: "addedLayouts") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "addedLayouts") }
    }

    /// Приложения, где Litara сам ничего не исправляет (bundle id; хоткеи там работают).
    static var disabledApps: [String] {
        get { UserDefaults.standard.stringArray(forKey: "disabledApps") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "disabledApps") }
    }

    /// Слова, которые не исправляются никогда (ZUS, GPT, /save).
    static var exceptions: [String] {
        get { UserDefaults.standard.stringArray(forKey: "exceptions") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "exceptions") }
    }

    /// Свои замены: сокращение → текст (docs/spec.md).
    static var replacements: [Replacement] {
        get {
            if let rows = UserDefaults.standard.array(forKey: "replacementRules") as? [[String: Any]] {
                return rows.compactMap { row in
                    (row["what"] as? String).map { Replacement(what: $0, with: row["with"] as? String ?? "", ignoreCase: row["ignoreCase"] as? Bool ?? false) }
                }
            }
            // до 0.13.0 — словарь «сокращение → текст», регистр тогда не учитывался
            let old = UserDefaults.standard.dictionary(forKey: "replacements") as? [String: String] ?? [:]
            return old.sorted { $0.key < $1.key }.map { Replacement(what: $0.key, with: $0.value, ignoreCase: true) }
        }
        set {
            UserDefaults.standard.set(newValue.map { ["what": $0.what, "with": $0.with, "ignoreCase": $0.ignoreCase] }, forKey: "replacementRules")
        }
    }

    /// Запоминание исправлений (docs/spec.md): после 3 откатов слова — уведомление «не исправлять».
    static var rememberRollbacks: Bool {
        get { UserDefaults.standard.object(forKey: "rememberRollbacks") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "rememberRollbacks") }
    }

    /// Назначенные хоткеи (docs/spec.md: все назначаются в настройках).
    static var hotkeys: [HotkeyAction: Hotkey] {
        Dictionary(uniqueKeysWithValues: HotkeyAction.allCases.compactMap { action in
            UserDefaults.standard.hotkey(action).map { (action, $0) }
        })
    }

    static func setHotkey(_ hotkey: Hotkey?, for action: HotkeyAction) {
        UserDefaults.standard.setHotkey(hotkey, for: action)
    }

    /// Подпись хоткея; клавиша — как в латинской раскладке ABC: при русской было бы «⌘Д» вместо «⌘L».
    @MainActor static func label(_ hotkey: Hotkey) -> String {
        hotkey.label(key: hotkey.code.map { keyNames[$0] ?? "#\($0)" } ?? "")
    }

    // ponytail: клавиши без символа, кроме этих четырёх (стрелки, F1…), подписаны кодом — «#123»
    @MainActor private static let keyNames: [UInt16: String] = {
        let abc = KeyboardLayout.available().first { $0.id == "com.apple.keylayout.ABC" }
        var names = Dictionary(abc?.chars.filter { !$0.key.shift && !$0.key.option }.map { ($0.key.code, $0.value.uppercased()) } ?? [],
                               uniquingKeysWith: { a, _ in a })
        names.merge([49: "Space", 36: "↩", 48: "⇥", 51: "⌫"]) { _, special in special }
        return names
    }()

    /// Статистика (docs/spec.md: как у Punto, только на этом Mac) — копится с `statsSince`.
    static var stats: TypingStats {
        get { TypingStats(UserDefaults.standard.dictionary(forKey: "stats") as? [String: Int] ?? [:]) }
        set { UserDefaults.standard.set(newValue.dictionary, forKey: "stats") }
    }

    static var statsSince: Date {
        get { UserDefaults.standard.object(forKey: "statsSince") as? Date ?? Date() }
        set { UserDefaults.standard.set(newValue, forKey: "statsSince") }
    }

    /// Вылеты Litara с `since`: отчёты macOS `~/Library/Logs/DiagnosticReports/Litara-….ips` (и в Retired).
    static func crashCount(since: Date) -> Int {
        let reports = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
        return [reports, reports.appendingPathComponent("Retired")].reduce(0) { count, folder in
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            return count + files.filter { url in
                // и отчёты прежнего имени — статистика идёт с 21 октября, до переименования (B34)
                (url.lastPathComponent.hasPrefix("Litara-") || url.lastPathComponent.hasPrefix("blalb-")) && url.pathExtension == "ips"
                    && ((try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >= since
            }.count
        }
    }

    /// Сколько раз откатывали исправление слова (строчными).
    static var rollbackCounts: [String: Int] {
        get { UserDefaults.standard.dictionary(forKey: "rollbackCounts") as? [String: Int] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "rollbackCounts") }
    }

    /// Слова, выученные из текстов (переписка Telegram, .txt) — часть своего словаря.
    /// Знакомые слова из текстов: промах по соседней клавише исправляется только в них (решение владельца 2026-10-21).
    static var vocabulary: [String] {
        get { UserDefaults.standard.stringArray(forKey: "vocabulary") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "vocabulary") }
    }

    static var learnedWords: [String] {
        get { UserDefaults.standard.stringArray(forKey: "learnedWords") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "learnedWords") }
    }

    static var logDecisions: Bool {
        get { UserDefaults.standard.bool(forKey: "logDecisions") }
        set { UserDefaults.standard.set(newValue, forKey: "logDecisions") }
    }

    /// Журнал решений — только на этом Mac.
    static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Litara/decisions.log")

    /// Переезд с прежнего имени (B34, `SettingsMigration`): настройки, слова и журнал blalb (`dev.blalb.app`) — в Litara.
    /// При первом переезде включается запуск при входе: у Litara своя запись, а включён ли он был у blalb, macOS
    /// не говорит (решение владельца 2026-11-06 — включать).
    static func migrateFromBlalb() {
        // blalb — та же программа под прежним именем (его автозапуск Litara снять не может): два перехвата исправляли бы
        // каждое слово дважды — Litara просит его завершиться, как «Выйти» в его меню (решение владельца 2026-11-06)
        NSRunningApplication.runningApplications(withBundleIdentifier: "dev.blalb.app").forEach { $0.terminate() }
        if SettingsMigration.migrate(.standard, from: "dev.blalb.app") > 0 { try? SMAppService.mainApp.register() }
        SettingsMigration.moveLog(from: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/blalb/decisions.log"), to: logURL)
    }

    static func appendLog(_ line: String) {
        let url = logURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
        let data = Data("\(stamp) \(line)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    /// Текст для обучения: экспорт Telegram Desktop (result.json) — личное и общие чаты порознь — либо обычный
    /// текстовый файл (как личное).
    static func text(from url: URL) -> (personal: String, group: String) {
        guard let data = try? Data(contentsOf: url) else { return ("", "") }
        if url.pathExtension.lowercased() == "json", let text = TextExtraction.telegramText(from: data) { return text }
        return (String(decoding: data, as: UTF8.self), "")
    }

    /// Первый запуск пройден — окно приветствия закрыто «Готово».
    static var welcomed: Bool {
        get { UserDefaults.standard.bool(forKey: "welcomed") }
        set { UserDefaults.standard.set(newValue, forKey: "welcomed") }
    }

    /// Хоткеи Punto Switcher по действиям Litara; пусто — Punto не найден или в нём ничего не назначено.
    static func puntoHotkeys() -> [HotkeyAction: Hotkey] {
        guard let punto = UserDefaults(suiteName: "ru.yandex.punto") else { return [:] }
        var result: [HotkeyAction: Hotkey] = [:]
        for action in HotkeyAction.allCases {
            if let key = action.puntoKey, let stored = punto.dictionary(forKey: key), let hotkey = Hotkey(punto: stored) {
                result[action] = hotkey
            }
        }
        return result
    }

    /// Исключения Punto Switcher: правила пользователя и выученные отмены. Пусто — Punto не найден.
    static func puntoExceptions() -> [String] {
        guard let punto = UserDefaults(suiteName: "ru.yandex.punto") else { return [] }
        let rules = (punto.array(forKey: "userRulesDictionary") ?? []).compactMap { ($0 as? [Any])?.first as? String }
        let learned = ((punto.dictionary(forKey: "undoLearning")?["undoDictionary"]) as? [String: Any])?.keys.sorted() ?? []
        var seen = Set<String>()
        return (rules + learned).filter { seen.insert($0.lowercased()).inserted }
    }
}

extension Language {
    /// Буквы на значке (docs/spec.md: RU, BY, UA, EN, PL).
    var code: String {
        switch self {
        case .ru: "RU"
        case .be: "BY"
        case .uk: "UA"
        case .en: "EN"
        case .pl: "PL"
        }
    }

    /// Флажок для значка (docs/spec.md, решение владельца 2026-11-06) зависит от языка интерфейса: при белорусском
    /// и украинском RU — флаг Мордора, BY — бел-чырвона-белы; при остальных RU — триколор, BY — флаг РБ. EN — США,
    /// UA, PL — свои. Рисуется полосами: эмодзи 🇧🇾 — другой флаг, а одинаковый плоский вид у всех.
    var flag: NSImage? {
        let free = [Language.be, .uk].contains(L10n.current)
        let red = NSColor(srgbRed: 0.784, green: 0.192, blue: 0.243, alpha: 1)
        // полосы сверху вниз; у США — ещё синий крыж, у Мордора — Око, у РБ — орнамент у древка
        let stripes: [NSColor]
        switch self {
        case .ru: stripes = free ? [.black]
            : [.white, NSColor(srgbRed: 0, green: 0.224, blue: 0.651, alpha: 1), NSColor(srgbRed: 0.835, green: 0.169, blue: 0.118, alpha: 1)]
        case .be: stripes = free ? [.white, red, .white] : [red, red, NSColor(srgbRed: 0.29, green: 0.651, blue: 0.341, alpha: 1)]
        case .uk: stripes = [NSColor(srgbRed: 0, green: 0.341, blue: 0.718, alpha: 1), NSColor(srgbRed: 1, green: 0.843, blue: 0, alpha: 1)]
        case .pl: stripes = [.white, NSColor(srgbRed: 0.863, green: 0.078, blue: 0.235, alpha: 1)]
        case .en:
            let red = NSColor(srgbRed: 0.698, green: 0.133, blue: 0.204, alpha: 1)
            stripes = (0..<13).map { $0.isMultiple(of: 2) ? red : .white }
        }
        let image = NSImage(size: NSSize(width: 20, height: 14), flipped: true) { rect in
            let clip = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
            clip.addClip()
            let height = rect.height / CGFloat(stripes.count)
            // каждая полоса — от своего верха до низа, следующая ложится поверх: на стыке одинаковых полос (красные у
            // РБ) иначе виден шов сглаживания
            for (i, color) in stripes.enumerated() {
                color.setFill()
                rect.divided(atDistance: height * CGFloat(i), from: .minYEdge).remainder.fill()
            }
            if self == .en {
                NSColor(srgbRed: 0.235, green: 0.231, blue: 0.431, alpha: 1).setFill()
                NSRect(x: 0, y: 0, width: rect.width * 0.4, height: height * 7).fill()
            }
            if self == .be, !free {
                // ponytail: орнамент РБ — столбик красных ромбов на белой полосе в 1/9 длины; узор на 20×14 не различить
                let strip = rect.width / 9
                NSColor.white.setFill()
                NSRect(x: 0, y: 0, width: strip, height: rect.height).fill()
                red.setFill()
                let step = rect.height / 5
                for i in 0..<5 {
                    let diamond = NSBezierPath(), y = step * CGFloat(i), mid = strip / 2
                    diamond.move(to: NSPoint(x: mid, y: y))
                    diamond.line(to: NSPoint(x: strip * 0.9, y: y + step / 2))
                    diamond.line(to: NSPoint(x: mid, y: y + step))
                    diamond.line(to: NSPoint(x: strip * 0.1, y: y + step / 2))
                    diamond.fill()
                }
            }
            if self == .ru, free {
                // ponytail: Око без завитков исходника (Викисклад, Flag_of_Mordor_SVG.svg) — на 20×14 их не видно
                let (w, h) = (rect.width, rect.height)
                let lens = NSBezierPath()
                lens.move(to: NSPoint(x: w * 0.2, y: h * 0.5))
                lens.curve(to: NSPoint(x: w * 0.8, y: h * 0.5),
                           controlPoint1: NSPoint(x: w * 0.38, y: h * 0.15), controlPoint2: NSPoint(x: w * 0.62, y: h * 0.15))
                lens.curve(to: NSPoint(x: w * 0.2, y: h * 0.5),
                           controlPoint1: NSPoint(x: w * 0.62, y: h * 0.85), controlPoint2: NSPoint(x: w * 0.38, y: h * 0.85))
                NSColor(srgbRed: 0.663, green: 0, blue: 0, alpha: 1).setFill()
                lens.fill()
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: w * 0.41, y: h * 0.31, width: w * 0.18, height: h * 0.38)).fill()
            }
            // белые полосы на светлой строке меню иначе сливаются с фоном; чёрное полотно Мордора — с тёмным меню, и
            // флажок кажется меньше остальных (проба владельца 2026-11-06) — у него рамка светлая
            (self == .ru && free ? NSColor.white.withAlphaComponent(0.5) : NSColor.gray.withAlphaComponent(0.6)).setStroke()
            clip.lineWidth = 1
            clip.stroke()
            return true
        }
        image.accessibilityDescription = code
        return image
    }

    /// Название языка на нём самом — понятно при любом языке интерфейса.
    var nativeName: String {
        switch self {
        case .ru: "Русский"
        case .be: "Беларуская"
        case .uk: "Українська"
        case .en: "English"
        case .pl: "Polski"
        }
    }

    /// Раскладка, которую Litara добавляет в macOS, если у языка её нет (docs/spec.md: ПК-варианты).
    var defaultLayoutID: String {
        switch self {
        case .ru: "com.apple.keylayout.RussianWin"
        case .be: "com.apple.keylayout.Byelorussian"
        case .uk: "com.apple.keylayout.Ukrainian-PC"
        case .en: "com.apple.keylayout.ABC"
        case .pl: "com.apple.keylayout.PolishPro"
        }
    }
}
