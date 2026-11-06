// Litara — приложение в строке меню: перехватывает набор и исправляет раскладку.
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
