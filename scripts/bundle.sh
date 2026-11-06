#!/bin/bash
# Собирает build/Litara.app (или путь из первого аргумента): release-сборка под Apple Silicon и Intel,
# Info.plist, словари, подпись.
#
# Подпись: BLALB_SIGN_IDENTITY, иначе «Developer ID Application» из связки ключей (B30: с усиленной средой выполнения
# и отметкой времени Apple — так её примет нотаризация), иначе локальный сертификат «blalb Local Signing» (создан
# 2026-10-21 по просьбе владельца), иначе ad-hoc («-»). С сертификатом признак подписи постоянный, и macOS не сбрасывает
# «Универсальный доступ» после пересборки; с ad-hoc — сбрасывает. Отметке времени нужна сеть; без сети —
# BLALB_SIGN_IDENTITY="blalb Local Signing".
set -euo pipefail
cd "$(dirname "$0")/.."
archs=(--arch arm64 --arch x86_64)
swift build -c release "${archs[@]}" --product Litara
bin="$(swift build -c release "${archs[@]}" --show-bin-path)"
app="${1:-build/Litara.app}"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Litara" "$app/Contents/MacOS/Litara"
# обновления (B33): Sparkle.framework — в Contents/Frameworks, путь к нему — в бинарнике (SwiftPM ищет рядом с собой)
mkdir -p "$app/Contents/Frameworks"
ditto "$bin/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$app/Contents/MacOS/Litara"
cp -R "$bin/Litara_LitaraCore.bundle" "$app/Contents/Resources/"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"  # иконка (B35)
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>io.github.nugnii.litara</string>
    <key>CFBundleName</key><string>Litara</string>
    <key>CFBundleExecutable</key><string>Litara</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$(cat VERSION)</string>
    <!-- по нему Sparkle сравнивает версии -->
    <key>CFBundleVersion</key><string>$(cat VERSION)</string>
    <!-- обновления (B33): лента выпусков на GitHub, подпись EdDSA (секретная часть — в связке ключей владельца),
         раз в сутки, без сведений о Mac -->
    <key>SUFeedURL</key><string>https://github.com/Nugnii/litara/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key><string>PFmnqMYGHGAhNQBelCjCDIDzISCSJffs3mb9v8KlEV0=</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUScheduledCheckInterval</key><integer>86400</integer>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <!-- без списка macOS отдаёт приложению английский: названия раскладок, окно выбора файла -->
    <key>CFBundleLocalizations</key><array><string>en</string><string>ru</string><string>be</string><string>uk</string><string>pl</string></array>
</dict>
</plist>
PLIST
identity="${BLALB_SIGN_IDENTITY:-}"
# вывод — в переменную, разбор — без раннего выхода: под pipefail оборванный источник (SIGPIPE, 141) остановил бы сборку
valid="$(security find-identity -v -p codesigning)"
all="$(security find-identity -p codesigning)"
if [[ -z "$identity" ]]; then
  identity="$(sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' <<<"$valid" | sed -n 1p)"
fi
if [[ -z "$identity" ]] && grep -q '"blalb Local Signing"' <<<"$all"; then
  identity="blalb Local Signing"
fi
sign() {
  if [[ "$identity" == "Developer ID Application:"* ]]; then
    codesign --force --options runtime --timestamp --sign "$identity" "$@"
  else
    codesign --force --sign "${identity:--}" "$@"
  fi
}
# Sparkle — изнутри наружу, без --deep (порядок из документации Sparkle «Code Signing»)
fw="$app/Contents/Frameworks/Sparkle.framework"
sign "$fw/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$fw/Versions/B/XPCServices/Downloader.xpc"
sign "$fw/Versions/B/Autoupdate"
sign "$fw/Versions/B/Updater.app"
sign "$fw"
sign "$app"
echo "$app"
