# Словари

Исходные словари hunspell, по которым Litara определяет язык слова. Скачаны 2026-10-20. У
каждого — свой файл лицензии (`<язык>/license`), он идёт вместе со словарём.

| Язык | Источник | Лицензия (как указано в файле) |
|------|----------|--------------------------------|
| en | [wooorm/dictionaries `en`](https://github.com/wooorm/dictionaries/tree/main/dictionaries/en) — SCOWL, en_US | разрешительная лицензия SCOWL (MIT/BSD-подобная) |
| ru | [wooorm/dictionaries `ru`](https://github.com/wooorm/dictionaries/tree/main/dictionaries/ru) — А. Лебедев | BSD-подобная, © 1997–2008 Alexander I. Lebedev |
| pl | [wooorm/dictionaries `pl`](https://github.com/wooorm/dictionaries/tree/main/dictionaries/pl) — SJP.PL | GPL, LGPL, MPL или CC ShareAlike — на выбор |
| uk | [wooorm/dictionaries `uk`](https://github.com/wooorm/dictionaries/tree/main/dictionaries/uk) — dict_uk | GPL-3.0 |
| be | [LibreOffice/dictionaries `be_BY`](https://github.com/LibreOffice/dictionaries/tree/master/be_BY) — официальное правописание 2008, Belarusian Grammar Database | CC BY-SA 4.0 или LGPLv3 |

Все совместимы с GPL-3.0, под которой выходит Litara.

**Имена и города** — `<язык>/names.dic`, собраны `scripts/build_names.py` 2026-10-22 из
[Wikidata](https://www.wikidata.org) (CC0, без ограничений) через [QLever](https://qlever.cs.uni-freiburg.de):
личные имена с подписью на языке и не меньше 3 статей Википедии; населённые пункты Польши, Беларуси, Украины,
России и Литвы от 5 000 жителей и мира от 100 000. Флаги падежей — из `<язык>/index.aff` этого же словаря.

**Производные файлы.** `Sources/LitaraCore/Resources/<язык>.bloom` — фильтры слов, собранные из
этих словарей; на них распространяются те же лицензии. Пересборка: `scripts/build_dictionaries.sh`
(разворачивает словарь в словоформы `scripts/expand_hunspell.py` и сжимает их `dictgen`).
