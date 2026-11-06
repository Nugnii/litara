#!/bin/bash
# Противник переименования blalb → Litara (B34): автозапуск при входе.
# Автозапуск blalb — запись SMAppService.mainApp под dev.blalb.app (Настройки → Основные → Объекты входа). В домене
# настроек dev.blalb.app её нет, поэтому SettingsMigration её не переносит; SMAppService.mainApp у Litara — новая
# запись под io.github.nugnii.litara, по умолчанию не зарегистрирована. Приложение запускать нельзя — проверка по коду:
# автозапуск переезжает, только если кроме переключателя в настройках (SettingsView.swift) есть путь, связанный
# с переездом, — в AppDelegate.swift или Settings.swift.
set -uo pipefail
cd "$(dirname "$0")/../.."
FAIL=0

OUT="$(grep -n -E 'SMAppService|launchAtLogin' Sources/Litara/AppDelegate.swift Sources/Litara/Settings.swift)"
if [[ -z "$OUT" ]]; then
  echo "FAIL: автозапуск blalb при переезде теряется — SMAppService вызывается только из переключателя:"
  grep -n 'SMAppService' Sources/Litara/SettingsView.swift
  FAIL=1
fi

MIG="$(cat Sources/LitaraCore/SettingsMigration.swift)"
if ! grep -q -E 'SMAppService|launchAtLogin|loginItem' <<< "$MIG"; then
  echo "     SettingsMigration переносит только UserDefaults (Sources/LitaraCore/SettingsMigration.swift)"
fi

exit $(( FAIL != 0 ))
