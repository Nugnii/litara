import Foundation

/// Компактное множество слов: отвечает «точно нет» или «почти наверняка да».
///
/// ponytail: фильтр Блума, ≈0,01% ложных «да» при 19,2 бита на слово (все 5 языков ≈22 МБ против
/// 183 МБ списков). 0,1% (17 МБ) давало на тестовом наборе на 14 верных решений меньше.
/// Если ложные «да» снова начнут мешать — точный автомат (DAWG).
public struct WordFilter: Sendable {
    private let bits: [UInt8]
    private let bitCount: UInt64
    private let hashCount: Int

    private static let magic = Data("BLWF".utf8)

    public init(words: some Sequence<String>, count: Int, falsePositiveRate: Double = 0.0001) {
        let n = Double(max(count, 1))
        let m = (-n * log(falsePositiveRate) / (log(2) * log(2))).rounded(.up)
        bitCount = UInt64(m)
        hashCount = max(1, Int((m / n * log(2)).rounded()))
        var bits = [UInt8](repeating: 0, count: Int((bitCount + 7) / 8))
        for word in words {
            for position in Self.positions(word, bitCount: bitCount, hashCount: hashCount) {
                bits[Int(position / 8)] |= 1 << (position % 8)
            }
        }
        self.bits = bits
    }

    public func contains(_ word: String) -> Bool {
        Self.positions(word, bitCount: bitCount, hashCount: hashCount).allSatisfy {
            bits[Int($0 / 8)] & (1 << ($0 % 8)) != 0
        }
    }

    /// Формат файла: «BLWF», число бит (UInt64, little-endian), число хешей (UInt32), биты.
    public func serialized() -> Data {
        var data = Self.magic
        withUnsafeBytes(of: bitCount.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(hashCount).littleEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: bits)
        return data
    }

    public init?(data: Data) {
        let header = Self.magic.count + 12
        guard data.count > header, data.prefix(Self.magic.count) == Self.magic else { return nil }
        let bytes = [UInt8](data)
        let bitCount = bytes[4..<12].reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        let hashCount = bytes[12..<16].reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard bitCount > 0, hashCount > 0, UInt64(bytes.count - header) == (bitCount + 7) / 8 else { return nil }
        self.bitCount = bitCount
        self.hashCount = Int(hashCount)
        self.bits = Array(bytes[header...])
    }

    /// Начала слов, известные фильтру начал: длиной от 3 до этого числа букв. Длиннее — неизвестно.
    /// ponytail: 8 букв — 3,6 млн начал на 5 языков (≈9 МБ); все длины — 15,8 млн (≈38 МБ)
    public static let prefixRange = 3...8

    /// Фильтр слов языка, собранный scripts/build_dictionaries.sh из словаря hunspell.
    public static func bundled(_ language: Language) -> WordFilter? {
        load("\(language.rawValue)")
    }

    /// Фильтр начал слов языка (длиной `prefixRange`) — для исправления на лету.
    public static func bundledPrefixes(_ language: Language) -> WordFilter? {
        load("\(language.rawValue).prefix")
    }

    /// Проверочный фильтр тех же слов (ru, be): слово хранится с `checkMarker` впереди, то есть с
    /// другими битами. Исправление опечатки проверяет ≈300 вариантов слова — при 0,01% ложных «да»
    /// это ≈3% слов с вымышленным вариантом; слово, с которым согласны оба фильтра, — ≈1e-8.
    public static func bundledCheck(_ language: Language) -> WordFilter? {
        load("\(language.rawValue).check")
    }

    public static let checkMarker = "\u{1}"
    /// В проверочном фильтре — ещё и окончания слов (три последние буквы) с этой меткой.
    public static let endingMarker = "\u{2}"

    private static func load(_ name: String) -> WordFilter? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "bloom", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        return WordFilter(data: data)
    }

    // Двойное хеширование (Кирш — Митценмахер) поверх 64-битного FNV-1a от UTF-8 слова.
    private static func positions(_ word: String, bitCount: UInt64, hashCount: Int) -> [UInt64] {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in word.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        let h1 = hash & 0xffff_ffff, h2 = (hash >> 32) | 1
        return (0..<UInt64(hashCount)).map { (h1 &+ $0 &* h2) % bitCount }
    }
}
