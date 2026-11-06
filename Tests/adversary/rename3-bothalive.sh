#!/bin/bash
# Противник переименования blalb → Litara (B34), раунд 3: оба приложения живы.
# До переименования новая сборка заменяла прежнюю на месте (тот же идентификатор и путь) — двух перехватов набора быть
# не могло. Теперь blalb (dev.blalb.app) и Litara — разные приложения: автозапуск blalb 0.28.0 (его SMAppService.mainApp,
# git show 802d2d2:Sources/blalb/SettingsView.swift:130) Litara снять не может, и после отката с возвратом, если
# build/blalb.app остался, при входе запускаются оба. Каждое слово тогда исправляют два перехвата.
# Приложение запускать нельзя — проверка по коду: кроме вызова переноса настроек Litara хоть где-то обращается
# к dev.blalb.app (запущен ли, предупредить, выйти).
set -uo pipefail
cd "$(dirname "$0")/../.."
FAIL=0

USES="$(grep -n 'dev\.blalb\.app' Sources/Litara/*.swift | grep -v -E '^[^:]+:[0-9]+: *//' | grep -v 'SettingsMigration\.migrate(')"
if [[ -z "$USES" ]]; then
  echo "FAIL: Litara не замечает запущенный blalb — два перехвата набора одновременно. Все упоминания dev.blalb.app:"
  grep -n 'dev\.blalb\.app' Sources/Litara/*.swift
  FAIL=1
fi

exit $(( FAIL != 0 ))
