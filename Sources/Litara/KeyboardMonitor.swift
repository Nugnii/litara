import AppKit
import LitaraCore
import Carbon

/// Перехват клавиатуры: нажатия идут в TypingSession, её действия исполняются синтетическими
/// нажатиями. Буфер обмена не используется.
@MainActor
final class KeyboardMonitor {
    var onLanguageChange: ((Language?) -> Void)?
    /// Язык текущей раскладки macOS; `nil` — раскладка не из языков Litara.
    private(set) var current: Language?
    /// Языки, между которыми Litara исправляет и переключает (у каждого есть раскладка в macOS).
    var languages: [Language] { Language.allCases.filter { sources[$0] != nil } }
    /// Автоопределение (настройка); в приложениях из `disabledApps` сеанс его не получает.
    var autoCorrect = true { didSet { applyFrontmostApp() } }
    var exceptions: Set<String> {
        get { session.exceptions }
        set { session.exceptions = newValue }
    }
    var correctTypos: Bool {
        get { session.correctTypos }
        set { session.correctTypos = newValue }
    }
    var replacements: [Replacement] = [] { didSet { applyFrontmostApp() } }
    /// «Не исправлять само в этих приложениях» (bundle id).
    var disabledApps: Set<String> = [] { didSet { applyFrontmostApp() } }
    private var frontmostApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    var hotkeys: [HotkeyAction: Hotkey] = [:]
    /// Хоткей «автопереключение вкл/выкл» — переключает приложение (настройка, меню, значок).
    var onToggleAutoCorrect: (() -> Void)?
    /// Приращение статистики — после каждого события, которое её изменило.
    var onStats: ((TypingStats) -> Void)?
    /// Слова, выученные на наборе: их сохраняют в словарь текстов (`Settings.vocabulary`).
    var onLearned: (([String]) -> Void)?
    /// ⌥ вернул автоисправленное слово к набранному — слово (строчными), для запоминания откатов.
    var onRollback: ((String) -> Void)?

    private var session: TypingSession
    /// Детектор текущих языков — им же отбираются слова для обучения.
    let detector: LanguageDetector
    private let sources: [Language: TISInputSource]
    private let languageByID: [String: Language]
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var observing = false
    private var activationObserver: NSObjectProtocol?
    /// Знаки «как в Русской – ПК» в белорусской раскладке: белорусская Apple и она же со знаками ПК — где они расходятся,
    /// печатается знак ПК (macOS напечатала бы знак Apple). Сеанс знает те же знаки (`withPunctuation`). Читается по
    /// нажатию, а не один раз: знаки ПК у ANSI и ISO разные (R18). `nil`, если «Русская – ПК» не включена.
    private var pcPunctuation: (apple: KeyboardLayout, pc: KeyboardLayout)?
    /// Нажатые без клавиш модификаторы — кандидат в хоткей «нажать и отпустить» (⌥, ⇧⌥).
    private var modifierTap: (flags: CGEventFlags, since: Date)?
    private var heldModifiers: CGEventFlags = []
    private static let modifierMask: CGEventFlags = [.maskAlternate, .maskShift, .maskCommand, .maskControl]

    /// Метка своих синтетических событий, чтобы не перехватывать их повторно.
    private static let marker: Int64 = 0x626c_616c_62  // «Litara»
    /// Приложения, где правка «стереть и напечатать» ненадёжна: стирание доходит позже печати и съедает её (B14, R7).
    /// Там Litara текст не правит — ни сам, ни хоткеями; раскладку переключать можно (решение владельца 2026-10-23).
    // ponytail: список вручную по пробам; другое приложение — сюда же после такой же пробы
    private static let unreliableApps: Set<String> = ["com.netease.mumu.nemux-global.emulator"]

    /// `allowed` — языки из настроек; раскладка языка — выбранный в настройках вариант (`preferred`), если он
    /// включён в macOS, иначе первая включённая.
    init?(allowed: Set<Language>, preferred: [Language: String], autoCorrect: Bool, exceptions: [String], learned: [String],
          vocabulary: [String]) {
        let known = Dictionary(KeyboardLayout.available().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var layouts: [Language: KeyboardLayout] = [:]
        var sources: [Language: TISInputSource] = [:]
        var languageByID: [String: Language] = [:]
        for source in Self.enabledLayoutSources() {
            guard let id = Self.id(of: source), let layout = known[id] else { continue }
            languageByID[id] = layout.language
            if allowed.contains(layout.language), layouts[layout.language] == nil || preferred[layout.language] == id {
                layouts[layout.language] = layout
                sources[layout.language] = source
            }
        }
        // у Apple нет белорусской раскладки «ПК»: ?, «,» и «.» в ней не на тех клавишах, что в «Русской –
        // ПК» (проба владельца 2026-10-21) — знаковые клавиши печатают знаки ПК; буквы не трогаются
        // сеансу — та же раскладка, что на экране: прежде он получал нажатие Apple, дающее знак ПК (⇧7 вместо
        // «/» для «.»), и круг ⌥ видел в белорусской «/» — «.» уходила в белорусскую (проба 2026-10-21)
        var pc: (apple: KeyboardLayout, pc: KeyboardLayout)?
        if let be = layouts[.be], let ru = layouts[.ru], ru.id == "com.apple.keylayout.RussianWin" {
            let withPC = be.withPunctuation(of: ru)
            pc = (be, withPC)
            layouts[.be] = withPC
        }
        var filters: [Language: WordFilter] = [:]
        var prefixes: [Language: WordFilter] = [:]
        var checks: [Language: WordFilter] = [:]
        var trigrams: [Language: Set<String>] = [:]
        for language in layouts.keys {
            filters[language] = WordFilter.bundled(language)
            prefixes[language] = WordFilter.bundledPrefixes(language)
            checks[language] = WordFilter.bundledCheck(language)
            trigrams[language] = LanguageDetector.bundledTrigrams(language)
        }
        let current = Self.currentID().flatMap { languageByID[$0] }

        self.sources = sources
        self.languageByID = languageByID
        self.pcPunctuation = pc
        self.current = current
        // сеансу нужен язык и тогда, когда текущая раскладка не наша: набор в ней не обрабатывается
        let start = current.flatMap { sources[$0] != nil ? $0 : nil } ?? Language.allCases.first { sources[$0] != nil } ?? .en
        var detector = LanguageDetector(layouts: layouts, filters: filters, prefixes: prefixes, checks: checks,
                                        userWords: exceptions + learned, trigrams: trigrams)
        detector.vocabulary = Set(vocabulary)
        self.detector = detector
        session = TypingSession(detector: detector, layouts: layouts, current: start)
        self.autoCorrect = autoCorrect
        applyFrontmostApp()
        session.exceptions = Set(exceptions)
        guard installTap() else { return nil }
        // доставлять сразу: AppKit приостанавливает доставку, пока приложение неактивно, а окно настроек
        // делает Litara активным — после него смены раскладки копились и не доходили, значок и сеанс
        // оставались в прежней (проба владельца 2026-10-21: выбор языка в списке не срабатывал)
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDistributedCenter(), Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { MainActor.assumeIsolated { monitor.inputSourceChanged() } }
            },
            kTISNotifySelectedKeyboardInputSourceChanged, nil, .deliverImmediately)
        observing = true
        // Electron (VSCode, Slack) строит дерево «Универсального доступа» только по просьбе и не сразу:
        // просьба в момент ⌥ опаздывала, и первое нажатие на выделении молчало (журнал пробы 2026-10-21:
        // «Code, фокус не отдан (AX -25212)», второе нажатие сработало) — просим, когда приложение активно
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier, id = app?.bundleIdentifier
            MainActor.assumeIsolated {
                pid.map(Self.requestAccessibility)
                self?.frontmostApp = id
                self?.applyFrontmostApp()
                if let pending = self?.pendingLanguage, id != Bundle.main.bundleIdentifier {
                    self?.pendingLanguage = nil
                    // чуть позже: macOS сама возвращает приложению его раскладку при активации
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.select(pending) }
                }
            }
        }
        NSWorkspace.shared.frontmostApplication.map { Self.requestAccessibility($0.processIdentifier) }
    }

    /// Приложение из «не исправлять само» (решение владельца 2026-10-21): ни раскладка, ни опечатки, ни свои
    /// замены сами не меняются; хоткеи работают — это явная просьба, и сеанс ведётся для них.
    private func applyFrontmostApp() {
        let unreliable = frontmostApp.map(Self.unreliableApps.contains) ?? false
        let off = unreliable || (frontmostApp.map(disabledApps.contains) ?? false)
        session.autoCorrect = autoCorrect && !off
        let rules = off ? [] : replacements
        if session.replacements != rules { session.replacements = rules }
        if off, Settings.logDecisions {
            Settings.appendLog("\(frontmostApp ?? "?") — " + (unreliable ? "правка текста ненадёжна, не правлю" : "в «не исправлять само»"))
        }
    }

    /// Просит приложение построить дерево «Универсального доступа»; `true` — оно поняло просьбу Electron (`AXManualAccessibility`).
    /// Chromium без Electron (ChatGPT на движке Owl) её не знает (-25205) и до просьбы VoiceOver — `AXEnhancedUserInterface` — не
    /// отдаёт ни поле, ни фокус (B46, R20; замер 2026-11-07: у окна ChatGPT 11 элементов, после просьбы, когда приложение впереди, —
    /// 522 и поле ввода). Её получает только приложение, которое фокус не отдаёт: у прочих она замедляет перемещение окон извне —
    /// ради этого Electron и завёл свою.
    /// ponytail: флаг не снимается — построенное дерево приложение может обновлять и в фоне; станет грузить процессор на длинных
    /// ответах ChatGPT — снимать при уходе приложения с переднего плана
    @discardableResult
    private static func requestAccessibility(_ pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)  // зависшее приложение не держит набор
        let electron = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        var focused: CFTypeRef?
        if electron == .attributeUnsupported, AXUIElementCopyAttributeValue(app, "AXFocusedUIElement" as CFString, &focused) == .noValue {
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            if Settings.logDecisions {
                let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "?"
                Settings.appendLog("\(name) не отдаёт фокус — прошу дерево доступа, как VoiceOver (AXEnhancedUserInterface)")
            }
        }
        return electron == .success
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if observing {
            CFNotificationCenterRemoveObserver(CFNotificationCenterGetDistributedCenter(), Unmanaged.passUnretained(self).toOpaque(),
                                               CFNotificationName(kTISNotifySelectedKeyboardInputSourceChanged), nil)
        }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        tap = nil
        runLoopSource = nil
        observing = false
        activationObserver = nil
    }

    /// Раскладка каждого языка, с которой работает перехват (её id в macOS).
    var layoutIDs: [Language: String] { sources.compactMapValues(Self.id(of:)) }

    /// Вариант раскладки (docs/spec.md: «Вариант меняется в настройках»): выбранный включается в macOS и
    /// запоминается как добавленный Litara; прежний убирается, только если его добавил Litara — как у языков.
    static func selectVariant(_ id: String, replacing old: String?) {
        func source(_ id: String) -> TISInputSource? {
            let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
            return (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource])?.first
        }
        guard let new = source(id) else { return }
        if !enabledLayoutSources().contains(where: { Self.id(of: $0) == id }), TISEnableInputSource(new) == noErr,
           !Settings.addedLayouts.contains(id) {
            Settings.addedLayouts.append(id)
        }
        guard let old, old != id, Settings.addedLayouts.contains(old), let oldSource = source(old) else { return }
        // набор шёл в прежнем варианте — переходит в новый, а не в случайную раскладку macOS
        if currentID() == old { TISSelectInputSource(new) }
        TISDisableInputSource(oldSource)
        Settings.addedLayouts.removeAll { $0 == old }
    }

    /// Переключение из меню — как ручное переключение пользователем.
    func select(_ language: Language) {
        guard let source = sources[language] else { return }
        TISSelectInputSource(source)
        // впереди окно Litara (настройки) — выбор повторяется, когда станет активным приложение пользователя: при
        // включённой в macOS «раскладке у каждого документа» выбранная может достаться окну Litara. У владельца
        // режим выключен, и повтор лишний: «не проходило» из-за недоставленного уведомления (0.17.4, B6)
        pendingLanguage = NSApp.isActive ? language : nil
    }

    private var pendingLanguage: Language?

    /// Языки Litara, у которых есть включённая раскладка в macOS.
    static func systemLanguages() -> Set<Language> {
        let known = Dictionary(KeyboardLayout.available().map { ($0.id, $0.language) }, uniquingKeysWith: { a, _ in a })
        return Set(enabledLayoutSources().compactMap { id(of: $0).flatMap { known[$0] } })
    }

    /// Включённый в настройках язык без раскладки в macOS получает раскладку по умолчанию (docs/spec.md);
    /// добавленная запоминается — снятый язык её уберёт.
    static func ensureSystemLayout(for language: Language) {
        guard !systemLanguages().contains(language) else { return }
        // выбранный раньше вариант важнее варианта по умолчанию
        let id = Settings.layoutVariants[language] ?? language.defaultLayoutID
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let source = (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource])?.first else {
            return
        }
        if TISEnableInputSource(source) == noErr, !Settings.addedLayouts.contains(id) {
            Settings.addedLayouts.append(id)
        }
    }

    /// Снятый в настройках язык: раскладки, которые добавил Litara, уходят из macOS (проба владельца
    /// 2026-10-21); бывшие до Litara остаются.
    static func removeAddedLayouts(for language: Language) {
        let known = Dictionary(KeyboardLayout.available().map { ($0.id, $0.language) }, uniquingKeysWith: { a, _ in a })
        for id in Settings.addedLayouts where known[id] == language {
            let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
            if let source = (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource])?.first {
                TISDisableInputSource(source)
            }
            Settings.addedLayouts.removeAll { $0 == id }
        }
    }

    private static func enabledLayoutSources() -> [TISInputSource] {
        let filter = [kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String] as CFDictionary
        return TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] ?? []
    }

    private static func currentID() -> String? {
        TISCopyCurrentKeyboardLayoutInputSource().flatMap { id(of: $0.takeRetainedValue()) }
    }

    private func installTap() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask), callback: tapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
        return true
    }

    /// `true` — пропустить событие дальше, `false` — проглотить.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        defer {
            let stats = session.takeStats()
            if stats != TypingStats() { onStats?(stats) }
            let learned = session.takeLearned()
            if !learned.isEmpty { onLearned?(learned) }
        }
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        case .leftMouseDown, .rightMouseDown:
            modifierTap = nil
            resetSession("клик")
            return true
        case .flagsChanged:
            modifiersChanged(event.flags.intersection(Self.modifierMask))
            return true
        case .keyDown:
            break
        default:
            return true
        }
        guard event.getIntegerValueField(.eventSourceUserData) != Self.marker else { return true }
        modifierTap = nil
        let flags = event.flags
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        // тип клавиатуры — из нажатия: внешняя и встроенная бывают ISO и ANSI, «ё» слева от «1» у них на разных кодах (B25)
        let keyboardType = event.getIntegerValueField(.keyboardEventKeyboardType)
        if keyboardType > 0, case let type = UInt32(truncatingIfNeeded: keyboardType), type != KeyboardLayout.keyboardType {
            KeyboardLayout.keyboardType = type  // таблица раскладки — под эту клавиатуру (R18)
            let left = KeyboardLayout.leftOfOneKey
            if Settings.logDecisions { Settings.appendLog("клавиатура \(left == 10 ? "ISO" : "ANSI") (тип \(keyboardType)): слева от «1» — код \(left)") }
        }
        let action = hotkeyAction(code: code, flags: flags.intersection(Self.modifierMask))
        // раскладка по кругу и вкл/выкл автопереключения — и из раскладки не из языков Litara
        if let action, action == .nextLayout || action == .toggleAutoCorrect { run(action); return false }
        // раскладка не из включённых языков Litara — набор в ней не трогаем
        guard let current, sources[current] != nil else { return true }
        // поле пароля: macOS включает защищённый ввод — ничего не трогаем
        guard !IsSecureEventInputEnabled() else { resetSession("поле пароля"); return true }
        if let action { run(action); return false }
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            resetSession("сочетание с ⌘ или ⌃")
            return true
        }
        switch code {
        case 49: return separator(" ", event)
        case 36, 76: return separator("\n", event)
        case 48: return separator("\t", event)
        case 51: session.backspace()
        case 53, 115...126: resetSession(code == 53 ? "Esc" : "клавиша перехода \(code)")  // Esc, Home/End/PgUp/PgDn, стрелки, Fn-клавиши
        default:
            // ponytail: Caps Lock не учитывается — при нём исправленное слово выйдет строчными
            let keystroke = Keystroke(code: code, shift: flags.contains(.maskShift), option: flags.contains(.maskAlternate))
            if current == .be, let pc = pcPunctuation, let text = pc.pc.chars[keystroke], text != pc.apple.chars[keystroke] {
                // на экран — знак ПК, сеансу — само нажатие: его раскладка уже со знаками ПК
                let actions = session.key(keystroke)
                if actions.isEmpty { postText(text) } else { logDecision(); perform(actions) }
                return false
            }
            let actions = session.key(keystroke)
            // исправление на лету: само нажатие уже в напечатанном тексте — проглатываем его
            if !actions.isEmpty {
                logDecision()
                perform(actions)
                return false
            }
        }
        return true
    }

    private func separator(_ separator: String, _ event: CGEvent) -> Bool {
        let actions = session.separator(separator)
        logDecision()
        if let word = session.lastRollback { onRollback?(word) }  // стёр исправление и набрал то же (B27)
        guard !actions.isEmpty else { return true }
        perform(actions)
        // сам разделитель — после исправления
        if let copy = event.copy() {
            copy.setIntegerValueField(.eventSourceUserData, value: Self.marker)
            copy.post(tap: .cgSessionEventTap)
        }
        return false
    }

    private func logDecision() {
        guard Settings.logDecisions, let line = session.lastDecision else { return }
        Settings.appendLog(line)
    }

    /// Сброс сеанса — в журнал с причиной (B5), но только когда было что стирать.
    private func resetSession(_ reason: String) {
        if Settings.logDecisions, session.hasState { Settings.appendLog("\(reason) — сеанс сброшен") }
        session.reset()
    }

    private func perform(_ actions: [TypingSession.Action]) {
        for action in actions {
            switch action {
            case let .replace(deleteCount, text):
                // с поправкой на автозакрытие скобок (R9) и на подсказку за курсором (B40, R16)
                let suggestion = deleteCount > 0 && Self.suggestionAfterCaret()
                for press in TypingSession.keypresses(deleting: deleteCount, typing: text, suggestionAfterCaret: suggestion) {
                    switch press {
                    case .text(let typed): postText(typed)
                    case .backspace: postKey(51)
                    case .forwardDelete: postKey(117)  // ⌦: стирает выделенную подсказку, без неё в конце поля — ничего
                    }
                }
            case let .switchLayout(language):
                guard let source = sources[language] else { continue }
                TISSelectInputSource(source)
            }
        }
    }

    /// Хоткеи «нажать и отпустить» (по умолчанию ⌥ — последнее слово по кругу, ⌥⇧ — следующая раскладка).
    /// Нажатая между ними клавиша или клик хоткей отменяют; дольше 0,6 с — не хоткей.
    private func modifiersChanged(_ flags: CGEventFlags) {
        if heldModifiers.isEmpty, !flags.isEmpty {
            modifierTap = (flags, Date())
        } else if !flags.isEmpty, let tap = modifierTap {
            modifierTap = (tap.flags.union(flags), tap.since)
        }
        heldModifiers = flags
        guard flags.isEmpty, let tap = modifierTap else { return }
        modifierTap = nil
        guard Date().timeIntervalSince(tap.since) < 0.6, let action = hotkeyAction(code: nil, flags: tap.flags) else { return }
        run(action)
    }

    /// Идёт запись хоткея в настройках: пока она идёт, хоткеи в окне Litara не исполняются (⌘L иначе
    /// проглотился бы, а ⌥ крутил бы слово в фоне). Ставит и снимает запись (`SettingsView.record`).
    static var recordingHotkey = false

    /// Действие назначенного хоткея; `code == nil` — модификаторы нажали и отпустили.
    /// В окнах Litara хоткеи работают, кроме записи: прежде они там не работали вовсе, и в «Моих словах»
    /// раскладку было не сменить (проба владельца 2026-10-21). Флаг, оставшийся после записи, действует
    /// только в окнах Litara — как раньше, не хуже.
    private func hotkeyAction(code: UInt16?, flags: CGEventFlags) -> HotkeyAction? {
        guard !(NSApp.isActive && Self.recordingHotkey) else { return nil }
        let action = hotkeys.first { $0.value.code == code && $0.value.flags == flags.rawValue }?.key
        // правящий текст хоткей в ненадёжном приложении не перехватывается — сочетание уходит приложению (R7)
        if let action, action != .nextLayout, action != .toggleAutoCorrect, let app = frontmostApp, Self.unreliableApps.contains(app) {
            if Settings.logDecisions { Settings.appendLog("\(app) — хоткей \(action.rawValue) пропущен: правка текста ненадёжна") }
            return nil
        }
        return action
    }

    /// В поле пароля (защищённый ввод) — только смена раскладки.
    private func run(_ action: HotkeyAction) {
        guard action == .nextLayout || action == .toggleAutoCorrect || !IsSecureEventInputEnabled() else { return }
        switch action {
        case .toggleAutoCorrect:
            onToggleAutoCorrect?()
        case .nextLayout:
            nextLayout()
        case .changeCase:
            perform(session.changeCase())
        case .transliterate:
            perform(session.transliterate(selection: selectionToEdit().text))
            logDecision()
        case .fix:
            // выделенный текст важнее последнего слова (docs/spec.md)
            let selection = selectionToEdit()
            if let text = selection.text {
                perform(session.cycleSelection(text))
                logDecision()  // и отказ: cycleSelection называет причину
            } else {
                // проба владельца 2026-10-21: в Терминале ⌥ на выделении молчал, круг «вставал» —
                // журнал называет, что ответила система и что сделал круг
                let actions = session.cycleWord()
                if Settings.logDecisions {
                    let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
                    Settings.appendLog("⌥ (выделения нет — \(app), \(selection.note)): "
                        + (actions.isEmpty ? "крутить нечего, сеанс пуст" : session.lastDecision ?? ""))
                }
                perform(actions)
                if let word = session.lastRollback { onRollback?(word) }
            }
        }
    }

    /// Выделенный текст для ⌥ и транслита: выделенная подсказка приложения за набранным словом — не выделение (B42, R17).
    /// О подсказке поле спрашивается, только когда от ответа что-то зависит: выделение есть и слово набрано.
    private func selectionToEdit() -> (text: String?, note: String) {
        let selection = Self.selectedText()
        let suggestion = selection.text != nil && session.hasState && Self.suggestionAfterCaret()
        let text = session.selectionToEdit(selection.text, suggestionAfterCaret: suggestion)
        return text == nil && selection.text != nil ? (nil, "выделена подсказка приложения") : (text, selection.note)
    }

    /// Выделенный текст поля в фокусе — через «Универсальный доступ», без буфера обмена.
    /// Приложения на Electron отдают его, только когда их попросят (`AXManualAccessibility`).
    /// Без текста — `note`: что ответила система (для журнала решений).
    private static func selectedText() -> (text: String?, note: String) {
        func read() -> (text: String?, note: String) {
            let system = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(system, 0.2)  // зависшее приложение не держит набор
            var focused: CFTypeRef?
            let found = AXUIElementCopyAttributeValue(system, "AXFocusedUIElement" as CFString, &focused)
            guard found == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
                return (nil, "фокус не отдан (AX \(found.rawValue))")
            }
            let element = focused as! AXUIElement
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(element, "AXRole" as CFString, &role)
            var value: CFTypeRef?
            let read = AXUIElementCopyAttributeValue(element, "AXSelectedText" as CFString, &value)
            guard read == .success, let text = value as? String, !text.isEmpty else {
                return (nil, "\(role as? String ?? "?"): выделение \(read == .success ? "пустое" : "не отдано (AX \(read.rawValue))")")
            }
            return (text, "")
        }
        let first = read()
        // Electron строит дерево сразу — читаем ещё раз; ChatGPT — за секунды (замер: 1–2,5 с, если просить впереди;
        // при активации — дольше 3,5 с): сработает следующее нажатие (R20)
        guard first.text == nil, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              requestAccessibility(pid) else { return first }
        return read()
    }

    /// За курсором — выделенная подсказка автодополнения (Spotlight, адресная строка): выделен хвост текста поля до конца
    /// (B40). Клик и стрелки сбрасывают сеанс, поэтому при правке слова выделение поставило приложение, а не пользователь.
    /// Многострочный текст (`AXTextArea`: Терминал, редакторы) — не подсказка: в Терминале выделение мышью набор не снимает.
    /// ponytail: признак — выделение до конца текста однострочного поля; там, где набор выделение пользователя не снимает,
    /// оно примется за подсказку и сотрётся лишний знак — тогда сравнивать текст перед выделением с напечатанным словом
    private static func suggestionAfterCaret() -> Bool {
        guard !NSApp.isActive else { return false }  // своё окно: вопрос к себе с главного потока ждал бы таймаута
        func note(_ text: String) { if Settings.logDecisions { Settings.appendLog("за курсором " + text) } }
        let system = AXUIElementCreateSystemWide()
        // правка ждёт ответа до первого Backspace, а набор идёт дальше: медленное поле — без поправки, как прежде (B43)
        AXUIElementSetMessagingTimeout(system, 0.05)
        defer { AXUIElementSetMessagingTimeout(system, 0.2) }
        var focused: CFTypeRef?, rangeValue: CFTypeRef?
        let found = AXUIElementCopyAttributeValue(system, "AXFocusedUIElement" as CFString, &focused)
        guard found == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            note("не спросить: фокус не отдан (AX \(found.rawValue))")
            return false
        }
        let element = focused as! AXUIElement
        var range = CFRange()
        let read = AXUIElementCopyAttributeValue(element, "AXSelectedTextRange" as CFString, &rangeValue)
        guard read == .success, let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID(),
              AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else {
            note("не спросить: выделение не отдано (AX \(read.rawValue))")
            return false
        }
        guard range.length > 0 else { return false }
        var role: CFTypeRef?, count: CFTypeRef?, value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, "AXRole" as CFString, &role)
        // длина текста: число знаков (дёшево и в большом поле), иначе сам текст
        let total = AXUIElementCopyAttributeValue(element, "AXNumberOfCharacters" as CFString, &count) == .success
            ? count as? Int
            : AXUIElementCopyAttributeValue(element, "AXValue" as CFString, &value) == .success ? (value as? String)?.utf16.count : nil
        let roleName = role as? String ?? "?"
        let suffix = roleName != "AXTextArea" && range.location > 0 && range.location + range.length == total
        note("выделение \(range.location)+\(range.length) из \(total.map(String.init) ?? "?") (\(roleName)): "
            + (suffix ? "подсказка приложения — стираю первым" : "не подсказка — не трогаю"))
        return suffix
    }

    private func nextLayout() {
        guard !languages.isEmpty else { return }
        let index = current.flatMap { languages.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        select(languages[index % languages.count])
    }

    private func postKey(_ code: CGKeyCode) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { continue }
            event.flags = []
            event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
            event.post(tap: .cgSessionEventTap)
        }
    }

    private func postText(_ text: String) {
        let units = Array(text.utf16)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else { continue }
            event.flags = []
            units.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: $0.baseAddress) }
            event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
            event.post(tap: .cgSessionEventTap)
        }
    }

    private func inputSourceChanged() {
        let language = Self.currentID().flatMap { languageByID[$0] }
        current = language
        // раскладка та, в которой сеанс уже ведётся, — своё переключение или повтор уведомления о нём.
        // Прежний флажок «переключаю сам» гасился первым уведомлением, и второе (повтор, опоздание)
        // сбрасывало круг хоткея как ручная смена раскладки
        // (проба владельца 2026-10-21: круг останавливался после первого шага)
        if let language, language == session.current {
        } else if let language, sources[language] != nil {
            if Settings.logDecisions { Settings.appendLog("раскладку сменили не через Litara (\(language.rawValue)) — сеанс сброшен") }
            session.layoutChanged(to: language)
        } else {
            resetSession("раскладка не из языков Litara")
        }
        onLanguageChange?(language)
    }

    private static func id(of source: TISInputSource) -> String? {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }
}

private let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    // источник перехвата добавлен в главный цикл (installTap) — колбэк всегда на главном потоке
    nonisolated(unsafe) let event = event
    let pass = MainActor.assumeIsolated { monitor.handle(type, event) }
    return pass ? Unmanaged.passUnretained(event) : nil
}
