/// Языки, которые Litara различает. Код — ISO 639-1, как его отдаёт macOS у раскладки.
public enum Language: String, CaseIterable, Sendable {
    case ru, be, uk, en, pl

    /// Кириллица ↔ кириллица исправляется целым предложением, латиница ↔ кириллица — словом.
    public var isCyrillic: Bool { self == .ru || self == .be || self == .uk }
}
