#!/usr/bin/env python3 -I
"""Имена и города из Wikidata → Dictionaries/<язык>/names.dic (просьба владельца 2026-10-22: имена и города должны
быть в словарях).

Источник — Wikidata (CC0), запросы через QLever. Имена — элементы «личное имя» (мужское, женское,
общее) с подписью на языке и не меньше MIN_SITELINKS статей Википедии; города — населённые пункты
Польши, Беларуси, Украины, России и Литвы от 5 000 жителей и мира от 100 000. Берутся подписи из
одного слова с заглавной, которых в словаре языка ещё нет ни в какой форме.

Падежи: у нового слова флаги hunspell образца — слова того же словаря с заглавной и самым длинным
общим окончанием (2–5 букв; при равенстве — самые частые флаги у этого окончания): «Илона» склоняется,
как «Ирина». ponytail: образец по окончанию не знает рода — «Любовь» могла бы получить флаги «Гав»;
понадобится — брать образец из того же рода (у имён род есть в Wikidata).

Запуск: scripts/build_names.py [MIN_SITELINKS]   (по умолчанию 3), затем scripts/build_dictionaries.sh.
"""
import collections
import csv
import importlib.util
import io
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LANGS = ("en", "ru", "be", "uk", "pl")
UA = "litara-dictionary-build/0.1 (github.com/Nugnii/litara)"
ENDPOINT = "https://qlever.cs.uni-freiburg.de/api/wikidata"
PREFIXES = """PREFIX wd: <http://www.wikidata.org/entity/> PREFIX wdt: <http://www.wikidata.org/prop/direct/>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#> PREFIX wikibase: <http://wikiba.se/ontology#> """
LANG_FILTER = 'FILTER(?lang IN ("ru","be","uk","pl","en"))'
NAMES = """SELECT ?i ?lang ?l ?n WHERE { VALUES ?t { wd:Q11879590 wd:Q12308941 wd:Q202444 wd:Q3409032 }
 ?i wdt:P31 ?t . ?i rdfs:label ?l . BIND(LANG(?l) AS ?lang) %s OPTIONAL { ?i wikibase:sitelinks ?n } }""" % LANG_FILTER
CITIES = """SELECT ?i ?lang ?l ?n WHERE { ?i wdt:P31/wdt:P279* wd:Q486972 . ?i wdt:P1082 ?n . ?i wdt:P17 ?c .
 FILTER((?c IN (wd:Q36, wd:Q184, wd:Q212, wd:Q159, wd:Q37) && ?n >= 5000) || ?n >= 100000)
 ?i rdfs:label ?l . BIND(LANG(?l) AS ?lang) %s }""" % LANG_FILTER
WORD = re.compile(r"^[^\W\d_]+(?:['-][^\W\d_]+)*$")


def query(sparql):
    url = ENDPOINT + "?" + urllib.parse.urlencode({"query": PREFIXES + sparql})
    request = urllib.request.Request(url, headers={"Accept": "text/csv", "User-Agent": UA})
    return list(csv.DictReader(io.StringIO(urllib.request.urlopen(request, timeout=600).read().decode("utf-8"))))


def labels(rows, minimum):
    """{язык: {подпись}} — элементы Wikidata (не лексемы), одно слово с заглавной, мера ≥ minimum."""
    out = collections.defaultdict(set)
    for row in rows:
        if "/entity/Q" not in row["i"]:
            continue
        label = row["l"].strip().replace("’", "'")
        if WORD.match(label) and label[0].isupper() and not label.isupper() and float(row["n"] or 0) >= minimum:
            out[row["lang"]].add(label)
    return out


def load_expander():
    sys.dont_write_bytecode = True  # без scripts/__pycache__ в рабочем дереве
    spec = importlib.util.spec_from_file_location("expand_hunspell", ROOT / "scripts/expand_hunspell.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_dic(path):
    """(основа, флаги как записаны) по строкам .dic."""
    with open(path, encoding="utf-8", errors="replace") as f:
        next(f)
        for line in f:
            entry = line.rstrip("\n").split("\t", 1)[0].split(" ", 1)[0]
            m = re.match(r"((?:\\/|[^/])+)(?:/(.*))?$", entry)
            if m and not entry.startswith("#"):
                yield m.group(1).replace("\\/", "/"), m.group(2) or ""


# Те же клавиши в другой раскладке: буква → клавиша (буквой «Русской – ПК») → буква. Факты о раскладках —
# docs/spec.md: в белорусской «і ў '» на месте «и щ ъ», в «Украинской – ПК» «і є ї» на месте «ы э ъ»;
# латиница — ЙЦУКЕН. ponytail: только буквы, где раскладки расходятся; ё и знаки не учтены.
LATIN = dict(zip("qwertyuiop[]asdfghjkl;'zxcvbnm,.`", "йцукенгшщзхъфывапролджэячсмитьбюё"))
TO_KEY = {"ru": {}, "be": {"і": "и", "ў": "щ", "'": "ъ"}, "uk": {"і": "ы", "є": "э", "ї": "ъ"}, "en": LATIN, "pl": LATIN}
FROM_KEY = {lang: {v: k for k, v in m.items()} for lang, m in TO_KEY.items()}


def twin(word, source, target):
    """Что напечатают клавиши слова `source` в раскладке `target` (строчными); None — нечем напечатать."""
    keys = [TO_KEY[source].get(ch, ch) for ch in word.lower()]
    if source in ("en", "pl") and any(ch not in LATIN.values() for ch in keys):
        return None
    if target in ("en", "pl"):
        back = {v: k for k, v in LATIN.items()}
        return "".join(back.get(k, "?") for k in keys)
    return "".join(FROM_KEY[target].get(k, k) for k in keys)


def known_forms(lang, ex):
    """Формы словаря строчными — обычных слов и аббревиатур (common) и имён собственных (proper), образцы
    склонения по окончаниям и флаги hunspell."""
    flag_type, _, only_in_compound, affixes = ex.parse_aff(ROOT / f"Dictionaries/{lang}/index.aff")
    common, proper, by_suffix = set(), set(), collections.defaultdict(collections.Counter)
    for stem, flags in read_dic(ROOT / f"Dictionaries/{lang}/index.dic"):
        parsed = ex.parse_flags(flags, flag_type)
        if only_in_compound and only_in_compound in parsed:
            continue
        name = stem[:1].isupper() and not stem.isupper()
        (proper if name else common).update(form.lower() for form in ex.expand(stem, parsed, affixes))
        # образцы — слова с заглавной (имена, города), не аббревиатуры
        if flags and name:
            for k in range(2, 6):
                if len(stem) > k:
                    by_suffix[stem[-k:].lower()][flags] += 1
    return common, proper, by_suffix, (flag_type, affixes)


def build(lang, words, ex, known, by_suffix, aff, shadowing):
    flag_type, affixes = aff
    lines = []
    for word in sorted(words):
        # короче трёх букв и тень чужого слова — не добавляются: «Ши» делало русским белорусское «ШІ»,
        # набранное в русской раскладке, «Кали» — «калі» (замер на чате «Беларускі ШІ» 2026-10-22)
        if word.lower() in known or len(word) < 3 or word in shadowing:
            continue
        flags = ""
        for k in range(min(5, len(word) - 1), 1, -1):
            if by_suffix[word[-k:].lower()]:
                flags = by_suffix[word[-k:].lower()].most_common(1)[0][0]
                break
        # образец годится, только если его окончания подошли и к этому слову: форм больше одной
        if flags and len(ex.expand(word, ex.parse_flags(flags, flag_type), affixes)) < 2:
            flags = ""
        lines.append(f"{word}/{flags}" if flags else word)
    path = ROOT / f"Dictionaries/{lang}/names.dic"
    path.write_text(f"{len(lines)}\n" + "".join(line + "\n" for line in lines), encoding="utf-8")
    print(f"{lang}: {len(lines)} новых слов → {path.relative_to(ROOT)}")


def main():
    minimum = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    names, cities = labels(query(NAMES), minimum), labels(query(CITIES), 0)
    words = {lang: names[lang] | cities[lang] for lang in LANGS}
    ex = load_expander()
    # тень: новое слово языка A, чьи клавиши в раскладке B дают обычное слово словаря B (имя на имя —
    # не тень: «Илона» и белорусское «Ілона» — форма имени «Ілон»). Словари — по одному в памяти
    # (польский и украинский — по 3,5 млн форм)
    shadowing = collections.defaultdict(set)
    for target in LANGS:
        common, _, _, _ = known_forms(target, ex)
        for source in LANGS:
            if source == target:
                continue
            for word in words[source]:
                t = twin(word, source, target)
                if t and t != word.lower() and t in common:
                    shadowing[source].add(word)
        del common
    for lang in LANGS:
        common, proper, by_suffix, aff = known_forms(lang, ex)
        build(lang, words[lang], ex, common | proper, by_suffix, aff, shadowing[lang])
        print(f"   {lang}: в тени чужих слов {len(shadowing[lang])}")


if __name__ == "__main__":
    main()
