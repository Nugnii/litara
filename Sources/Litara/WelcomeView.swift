import ApplicationServices
import LitaraCore
import SwiftUI

/// Первый запуск (docs/spec.md): «Универсальный доступ» и перенос из Punto Switcher — исключения и хоткеи.
struct WelcomeView: View {
    let puntoExceptions: Int
    let puntoHotkeys: [HotkeyAction: Hotkey]
    /// «Готово»: переносить ли исключения и хоткеи Punto.
    let onDone: (_ exceptions: Bool, _ hotkeys: Bool) -> Void
    @State private var importExceptions = true
    @State private var importHotkeys = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Litara").font(.largeTitle.bold())
            Text(L10n.text(.welcomeIntro)).fixedSize(horizontal: false, vertical: true)
            GroupBox {
                // доступ дают в Системных настройках — окно видит его без перезапуска
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    HStack {
                        if AXIsProcessTrusted() {
                            Label(L10n.text(.welcomeAccessOK), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Text(L10n.text(.welcomeAccessNeeded)).fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button(L10n.text(.welcomeOpenAccess)) {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(4)
                }
            }
            if puntoExceptions > 0 || !puntoHotkeys.isEmpty {
                GroupBox(L10n.text(.welcomePunto)) {
                    VStack(alignment: .leading, spacing: 6) {
                        if puntoExceptions > 0 {
                            Toggle(String(format: L10n.text(.welcomePuntoExceptions), puntoExceptions), isOn: $importExceptions)
                        }
                        if !puntoHotkeys.isEmpty {
                            Toggle(L10n.text(.welcomePuntoHotkeys), isOn: $importHotkeys)
                            ForEach(HotkeyAction.allCases.filter { puntoHotkeys[$0] != nil }, id: \.self) { action in
                                Text("\(Settings.label(puntoHotkeys[action]!))  \(L10n.hint(action))")
                                    .font(.caption).foregroundStyle(.secondary).padding(.leading, 20)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }
            }
            Text(String(format: L10n.text(.welcomeHint), Settings.hotkeys[.fix].map(Settings.label) ?? "⌥"))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(L10n.text(.welcomeDone)) {
                    onDone(importExceptions && puntoExceptions > 0, importHotkeys && !puntoHotkeys.isEmpty)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
