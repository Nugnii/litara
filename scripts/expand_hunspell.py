#!/usr/bin/env python3 -I
"""Разворачивает словарь hunspell (.dic + .aff) в полный список словоформ: по слову на строку,
строчными буквами, без повторов, по алфавиту.

Поддержано то, что встречается в словарях Litara: SFX/PFX с условиями, перекрёстные
приставка+окончание, окончания с собственными флагами (двойные окончания), FLAG
char/long/num/UTF-8, IGNORE. Составные слова (COMPOUND*) не разворачиваются: слова с флагом
ONLYINCOMPOUND пропускаются.

Запуск: scripts/expand_hunspell.py Dictionaries/ru/index.aff Dictionaries/ru/index.dic > out.txt
"""
import re
import sys


# Апостроф в словарях бывает разный (’ ʼ); в списках всегда ASCII ', как его печатают раскладки.
APOSTROPHES = str.maketrans({"’": "'", "ʼ": "'"})


def parse_flags(s, flag_type):
    if not s:
        return []
    if flag_type == "long":
        return [s[i:i + 2] for i in range(0, len(s), 2)]
    if flag_type == "num":
        return [f for f in s.split(",") if f]
    return list(s)  # char и UTF-8: по символу


class Affix:
    __slots__ = ("kind", "flag", "cross", "strip", "add", "cont", "cond")

    def __init__(self, kind, flag, cross, strip, add, cont, cond):
        self.kind, self.flag, self.cross = kind, flag, cross
        self.strip, self.add, self.cont = strip, add, cont
        pattern = "" if cond == "." else cond
        self.cond = re.compile(pattern + "$" if kind == "SFX" else "^" + pattern) if pattern else None

    def apply(self, word):
        if self.cond and not self.cond.search(word):
            return None
        if self.kind == "SFX":
            if self.strip and not word.endswith(self.strip):
                return None
            base = word[: len(word) - len(self.strip)] if self.strip else word
            return base + self.add
        if self.strip and not word.startswith(self.strip):
            return None
        return self.add + word[len(self.strip):]


def parse_aff(path):
    flag_type, ignore, only_in_compound = "char", "", None
    affixes = {}  # флаг → [Affix]
    headers = {}  # (kind, flag) → cross
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.split()
            if not parts or parts[0].startswith("#"):
                continue
            key = parts[0]
            if key == "FLAG" and len(parts) > 1:
                flag_type = parts[1]
            elif key == "IGNORE" and len(parts) > 1:
                ignore = parts[1]
            elif key == "ONLYINCOMPOUND" and len(parts) > 1:
                only_in_compound = parts[1]
            elif key in ("SFX", "PFX") and len(parts) >= 4:
                flag = parts[1]
                if (key, flag) not in headers and parts[2] in ("Y", "N") and len(parts) == 4:
                    headers[(key, flag)] = parts[2] == "Y"
                    continue
                strip = "" if parts[2] == "0" else parts[2]
                add_field = parts[3]
                add, _, cont = add_field.partition("/")
                add = "" if add == "0" else add
                cond = parts[4] if len(parts) > 4 else "."
                cross = headers.get((key, flag), False)
                affixes.setdefault(flag, []).append(
                    Affix(key, flag, cross, strip, add, parse_flags(cont, flag_type), cond))
    return flag_type, ignore, only_in_compound, affixes


def expand(word, flags, affixes, depth=0):
    """Слово и все его формы по флагам; окончания с собственными флагами — ещё один уровень."""
    forms = {word}
    suffixed = []
    prefixes = []
    for flag in flags:
        for a in affixes.get(flag, ()):
            if a.kind == "PFX":
                prefixes.append(a)
                continue
            w = a.apply(word)
            if w is None:
                continue
            forms.add(w)
            suffixed.append((w, a))
            if a.cont and depth < 1:
                forms |= expand(w, a.cont, affixes, depth + 1)
    for p in prefixes:
        w = p.apply(word)
        if w is not None:
            forms.add(w)
        if p.cross:
            for sw, s in suffixed:
                if s.cross:
                    pw = p.apply(sw)
                    if pw is not None:
                        forms.add(pw)
    return forms


def main(aff_path, dic_path):
    flag_type, ignore, only_in_compound, affixes = parse_aff(aff_path)
    strip_ignored = str.maketrans("", "", ignore)
    words = set()
    with open(dic_path, encoding="utf-8", errors="replace") as f:
        next(f)  # первая строка — число слов
        for line in f:
            line = line.rstrip("\n")
            if not line or line.startswith(("#", "\t")):
                continue
            entry = line.split("\t", 1)[0].split(" ", 1)[0]
            # косая черта внутри слова экранируется как \/
            m = re.match(r"((?:\\/|[^/])+)(?:/(.*))?$", entry)
            if not m:
                continue
            word = m.group(1).replace("\\/", "/")
            flags = parse_flags(m.group(2) or "", flag_type)
            if only_in_compound and only_in_compound in flags:
                continue
            for form in expand(word, flags, affixes):
                form = form.translate(strip_ignored).translate(APOSTROPHES)
                if form and all(ch.isalpha() or ch in "'-" for ch in form):
                    words.add(form)
    sys.stdout.write("\n".join(sorted(words)))
    sys.stdout.write("\n")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
