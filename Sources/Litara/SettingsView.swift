import LitaraCore
import ServiceManagement
import SwiftUI

/// Окно настроек.
struct SettingsView: View {
    @State var languages: Set<Language>
    @State var autoDetect: Bool
    @State var exceptions: String
    @State var replaceSystemSwitcher = Settings.replaceSystemSwitcher
    @State private var correctTypos = Settings.correctTypos
    @State private var rememberRollbacks = Settings.rememberRollbacks
    @State private var clickSound = Settings.clickSound
    @State private var rules = Settings.replacements
    @State private var uiLanguage = Settings.interfaceLanguage
    @State private var learnedCount = Settings.learnedWords.count
    @State private var vocabularyCount = Settings.vocabulary.count
    @State private var logDecisions = Settings.logDecisions
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    let onLanguagesChange: (Set<Language>) -> Void
    let onAutoDetectChange: (Bool) -> Void
    let onCorrectTyposChange: (Bool) -> Void
    let onReplacementsChange: ([Replacement]) -> Void
    let onHotkeysChange: () -> Void
    let onDisabledAppsChange: ([String]) -> Void
    let onShowFlagsChange: () -> Void
    let onAutoUpdateChange: (Bool) -> Void
    /// Выбран вариант раскладки языка (id раскладки macOS).
    let onVariantChange: (Language, String) -> Void
    /// Раскладки, с которыми работает перехват сейчас.
    let currentVariants: () -> [Language: String]
    /// Выбранное в этом окне — до перезапуска перехвата.
    @State private var variants: [Language: String] = [:]
    /// Раскладки macOS по языкам — для выбора варианта.
    @State private var layoutOptions = Dictionary(grouping: KeyboardLayout.available(), by: \.language)
        .mapValues { $0.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    @State private var showFlags = Settings.showFlags
    @State private var autoUpdate = Settings.autoUpdate
    @State private var disabledApps = Settings.disabledApps
    @State private var hotkeys = Settings.hotkeys
    /// Действие, чей хоткей сейчас записывается, и монитор нажатий записи.
    @State private var recording: HotkeyAction?
    @State private var keyMonitor: Any?
    /// Сброс статистики — перерисовать сразу, не ждать следующего тика.
    @State private var statsSince = Settings.statsSince
    @AppStorage("settingsTab") private var tab = "general"
    let onExceptionsChange: ([String]) -> Void
    /// Выбрать файлы и выучить слова; ответ — сколько слов теперь выучено.
    let onLearn: (@escaping @MainActor (Int) -> Void) -> Void
    let onForgetLearned: () -> Void
    /// Выученные слова — в JSON для другого человека (B28).
    let onExportLearned: () -> Void
    /// Слова из такого файла — к своим; ответ — сколько всего и сколько добавлено, не файл слов — `nil`.
    let onImportLearned: (@escaping @MainActor ((count: Int, added: Int)?) -> Void) -> Void
    @State private var importNote: String?

    /// Язык подписей: выбранный здесь же или язык системы.
    private var ui: Language { uiLanguage ?? L10n.current }

    /// Вкладки (просьба владельца 2026-10-21: без длинной прокрутки); последняя открытая запоминается.
    var body: some View {
        TabView(selection: $tab) {
            general.tabItem { Text(L10n.text(.tabGeneral, ui)) }.tag("general")
            shortcuts.tabItem { Text(L10n.text(.tabHotkeys, ui)) }.tag("hotkeys")
            words.tabItem { Text(L10n.text(.tabWords, ui)) }.tag("words")
            statistics.tabItem { Text(L10n.text(.statistics, ui)) }.tag("stats")
            apps.tabItem { Text(L10n.text(.tabApps, ui)) }.tag("apps")
        }
        .padding(.top, 8)
        .frame(width: 480, height: 720)
    }

    /// Основные: язык интерфейса, языки, что исправлять, запуск.
    private var general: some View {
        Form {
            Section {
                Picker(L10n.text(.interfaceLanguage, ui), selection: Binding(
                    get: { uiLanguage },
                    set: { uiLanguage = $0; Settings.interfaceLanguage = $0; onShowFlagsChange() }  // флажки зависят от языка интерфейса
                )) {
                    Text(L10n.text(.systemLanguage, ui)).tag(Language?.none)
                    ForEach(Language.allCases, id: \.self) { Text($0.nativeName).tag(Language?.some($0)) }
                }
            }
            Section(L10n.text(.languages, ui)) {
                ForEach(Language.allCases, id: \.self) { language in
                    HStack {
                        Text("\(language.code)  \(language.nativeName)")
                        Spacer()
                        // вариант раскладки (docs/spec.md) — в той же строке: вкладка не должна прокручиваться
                        if languages.contains(language), let options = layoutOptions[language], options.count > 1 {
                            Picker("", selection: Binding(
                                get: { variants[language] ?? currentVariants()[language] ?? "" },
                                set: { variants[language] = $0; onVariantChange(language, $0) }
                            )) {
                                ForEach(options, id: \.id) { Text($0.name).tag($0.id) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        Toggle("", isOn: Binding(
                            get: { languages.contains(language) },
                            set: { on in
                                if on { languages.insert(language) } else { languages.remove(language) }
                                onLanguagesChange(languages)
                            }
                        ))
                        .labelsHidden()
                    }
                }
            }
            Section {
                Toggle(L10n.text(.autoDetect, ui), isOn: Binding(
                    get: { autoDetect },
                    set: { autoDetect = $0; onAutoDetectChange($0) }
                ))
                Toggle(L10n.text(.correctTypos, ui), isOn: Binding(
                    get: { correctTypos },
                    set: { correctTypos = $0; onCorrectTyposChange($0) }
                ))
                Text(String(format: L10n.text(.correctTyposHint, ui), fixLabel)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)  // форма иначе обрезает подпись в одну строку
                Toggle(L10n.text(.clickSound, ui), isOn: Binding(
                    get: { clickSound },
                    set: { clickSound = $0; Settings.clickSound = $0; if $0 { Settings.playClick() } }
                ))
                Toggle(L10n.text(.launchAtLogin, ui), isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                ))
                if let loginError { Text(loginError).foregroundStyle(.red).font(.caption) }
                Toggle(L10n.text(.autoUpdate, ui), isOn: Binding(
                    get: { autoUpdate },
                    set: { autoUpdate = $0; onAutoUpdateChange($0) }
                ))
                Toggle(L10n.text(.showFlags, ui), isOn: Binding(
                    get: { showFlags },
                    set: { showFlags = $0; Settings.showFlags = $0; onShowFlagsChange() }
                ))
                Toggle(L10n.text(.replaceSwitcher, ui), isOn: Binding(
                    get: { replaceSystemSwitcher },
                    set: { on in
                        replaceSystemSwitcher = on
                        Settings.replaceSystemSwitcher = on
                        Settings.setSystemInputMenuVisible(!on)
                    }
                ))
                Text(L10n.text(.replaceSwitcherHint, ui))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)  // форма иначе обрезает подпись в одну строку
            }
        }
        .formStyle(.grouped)
    }

    /// Сочетания клавиш.
    private var shortcuts: some View {
        Form {
            Section(L10n.text(.hotkeys, ui)) {
                ForEach(HotkeyAction.allCases, id: \.self) { action in
                    HStack {
                        let name = L10n.hint(action, ui)
                        Text(name.prefix(1).uppercased() + name.dropFirst()).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(recording == action ? L10n.text(.pressShortcut, ui)
                               : hotkeys[action].map(Settings.label) ?? L10n.text(.assignShortcut, ui)) { record(action) }
                        if hotkeys[action] != nil, recording != action {
                            Button("×") { assign(nil, to: action) }
                        }
                    }
                }
                Text(L10n.text(.hotkeysHint, ui)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)  // форма иначе обрезает подпись в одну строку
            }
        }
        .formStyle(.grouped)
    }

    /// Свои замены, «Мои слова», обучение.
    private var words: some View {
        Form {
            Section(L10n.text(.replacements, ui)) {
                // табличка: «что», «на что» и своя галочка регистра у строки (просьбы владельца 2026-10-21).
                // Не `Table`: внутри Form SwiftUI выключает ей прокрутку (hasVerticalScroller = false) — длинный
                // список обрезался без полосы (проба владельца 2026-10-23); ScrollView свою прокрутку сохраняет.
                ScrollViewReader { proxy in
                    VStack(spacing: 4) {
                        HStack {
                            Text(Self.heading(L10n.text(.replaceWhat, ui))).frame(maxWidth: .infinity, alignment: .leading)
                            Text(Self.heading(L10n.text(.replaceWith, ui))).frame(maxWidth: .infinity, alignment: .leading)
                            Text(Self.heading(L10n.text(.replacementsIgnoreCase, ui))).frame(width: 130)
                            // над «×» строк: отдельная строка с кнопкой не влезла бы во вкладку высотой 720
                            Button("+") { rules.append(Replacement(what: "", with: "")) }.foregroundStyle(.primary)
                        }
                        .font(.subheadline).foregroundStyle(.secondary)  // мелко, как заголовки таблицы
                        ScrollView {
                            VStack {
                                ForEach(rules) { rule in
                                    HStack {
                                        // рамка видна и без фокуса — сразу ясно, что поле можно заполнить (просьба владельца 2026-10-23)
                                        TextField("", text: ruleBinding(rule.id, \.what)).labelsHidden().textFieldStyle(.roundedBorder)
                                        TextField("", text: ruleBinding(rule.id, \.with)).labelsHidden().textFieldStyle(.roundedBorder)
                                        Toggle("", isOn: ruleBinding(rule.id, \.ignoreCase)).labelsHidden().toggleStyle(.checkbox)
                                            .help(Self.ignoreCaseHelp(rule.what, ui))
                                            .frame(width: 130)
                                        Button("×") { rules.removeAll { $0.id == rule.id } }
                                    }
                                    .id(rule.id)
                                }
                            }
                        }
                        .frame(height: 130)
                    }
                    // новая строка внизу списка — прокрутить к ней
                    .onChange(of: rules.last?.id) { id in if let id { proxy.scrollTo(id) } }
                }
                Text(String(format: L10n.text(.replacementsHint, ui), fixLabel)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)  // форма иначе обрезает подпись в одну строку
            }
            Section(L10n.text(.neverCorrect, ui)) {
                TextEditor(text: Binding(
                    get: { exceptions },
                    set: { exceptions = $0; onExceptionsChange(Self.lines($0)) }
                ))
                .font(.body.monospaced())
                .frame(height: 140)
                Toggle(L10n.text(.rememberRollbacks, ui), isOn: Binding(
                    get: { rememberRollbacks },
                    set: { rememberRollbacks = $0; Settings.rememberRollbacks = $0 }
                ))
                let punto = Settings.puntoExceptions()
                if !punto.isEmpty {
                    Button(String(format: L10n.text(.importPunto, ui), punto.count)) {
                        let have = Set(Self.lines(exceptions).map { $0.lowercased() })
                        let added = punto.filter { !have.contains($0.lowercased()) }
                        exceptions = (Self.lines(exceptions) + added).joined(separator: "\n")
                        onExceptionsChange(Self.lines(exceptions))
                    }
                }
                FittingRow {
                    Text(String(format: L10n.text(.learned, ui), learnedCount)).fixedSize(horizontal: false, vertical: true)
                } buttons: {
                    Button(L10n.text(.learnFromTexts, ui)) {
                        onLearn { learnedCount = $0; vocabularyCount = Settings.vocabulary.count }
                    }
                    if learnedCount > 0 || vocabularyCount > 0 {
                        Button(L10n.text(.clearLearned, ui)) { onForgetLearned(); learnedCount = 0; vocabularyCount = 0 }
                    }
                }
                // передать выученные слова другому человеку и принять его (решение владельца 2026-11-06, B28)
                FittingRow {
                    if let importNote {
                        Text(importNote).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                } buttons: {
                    Button(L10n.text(.exportLearned, ui)) { onExportLearned() }.disabled(learnedCount == 0)
                    Button(L10n.text(.importLearned, ui)) {
                        onImportLearned { result in
                            if let result {
                                learnedCount = result.count
                                importNote = String(format: L10n.text(.importedWords, ui), result.added)
                            } else {
                                importNote = L10n.text(.notWordsFile, ui)
                            }
                        }
                    }
                }
                Text(String(format: L10n.text(.vocabularyHint, ui), vocabularyCount)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)  // форма иначе обрезает подпись в одну строку
            }
        }
        .formStyle(.grouped)
        .onChange(of: rules) { onReplacementsChange($0) }
    }

    /// Приложения, где Litara сам ничего не исправляет (решение владельца 2026-10-21: хоткеи там работают).
    private var apps: some View {
        Form {
            Section(L10n.text(.disabledApps, ui)) {
                ForEach(disabledApps, id: \.self) { id in
                    HStack {
                        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
                        if let url { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20) }
                        // имя по-системному («Терминал»); с включёнными в Finder расширениями оно приходит с «.app»
                        let name = url.map { FileManager.default.displayName(atPath: $0.path) } ?? id
                        Text(name.hasSuffix(".app") ? String(name.dropLast(4)) : name)
                        Spacer()
                        Button("×") { setDisabledApps(disabledApps.filter { $0 != id }) }
                    }
                }
                // запущенные приложения — обычный случай «выключить там, где я сейчас»; остальные — «Другое…»
                Menu(L10n.text(.addApp, ui)) {
                    let running = NSWorkspace.shared.runningApplications.filter {
                        $0.activationPolicy == .regular && $0.bundleIdentifier.map { !disabledApps.contains($0) && $0 != Bundle.main.bundleIdentifier } == true
                    }.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
                    ForEach(running, id: \.processIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "?") { setDisabledApps(disabledApps + [app.bundleIdentifier!]) }
                    }
                    Divider()
                    Button(L10n.text(.otherApp, ui)) { chooseApps() }
                }
                .fixedSize()
                Text(L10n.text(.disabledAppsHint, ui)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)  // форма иначе обрезает подпись в одну строку
            }
        }
        .formStyle(.grouped)
    }

    private func setDisabledApps(_ apps: [String]) {
        disabledApps = apps
        onDisabledAppsChange(apps)
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        var apps = disabledApps
        for id in panel.urls.compactMap({ Bundle(url: $0)?.bundleIdentifier }) where !apps.contains(id) { apps.append(id) }
        setDisabledApps(apps)
    }

    /// Статистика и журнал решений.
    private var statistics: some View {
        Form {
            Section(L10n.text(.statistics, ui)) {
                // какая сборка запущена — по номеру видно, в какой что сломалось (решение владельца 2026-11-06)
                LabeledContent(L10n.text(.statVersion, ui),
                               value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                // что нового — страница выпусков на GitHub, открывается в браузере (решение владельца 2026-11-06, B36)
                Link(L10n.text(.whatsNew, ui), destination: URL(string: "https://github.com/Nugnii/litara/releases")!)
                // благодарность автору — открывается в браузере по нажатию, сама программа в сеть не ходит (решение
                // владельца 2026-11-06)
                Link(L10n.text(.supportAuthor, ui), destination: URL(string: "https://buycoffee.to/stugka")!)
                // счётчики пишет перехват — окно перечитывает их раз в 2 секунды
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    let stats = Settings.stats
                    let fixes = stats.autoSwitches + stats.manualFixes, autos = stats.autoSwitches + stats.typoFixes
                    LabeledContent(L10n.text(.statWords, ui), value: stats.words.formatted())
                    LabeledContent(L10n.text(.statAuto, ui), value: stats.autoSwitches.formatted())
                    LabeledContent(L10n.text(.statTypos, ui), value: stats.typoFixes.formatted())
                    LabeledContent(L10n.text(.statManual, ui), value: Self.count(stats.manualFixes, of: fixes))
                    LabeledContent(L10n.text(.statRollbacks, ui), value: Self.count(stats.rollbacks, of: autos))
                    LabeledContent(L10n.text(.statCrashes, ui), value: Settings.crashCount(since: statsSince).formatted())
                }
                HStack {
                    Text(String(format: L10n.text(.statSince, ui),
                                statsSince.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: ui.rawValue)))))
                    Spacer()
                    Button(L10n.text(.statReset, ui)) {
                        Settings.stats = TypingStats()
                        Settings.statsSince = Date()
                        statsSince = Settings.statsSince
                    }
                }
                Text(L10n.text(.statHint, ui)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)  // форма иначе обрезает подпись в одну строку
            }
            Section {
                Toggle(L10n.text(.logDecisions, ui), isOn: Binding(
                    get: { logDecisions },
                    set: { logDecisions = $0; Settings.logDecisions = $0 }
                ))
                Text(L10n.text(.logHint, ui)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)  // форма иначе обрезает подпись в одну строку
            }
        }
        .formStyle(.grouped)
    }

    /// Ячейка таблицы замен — поле строки `id`.
    private func ruleBinding<T>(_ id: Replacement.ID, _ field: WritableKeyPath<Replacement, T>) -> Binding<T> {
        Binding(
            get: { (rules.first { $0.id == id } ?? Replacement(what: "", with: ""))[keyPath: field] },
            set: { value in if let i = rules.firstIndex(where: { $0.id == id }) { rules[i][keyPath: field] = value } }
        )
    }

    /// Заголовок столбца с заглавной.
    static func heading(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }

    /// Подсказка галочки на примере самой строки (просьба владельца 2026-10-21): «мск», «Мск», «МСК».
    static func ignoreCaseHelp(_ what: String, _ ui: Language) -> String {
        let what = what.trimmingCharacters(in: .whitespaces)
        guard !what.isEmpty else { return L10n.text(.ignoreCaseHelpEmpty, ui) }
        let lower = what.lowercased()
        return String(format: L10n.text(.ignoreCaseHelp, ui), what, lower.prefix(1).uppercased() + lower.dropFirst(), what.uppercased())
    }

    /// «12 · 4,1 %» — число и его доля от `total`.
    static func count(_ value: Int, of total: Int) -> String {
        total == 0 ? value.formatted() : "\(value.formatted()) · \((Double(value) / Double(total)).formatted(.percent.precision(.fractionLength(1))))"
    }

    /// Подпись хоткея «исправить» для подсказок «… возвращает набранное».
    private var fixLabel: String { hotkeys[.fix].map(Settings.label) ?? "—" }

    /// Хоткей действия: сохранить, у другого действия то же сочетание снять, перехвату — новые хоткеи.
    private func assign(_ hotkey: Hotkey?, to action: HotkeyAction) {
        for (other, existing) in hotkeys where other != action && existing == hotkey {
            Settings.setHotkey(nil, for: other)
        }
        Settings.setHotkey(hotkey, for: action)
        hotkeys = Settings.hotkeys
        onHotkeysChange()
    }

    /// Запись хоткея (`HotkeyRecorder`). Пока она идёт, нажатия в окно настроек не попадают, а перехват Litara
    /// хоткеи не исполняет (`KeyboardMonitor.recordingHotkey`); клик мышью запись отменяет — иначе набор в поле
    /// глотался бы.
    private func record(_ action: HotkeyAction) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        recording = action
        KeyboardMonitor.recordingHotkey = true
        var recorder = HotkeyRecorder()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown]) { event in
            let flags = UInt64(event.modifierFlags.intersection([.command, .option, .control, .shift]).rawValue)
            let outcome: HotkeyRecorder.Outcome = switch event.type {
            case .leftMouseDown: .cancel
            case .flagsChanged: recorder.modifiers(flags)
            default: recorder.key(event.keyCode, flags: flags)
            }
            guard outcome != .wait else { return nil }
            MainActor.assumeIsolated {
                if case let .done(hotkey) = outcome { assign(hotkey, to: action) }
                if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
                keyMonitor = nil
                recording = nil
                KeyboardMonitor.recordingHotkey = false
            }
            return event.type == .leftMouseDown ? event : nil  // клик идёт дальше — по кнопке или в поле
        }
    }

    static func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

/// Подпись и кнопки ряда без обрезки (R14, B29; владелец 2026-11-06: подписи не обрезаются ни на одном языке):
/// в строку, если влезают целиком; иначе кнопки — под подписью; не влезут и так — друг под другом. Окно настроек
/// фиксированной ширины, а подписи на 5 языках разной длины — `HStack` без запасного расположения сжимал кнопки, и надписи обрезались.
private struct FittingRow<Label: View, Buttons: View>: View {
    @ViewBuilder var label: Label
    @ViewBuilder var buttons: Buttons

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { label; Spacer(); buttons }
            VStack(alignment: .leading) { label; HStack { Spacer(); buttons } }
            VStack(alignment: .leading) {
                label
                VStack(alignment: .trailing) { buttons }.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}
