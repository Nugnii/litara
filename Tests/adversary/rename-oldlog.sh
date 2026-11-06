#!/bin/bash
# Противник переименования blalb → Litara (B34): журнал решений под прежним именем.
# blalb писал набранные слова в ~/Library/Logs/blalb/decisions.log; Litara пишет в ~/Library/Logs/Litara/decisions.log
# (Settings.swift: logURL), а подсказка «содержит набранные слова; после отладки выключите и удалите» (L10n.swift,
# .logHint) называет только новый путь. Утверждение: о прежнем журнале приложение знает — переносит его или
# называет. Проверка по коду, живой журнал не читается.
set -uo pipefail
cd "$(dirname "$0")/../.."
FAIL=0

OUT="$(grep -n -F 'Logs/blalb' Sources/Litara/*.swift Sources/LitaraCore/*.swift)"
if [[ -z "$OUT" ]]; then
  echo "FAIL: прежний журнал ~/Library/Logs/blalb/decisions.log в коде не упомянут — не переносится и не назван:"
  grep -n -F 'Logs/Litara' Sources/Litara/Settings.swift
  FAIL=1
fi

exit $(( FAIL != 0 ))
