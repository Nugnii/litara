#!/bin/bash
# Пересобирает фильтры: Dictionaries/<язык>/index.{aff,dic} → Sources/LitaraCore/Resources/<язык>.bloom
# (слова) и <язык>.prefix.bloom (начала слов для исправления на лету)
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product dictgen
dictgen="$(swift build -c release --show-bin-path)/dictgen"
out=Sources/LitaraCore/Resources
mkdir -p "$out"
words=$(mktemp -d)
trap 'rm -rf "$words"' EXIT
for lang in en ru be uk pl; do
  python3 -I scripts/expand_hunspell.py "Dictionaries/$lang/index.aff" "Dictionaries/$lang/index.dic" > "$words/$lang.txt"
  # имена и города из Wikidata (scripts/build_names.py) — тот же .aff, флаги образцов этого словаря
  if [ -f "Dictionaries/$lang/names.dic" ]; then
    python3 -I scripts/expand_hunspell.py "Dictionaries/$lang/index.aff" "Dictionaries/$lang/names.dic" >> "$words/$lang.txt"
  fi
  "$dictgen" "$out/$lang.bloom" < "$words/$lang.txt"
  "$dictgen" --prefixes "$out/$lang.prefix.bloom" < "$words/$lang.txt"
  # тройки букв слов — для слова вне словарей (LanguageDetector.impossibleCorrection)
  "$dictgen" --trigrams "$out/$lang.trigrams" < "$words/$lang.txt"
  # проверочный фильтр — только языкам, где исправляются опечатки (docs/spec.md)
  case $lang in ru|be) "$dictgen" --check "$out/$lang.check.bloom" < "$words/$lang.txt" ;; esac
done
