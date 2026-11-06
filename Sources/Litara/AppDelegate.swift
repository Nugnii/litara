import AppKit
import LitaraCore
import Carbon
import SwiftUI
import Sparkle
@preconcurrency import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem?
    /// Обновления (B33): стандартное окно Sparkle, раз в день. Без адреса ленты (сборка не через bundle.sh) не стартует —
    /// иначе Sparkle при запуске показывает ошибку.
    /// ponytail: без «мягких напоминаний» Sparkle для фоновых программ — окно обновления может открыться за другими
    /// окнами; заметит владелец — добавить SPUStandardUserDriverDelegate (точка на значке).
    private let updater = SPUStandardUpdaterController(
        startingUpdater: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil, updaterDelegate: nil, userDriverDelegate: nil)
    private var monitor: KeyboardMonitor?
    private var permissionTimer: Timer?
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private var pendingRestart: DispatchWorkItem?
    private var secureInput = false
    private var secureInputTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // до первого чтения настроек; копия с другим id (снимки окон, проба) не переезжает — переезд закрыл бы рабочий
        // blalb и забрал его настройки и журнал
        if Bundle.main.bundleIdentifier == "io.github.nugnii.litara" { Settings.migrateFromBlalb() }
        // уведомление «больше не исправляется» после 3 откатов слова (docs/spec.md) — и при Litara впереди
        UNUserNotificationCenter.current().delegate = self
        // выученная раньше латиница уходит: учим только кириллицу (решение владельца 2026-10-21)
        Settings.learnedWords = Settings.learnedWords.filter { !LanguageDetector.isLatin($0) }
        if Settings.replaceSystemSwitcher { Settings.setSystemInputMenuVisible(false) }
        // установки до окна приветствия (≤ 0.11.0) его не видят: ⌘L был умолчанием регистра у всех и
        // остаётся у них явно, новым пользователям регистр без сочетания (docs/spec.md, BACKLOG B3)
        if !Settings.welcomed, UserDefaults.standard.object(forKey: "statsSince") != nil || Settings.languages != nil {
            if UserDefaults.standard.object(forKey: "changeCaseHotkey") == nil {
                Settings.setHotkey(Hotkey(code: 37, flags: Hotkey.command), for: .changeCase)
            }
            Settings.welcomed = true
        }
        let firstLaunch = !Settings.welcomed
        if firstLaunch || CommandLine.arguments.contains("--welcome") { DispatchQueue.main.async { self.openWelcome() } }
        if UserDefaults.standard.object(forKey: "statsSince") == nil { Settings.statsSince = Date() }
        // `--settings` при запуске сразу открывает настройки (и для проверки окна)
        if CommandLine.arguments.contains("--settings") { DispatchQueue.main.async { self.openSettings() } }
        // ⌘V, ⌘C, ⌘X, ⌘A, ⌘Z поля ввода получают через пункты меню «Правка». У приложения без Dock меню нет,
        // и в «Моих словах» вставка не работала (проба владельца 2026-10-21); строки меню не видно, сочетания —
        // работают
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z").keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        NSApp.mainMenu = NSMenu()
        NSApp.mainMenu?.addItem(NSMenuItem())  // первый пункт — меню приложения
        NSApp.mainMenu?.addItem(editItem)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        item.button?.title = "…"
        item.button?.imagePosition = .imageLeading  // флажок и замок рядом
        statusItem = item
        // защищённый ввод (поле пароля, и забытое в фоне) глушит Litara — видно замком (B18).
        // ponytail: опрос раз в 2 с — macOS о защищённом вводе не уведомляет
        secureInputTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard IsSecureEventInputEnabled() != self.secureInput else { return }
                self.secureInput.toggle()
                if self.monitor != nil { self.show(self.monitor?.current) }
            }
        }

        // Перехват и подмена нажатий требуют «Универсального доступа»; без него ждём, пока его дадут.
        // строка — значение kAXTrustedCheckOptionPrompt: сама глобальная константа в Swift 6 не потокобезопасна
        // при первом запуске доступ объясняет окно приветствия — системный запрос поверх него лишний
        let prompt = ["AXTrustedCheckOptionPrompt": !firstLaunch] as CFDictionary
        if AXIsProcessTrustedWithOptions(prompt) {
            startMonitor()
        } else {
            item.button?.title = "Litara ⚠︎"
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                MainActor.assumeIsolated {
                    guard AXIsProcessTrusted() else { return }
                    self.permissionTimer?.invalidate()
                    self.startMonitor()
                }
            }
        }
        // откаты, трижды оставшиеся без ответа на прежний вопрос с кнопками, — запомнить сейчас (B13)
        for (word, count) in Settings.rollbackCounts where count >= 3 { rolledBack(word) }
    }

    // без Litara индикатор раскладки нужен — системный значок возвращается
    func applicationWillTerminate(_ notification: Notification) {
        if Settings.replaceSystemSwitcher { Settings.setSystemInputMenuVisible(true) }
    }

    private func startMonitor() {
        monitor?.stop()
        let allowed = Settings.languages ?? KeyboardMonitor.systemLanguages()
        guard let monitor = KeyboardMonitor(allowed: allowed, preferred: Settings.layoutVariants, autoCorrect: Settings.autoDetect,
                                            exceptions: Settings.exceptions, learned: Settings.learnedWords,
                                            vocabulary: Settings.vocabulary) else {
            statusItem?.button?.title = "Litara ✕"
            return
        }
        monitor.correctTypos = Settings.correctTypos
        monitor.replacements = Settings.replacements
        monitor.disabledApps = Set(Settings.disabledApps)
        monitor.hotkeys = Settings.hotkeys
        monitor.onRollback = { [weak self] word in self?.rolledBack(word) }
        monitor.onToggleAutoCorrect = { [weak self] in self?.setAutoCorrect(!Settings.autoDetect) }
        monitor.onLearned = { words in
            Settings.vocabulary = Array(Set(Settings.vocabulary + words)).sorted()
            if Settings.logDecisions { words.forEach { Settings.appendLog("выучено на наборе: «\($0)»") } }
        }
        monitor.onStats = { stats in
            Settings.stats = Settings.stats + stats
            // автоисправление — раскладка или опечатка, исправленные сами (их и считает статистика)
            if Settings.clickSound, stats.autoSwitches + stats.typoFixes > 0 { Settings.playClick() }
        }
        monitor.onLanguageChange = { [weak self] language in self?.show(language) }
        show(monitor.current)
        statusItem?.button?.appearsDisabled = !Settings.autoDetect
        self.monitor = monitor
    }

    // свои слова входят в словарь детектора — он пересобирается, но не на каждую букву в редакторе
    private func restartMonitorSoon() {
        pendingRestart?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.startMonitor() }
        pendingRestart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    /// Обучение: экспорт Telegram (result.json) или .txt → слова, которых не хватает словарям.
    /// Всё на этом Mac; сохраняется только список слов, сами сообщения — нет.
    private func learnFromTexts(_ done: @escaping @MainActor (Int) -> Void) {
        guard let detector = monitor?.detector else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.json, .plainText]
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task { @MainActor in
            // разбор и отбор — в фоне: экспорт переписки бывает большим
            let (words, known) = await Task.detached {
                let texts = urls.map(Settings.text(from:))
                let personal = texts.map(\.personal).joined(separator: "\n"), group = texts.map(\.group).joined(separator: "\n")
                return (detector.learnableWords(in: personal, group: group), detector.vocabularyWords(in: personal, group: group))
            }.value
            Settings.learnedWords = Array(Set(Settings.learnedWords + words)).sorted()
            Settings.vocabulary = Array(Set(Settings.vocabulary + known)).sorted()
            startMonitor()
            done(Settings.learnedWords.count)
        }
    }

    /// Выученные слова — в JSON для другого человека (решение владельца 2026-11-06, B28): только выученные, без словаря
    /// текстов и «Моих слов».
    private func exportLearned() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Litara-words.json"
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        guard panel.runModal() == .OK, let url = panel.url, let data = try? LearnedWordsFile.encode(Settings.learnedWords) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Слова из файла другого человека — к своим (B28). Файл чужой: не больше 20 МБ, из него берутся только слова.
    private func importLearned(_ done: @escaping @MainActor ((count: Int, added: Int)?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap({ $0 }) ?? 0 <= 20_000_000,
              let data = try? Data(contentsOf: url), let words = LearnedWordsFile.decode(data) else { done(nil); return }
        let merged = LearnedWordsFile.merge(Settings.learnedWords, words)
        Settings.learnedWords = merged.words
        startMonitor()
        done((merged.words.count, merged.added))
    }

    /// macOS, добавив раскладку, снова показывает свой значок, даже скрытый (проба владельца 2026-10-21) —
    /// прячем заново, и ещё раз чуть позже: система показывает его не сразу.
    private func hideSystemSwitcherAgain() {
        guard Settings.replaceSystemSwitcher else { return }
        Settings.setSystemInputMenuVisible(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { Settings.setSystemInputMenuVisible(false) }
    }

    private func show(_ language: Language?) {
        let flag = Settings.showFlags ? language?.flag : nil
        statusItem?.button?.image = flag
        statusItem?.button?.title = (flag == nil ? language?.code ?? "—" : "") + (secureInput ? " 🔒" : "")
    }

    /// Приложение, которому macOS приписала защищённый ввод. Приписывает тому, что впереди в момент включения,
    /// а не включившему (проба 2026-11-03, B18) — потому в меню «ввод (Chrome)», а не «Chrome включил».
    private static func secureInputApp() -> String {
        let pid = (CGSessionCopyCurrentDictionary() as? [String: Any])?["kCGSSessionSecureInputPID"] as? Int
        return pid.flatMap { NSRunningApplication(processIdentifier: pid_t($0))?.localizedName } ?? "macOS"
    }

    // Меню собирается при каждом открытии: языки и галочка текущего — по состоянию сейчас.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if secureInput {
            let item = NSMenuItem(title: String(format: L10n.text(.secureInput), Self.secureInputApp()), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        }
        if let monitor {
            for language in monitor.languages {
                // флажки включены — и в списке флажок вместо букв
                let flag = Settings.showFlags ? language.flag : nil
                let item = NSMenuItem(title: flag == nil ? "\(language.code)  \(language.nativeName)" : language.nativeName,
                                      action: #selector(selectLanguage(_:)), keyEquivalent: "")
                item.image = flag
                item.target = self
                item.representedObject = language.rawValue
                item.state = language == monitor.current ? .on : .off
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let hotkeys = Settings.hotkeys
            for action in HotkeyAction.allCases {
                guard let hotkey = hotkeys[action] else { continue }
                let item = NSMenuItem(title: "\(Settings.label(hotkey))  \(L10n.hint(action))", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }
        // автопереключение — прямо в меню (просьба владельца 2026-10-21: не ходить в настройки)
        let auto = NSMenuItem(title: L10n.text(.autoSwitchMenu), action: #selector(toggleAutoCorrect), keyEquivalent: "")
        auto.target = self
        auto.state = Settings.autoDetect ? .on : .off
        menu.addItem(auto)
        menu.addItem(.separator())
        let update = NSMenuItem(title: L10n.text(.checkForUpdates), action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self
        update.isEnabled = updater.updater.canCheckForUpdates
        menu.addItem(update)
        let settings = NSMenuItem(title: L10n.text(.settings), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settings)
        menu.addItem(withTitle: L10n.text(.quit), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func toggleAutoCorrect() { setAutoCorrect(!Settings.autoDetect) }

    /// Программа без Dock не впереди — окно Sparkle иначе открылось бы за чужими окнами.
    @objc private func checkForUpdates() {
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        updater.checkForUpdates(nil)
    }

    /// Автопереключение из меню, хоткея или настроек: значок бледнеет, пока оно выключено.
    private func setAutoCorrect(_ on: Bool) {
        Settings.autoDetect = on
        monitor?.autoCorrect = on
        statusItem?.button?.appearsDisabled = !on
        // ponytail: открытое окно настроек своего переключателя не обновит; закрытое — соберётся заново
        if settingsWindow?.isVisible == false { settingsWindow = nil }
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let language = Language(rawValue: raw) else { return }
        // ponytail: задержка из 0.13.1 — «перехода не было» в журнале тогда списали на закрывающееся меню, а это
        // было недоставленное уведомление о смене раскладки (0.17.4). Нужна ли задержка — не проверялось; безвредна
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.monitor?.select(language)
            guard Settings.logDecisions else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Settings.appendLog("меню: выбрана \(language.rawValue), раскладка теперь \(self?.monitor?.current?.rawValue ?? "—")"
                    + (DistributedNotificationCenter.default().suspended ? " (доставка уведомлений приостановлена AppKit)" : ""))
            }
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(
                languages: Settings.languages ?? KeyboardMonitor.systemLanguages(),
                autoDetect: Settings.autoDetect,
                exceptions: Settings.exceptions.joined(separator: "\n"),
                onLanguagesChange: { [weak self] languages in
                    let removed = (Settings.languages ?? KeyboardMonitor.systemLanguages()).subtracting(languages)
                    Settings.languages = languages
                    languages.forEach(KeyboardMonitor.ensureSystemLayout)
                    removed.forEach(KeyboardMonitor.removeAddedLayouts)
                    self?.hideSystemSwitcherAgain()
                    self?.startMonitor()
                },
                onAutoDetectChange: { [weak self] on in self?.setAutoCorrect(on) },
                onCorrectTyposChange: { [weak self] on in
                    Settings.correctTypos = on
                    self?.monitor?.correctTypos = on
                },
                onReplacementsChange: { [weak self] replacements in
                    Settings.replacements = replacements
                    self?.monitor?.replacements = replacements
                },
                onHotkeysChange: { [weak self] in self?.monitor?.hotkeys = Settings.hotkeys },
                onDisabledAppsChange: { [weak self] apps in
                    Settings.disabledApps = apps
                    self?.monitor?.disabledApps = Set(apps)
                },
                onShowFlagsChange: { [weak self] in self?.show(self?.monitor?.current) },
                onAutoUpdateChange: { [weak self] in self?.updater.updater.automaticallyChecksForUpdates = $0 },
                onVariantChange: { [weak self] language, id in
                    let old = self?.monitor?.layoutIDs[language]
                    Settings.layoutVariants[language] = id
                    KeyboardMonitor.selectVariant(id, replacing: old)
                    self?.hideSystemSwitcherAgain()
                    self?.startMonitor()
                },
                currentVariants: { [weak self] in self?.monitor?.layoutIDs ?? [:] },
                onExceptionsChange: { [weak self] words in
                    Settings.exceptions = words
                    self?.monitor?.exceptions = Set(words)
                    self?.restartMonitorSoon()
                },
                onLearn: { [weak self] done in self?.learnFromTexts(done) },
                onForgetLearned: { [weak self] in
                    Settings.learnedWords = []
                    Settings.vocabulary = []
                    self?.startMonitor()
                },
                onExportLearned: { [weak self] in self?.exportLearned() },
                onImportLearned: { [weak self] done in self?.importLearned(done) }
            )
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Litara"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        // приложение без значка в Dock macOS 27 на передний план само не выводит — окно оказывалось
        // позади остальных (проба владельца 2026-10-21); orderFrontRegardless выводит его в любом случае
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        // без этого AppKit отдаёт фокус первому полю своих замен с выделенным текстом — набор затёр бы замену
        settingsWindow?.makeFirstResponder(nil)
        settingsWindow?.orderFrontRegardless()
    }

    /// Окно первого запуска (docs/spec.md): доступ и перенос из Punto. `--welcome` при запуске открывает его снова.
    private func openWelcome() {
        let exceptions = Settings.puntoExceptions(), hotkeys = Settings.puntoHotkeys()
        let view = WelcomeView(puntoExceptions: exceptions.count, puntoHotkeys: hotkeys) { [weak self] importExceptions, importHotkeys in
            if importExceptions {
                let have = Set(Settings.exceptions.map { $0.lowercased() })
                Settings.exceptions += exceptions.filter { !have.contains($0.lowercased()) }
            }
            if importHotkeys { hotkeys.forEach { Settings.setHotkey($0.value, for: $0.key) } }
            Settings.welcomed = true
            self?.welcomeWindow?.close()
            // перенесённое — в работающий перехват; без доступа его запустит ожидание доступа
            if AXIsProcessTrusted(), self?.monitor != nil { self?.startMonitor() }
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Litara"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        welcomeWindow = window
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    // MARK: запоминание откатов

    /// ⌥ вернул автоисправленное слово к набранному. Третий откат одного слова — слово в «Мои слова», уведомление
    /// только сообщает (решение владельца 2026-10-23: вопрос с кнопками приходил баннером и исчезал без ответа).
    private func rolledBack(_ rolled: String) {
        guard Settings.rememberRollbacks else { return }
        let word = rolled.trimmingCharacters(in: .punctuationCharacters)  // «вуфирмы?» и «вуфирмы» — одно слово
        guard !word.isEmpty else { return }
        var counts = Settings.rollbackCounts
        counts[word, default: 0] += 1
        // больше трёх — счёт прежних версий, где вопрос остался без ответа
        let remember = counts[word, default: 0] >= 3
        if remember { counts[word] = nil }
        Settings.rollbackCounts = counts
        guard remember, !Settings.exceptions.contains(where: { $0.lowercased() == word }) else { return }
        Settings.exceptions.append(word)
        monitor?.exceptions.insert(word)
        restartMonitorSoon()  // «Мои слова» входят и в словарь детектора
        let content = UNMutableNotificationContent()
        content.title = L10n.text(.rollbackTitle)
        content.body = String(format: L10n.text(.rollbackRemembered), word)
        let request = UNNotificationRequest(identifier: "rollback-\(word)", content: content, trigger: nil)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
            if granted { UNUserNotificationCenter.current().add(request) }
        }
    }

    // приложение без Dock почти всегда «не на переднем плане», но если вдруг — показать всё равно
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner]
    }
}
