import Foundation

/// Текст для обучения словам: экспорт Telegram Desktop или обычный текст.
public enum TextExtraction {
    /// Все поля «text» экспорта Telegram (result.json; строка или массив с форматированием): личная переписка
    /// и общие чаты — группы и каналы — порознь; из общего слово учится с большего числа повторов (B17).
    /// `text_entities` пропускается: там тот же текст ещё раз, и слово, сказанное однажды,
    /// посчиталось бы дважды и прошло бы порог «встречено не меньше двух раз».
    public static func telegramText(from data: Data) -> (personal: String, group: String)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var personal: [String] = [], group: [String] = []
        // куски одного сообщения (смена форматирования посреди слова) склеиваются без разделителя
        func appendText(_ value: Any, inGroup: Bool) {
            var part: String?
            if let string = value as? String { part = string }
            if let array = value as? [Any] {
                part = array.map { ($0 as? String) ?? (($0 as? [String: Any])?["text"] as? String) ?? "" }.joined()
            }
            if let part { if inGroup { group.append(part) } else { personal.append(part) } }
        }
        func walk(_ value: Any, inGroup: Bool) {
            if let dict = value as? [String: Any] {
                // чат — словарь с messages; тип общего: private_group, private_supergroup, public_supergroup
                // (экспорты владельца, 2026-11-02) и каналы; personal_chat, bot_chat, saved_messages — личное
                var inGroup = inGroup
                if dict["messages"] != nil, let type = dict["type"] as? String {
                    inGroup = type.hasSuffix("group") || type.hasSuffix("channel")
                }
                for (key, child) in dict where key != "text_entities" {
                    if key == "text" { appendText(child, inGroup: inGroup) } else { walk(child, inGroup: inGroup) }
                }
            } else if let array = value as? [Any] {
                array.forEach { walk($0, inGroup: inGroup) }
            }
        }
        walk(json, inGroup: false)
        return (personal.joined(separator: "\n"), group.joined(separator: "\n"))
    }
}
