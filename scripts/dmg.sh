#!/bin/bash
# Собирает build/Litara-<версия>.dmg для установки на другой Mac: приложение и ярлык «Программы».
# Рабочую build/Litara.app не трогает — сборка идёт в build/dmg/.
#
# Подпись — та же, что в bundle.sh. С Developer ID и профилем нотаризации «blalb-notary» в связке ключей
# (`xcrun notarytool store-credentials blalb-notary …`) приложение и DMG уходят на проверку Apple и получают печать
# (B30) — на другом Mac запуск без предупреждения. Без них — как раньше: первый запуск блокируется, Настройки →
# Конфиденциальность и безопасность → «Всё равно открыть».
set -euo pipefail
cd "$(dirname "$0")/.."
stage=build/dmg
rm -rf "$stage"
scripts/bundle.sh "$stage/Litara.app" >/dev/null
ln -s /Applications "$stage/Applications"
dmg="build/Litara-$(cat VERSION).dmg"
identity="$(codesign -dvv "$stage/Litara.app" 2>&1 | sed -n 's/^Authority=\(Developer ID Application: .*\)$/\1/p')"
notarize=""
if [[ -n "$identity" ]] && xcrun notarytool history --keychain-profile blalb-notary >/dev/null 2>&1; then notarize=1; fi
if [[ -n "$notarize" ]]; then
  # приложение — отдельно, чтобы печать была и на нём: скопированное из DMG без сети тоже откроется
  ditto -c -k --keepParent "$stage/Litara.app" "$stage.zip"
  xcrun notarytool submit "$stage.zip" --keychain-profile blalb-notary --wait >&2
  rm -f "$stage.zip"
  xcrun stapler staple "$stage/Litara.app" >&2
fi
hdiutil create -volname "Litara $(cat VERSION)" -srcfolder "$stage" -format UDZO -ov "$dmg" >/dev/null
rm -rf "$stage"
if [[ -n "$notarize" ]]; then
  codesign --force --timestamp --sign "$identity" "$dmg"
  xcrun notarytool submit "$dmg" --keychain-profile blalb-notary --wait >&2
  xcrun stapler staple "$dmg" >&2
  spctl -a -t open --context context:primary-signature -v "$dmg" >&2
else
  echo "без нотаризации: нет Developer ID или профиля blalb-notary — на другом Mac «Всё равно открыть»" >&2
fi
echo "$dmg"
