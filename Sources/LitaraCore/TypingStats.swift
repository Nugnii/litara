/// Статистика набора как у Punto (docs/spec.md, критерии этапа 5): считает сеанс, копит приложение.
/// Поля — приращения: ⌫, снова открывший слово, вычитает его из `words`.
public struct TypingStats: Equatable, Sendable {
    /// Законченные слова (с буквой).
    public var words = 0
    /// Раскладка исправлена сама — по пробелу или на лету.
    public var autoSwitches = 0
    /// Опечатка исправлена сама (и дефис: «кто то» → «кто-то»).
    public var typoFixes = 0
    /// Хоткей «исправить» перевёл слово или выделение — первое нажатие, если оно не откат.
    public var manualFixes = 0
    /// Хоткей вернул автоисправленное к набранному.
    public var rollbacks = 0

    public init() {}

    public init(_ dictionary: [String: Int]) {
        words = dictionary["words"] ?? 0
        autoSwitches = dictionary["autoSwitches"] ?? 0
        typoFixes = dictionary["typoFixes"] ?? 0
        manualFixes = dictionary["manualFixes"] ?? 0
        rollbacks = dictionary["rollbacks"] ?? 0
    }

    public var dictionary: [String: Int] {
        ["words": words, "autoSwitches": autoSwitches, "typoFixes": typoFixes, "manualFixes": manualFixes, "rollbacks": rollbacks]
    }

    public static func + (a: TypingStats, b: TypingStats) -> TypingStats {
        var sum = a
        sum.words += b.words
        sum.autoSwitches += b.autoSwitches
        sum.typoFixes += b.typoFixes
        sum.manualFixes += b.manualFixes
        sum.rollbacks += b.rollbacks
        return sum
    }
}
