#!/usr/bin/env python3 -I
"""Тестовый набор для определения языка: N случайных словоформ из развёрнутого словаря.

Выборка равномерная по словоформам словаря, а не по частоте в живой речи: редких форм в ней
больше, чем в настоящем тексте. Seed фиксирован — набор воспроизводим.

Запуск: scripts/expand_hunspell.py X.aff X.dic | scripts/sample_corpus.py 500 > Tests/LitaraCoreTests/Fixtures/<язык>.txt
"""
import random
import sys

n = int(sys.argv[1])
words = [w for w in sys.stdin.read().split("\n") if len(w) >= 2]
sys.stdout.write("\n".join(sorted(random.Random(2026).sample(words, n))) + "\n")
