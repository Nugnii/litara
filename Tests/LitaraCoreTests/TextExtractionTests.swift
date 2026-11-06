import Foundation
import Testing
@testable import LitaraCore

@Test func telegramExportTextIsTakenOnce() throws {
    // формат Telegram Desktop: text — строка или массив с форматированием, text_entities — тот же текст
    let json = """
    {"name": "Чат", "messages": [
      {"id": 1, "text": "кринжово было", "text_entities": [{"type": "plain", "text": "кринжово было"}]},
      {"id": 2, "text": ["смотри ", {"type": "bold", "text": "кринжово"}],
       "text_entities": [{"type": "plain", "text": "смотри "}, {"type": "bold", "text": "кринжово"}]},
      {"id": 3, "text": ["раз", {"type": "bold", "text": "віццё"}]}
    ]}
    """
    let text = try #require(TextExtraction.telegramText(from: Data(json.utf8))?.personal)
    #expect(text.components(separatedBy: "кринжово").count - 1 == 2)
    #expect(text.contains("смотри") && !text.contains("Чат"))
    // смена форматирования посреди слова не рвёт его
    #expect(text.contains("развіццё"))
}

@Test @MainActor func groupChatWordsNeedFourOccurrences() throws {
    // экспорт всего аккаунта: личный чат и общий (решение владельца 2026-11-02, B17: из общего — с 4 раз, не с 2)
    let json = """
    {"chats": {"list": [
      {"type": "personal_chat", "messages": [{"text": "рофлить"}, {"text": "рофлить"}]},
      {"type": "public_supergroup", "messages": [
        {"text": "вайбово хайпануть"}, {"text": "вайбово хайпануть"}, {"text": "вайбово хайпануть"}, {"text": "хайпануть"}
      ]}
    ]}}
    """
    let (personal, group) = try #require(TextExtraction.telegramText(from: Data(json.utf8)))
    #expect(personal.contains("рофлить") && !personal.contains("вайбово"))
    let (detector, _) = try makeDetector()
    // «рофлить» — дважды в личном; «хайпануть» — 4 раза в общем; «вайбово» — 3 раза в общем, мало
    #expect(detector.learnableWords(in: personal, group: group) == ["рофлить", "хайпануть"])
    // личное и общее складываются: раз в личном (за два) и дважды в общем — четыре
    #expect(detector.learnableWords(in: "вайбово", group: "вайбово вайбово") == ["вайбово"])
}
