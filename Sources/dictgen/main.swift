// Собирает фильтр слов: слова из stdin (по одному на строку) → файл, путь которого — последний аргумент.
// С флагом --prefixes — фильтр начал слов длиной WordFilter.prefixRange; с --check — проверочный
// фильтр тех же слов с другим хешем (WordFilter.checkMarker), для исправления опечаток.
// Зовётся из scripts/build_dictionaries.sh.
import LitaraCore
import Foundation

let prefixes = CommandLine.arguments.contains("--prefixes")
let check = CommandLine.arguments.contains("--check")
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
    } else {
        items.insert(line)
    }
}
// обычное окончание (три последние буквы у 15+ слов): у опечатки оно ломается — «приевт», «-евт» у 5 слов,
// а у сленга остаётся обычным — «каменты», «-нты» у 299 (замер 2026-10-21)
for (ending, count) in endings where count >= 15 { items.insert(WordFilter.endingMarker + ending) }
let path = CommandLine.arguments.last!
let data = WordFilter(words: items, count: items.count).serialized()
try data.write(to: URL(fileURLWithPath: path))
print("\(path): \(items.count) \(prefixes ? "начал" : "слов"), \(data.count / 1024) КБ")
