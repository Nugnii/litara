// Собирает фильтр слов: слова из stdin (по одному на строку) → файл, путь которого — последний аргумент.
// С флагом --prefixes — фильтр начал слов длиной WordFilter.prefixRange; с --check — проверочный
// фильтр тех же слов с другим хешем (WordFilter.checkMarker), для исправления опечаток; с --trigrams —
// не фильтр, а список троек букв слов (LanguageDetector.trigrams), по одной на строку.
// Зовётся из scripts/build_dictionaries.sh.
import LitaraCore
import Foundation

let prefixes = CommandLine.arguments.contains("--prefixes")
let check = CommandLine.arguments.contains("--check")
let trigrams = CommandLine.arguments.contains("--trigrams")
var items = Set<String>()
var endings: [String: Int] = [:]
while let line = readLine() {
    guard !line.isEmpty else { continue }
    if prefixes {
        let chars = Array(line)
        for n in WordFilter.prefixRange where n <= chars.count { items.insert(String(chars[..<n])) }
    } else if check {
        items.insert(WordFilter.checkMarker + line)
        if line.count >= 3 { endings[String(line.lowercased().suffix(3)), default: 0] += 1 }
    } else if trigrams {
        items.formUnion(LanguageDetector.trigrams(of: line))
    } else {
        items.insert(line)
    }
}
let path = CommandLine.arguments.last!
if trigrams {
    try (items.sorted().joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    print("\(path): \(items.count) троек")
    exit(0)
}
// обычное окончание (три последние буквы у 15+ слов): у опечатки оно ломается — «приевт», «-евт» у 5 слов,
// а у сленга остаётся обычным — «каменты», «-нты» у 299 (замер 2026-10-21)
for (ending, count) in endings where count >= 15 { items.insert(WordFilter.endingMarker + ending) }
let data = WordFilter(words: items, count: items.count).serialized()
try data.write(to: URL(fileURLWithPath: path))
print("\(path): \(items.count) \(prefixes ? "начал" : "слов"), \(data.count / 1024) КБ")
