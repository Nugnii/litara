# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions: [SemVer](https://semver.org/).

## [Unreleased]

## [0.29.0] - 2026-11-06

### Changed
- blalb is now Litara ("letter" in Belarusian), with its own icon. On the first launch settings, learned words,
  statistics and the decision log move over, and launch at login is turned on again. If you go back to blalb for a
  while, words it learns are added to Litara later; words you made Litara forget are not brought back.
  Accessibility has to be granted again: the app has a new identity. A running blalb is closed, so words are not
  fixed twice.
- Signed with a Developer ID and notarized by Apple: macOS opens it without "Open Anyway".

### Added
- Updates: once a day Litara checks for a new version and offers to install it (Sparkle). Nothing about your typing
  is sent; turn it off in General. "Check for Updates…" is in the menu.
- "Buy the author a coffee" link under the version in Statistics.
- "What's new" link under the version in Statistics: opens the Litara releases page.
- With flags turned on, RU gets a flag too, and the RU and BY flags follow the interface language: in Belarusian
  and Ukrainian, RU is the flag of Mordor and BY is white-red-white; in other languages, RU is the Russian tricolour
  and BY is the state flag of Belarus.

## [0.28.0] - 2026-11-06

### Fixed
- Button labels on the "Words" tab are no longer cut off in any of the 5 languages ("Learn words from texts…",
  "Forget learned"): if the row does not fit, the buttons move below the label. All tabs and the first-launch window
  were checked in 5 languages; no other labels are cut off.

### Added
- "Export words…" and "Import words…" on the "Words" tab: learned words are saved to a JSON file, and another person
  can add them to their own blalb. The file holds only learned words, with no dictionary of your texts, no "My words"
  and no custom replacements.

## [0.27.0] - 2026-11-06

### Changed
- Declining a typo fix works not only with ⌥: if you erase the corrected word and type the same thing again (or change
  it back), blalb keeps it as typed and counts it as a rollback. After the third one, the word goes to "My words".
  Before, "некада" was changed to "некуда" every time.

### Fixed
- When translating selected text with ⌥, "ё" is taken from the key left of "1", the one you type it with: "всё" into
  Belarusian gives "вс’", not "вс’" one run and "вс“" the next. blalb detects the keyboard type from key presses:
  on a European (ISO) keyboard it is §, on an American (ANSI) one it is `, and an external and the built-in keyboard
  can differ.
- A Russian word no longer goes into English when its letters turn into punctuation there: "быкуе" → ",sret",
  "ютуб" → ".ne,", "Вглубю" → "Duke,.". A bracket or a period in place of a letter was treated as the edge of the
  word and cut off, and the rest was taken as a word. All 12 such fixes in the log were wrong. An apostrophe
  ("don't") and a comma after a word ("hello,") work as before.

## [0.26.0] - 2026-11-06

### Added
- "Statistics" now shows the version of the running build on its first line, so you can see which one is running.

## [0.25.0] - 2026-11-06

### Changed
- The layout is decided by the word, not by the earlier words of the phrase, for all languages: part of a sentence
  can be typed in any layout. A Belarusian word after Russian ones goes to Belarusian just like at the start of a
  phrase: "привет прывитанне" → "прывітанне", "если взять нацисни литару" → "націсні літару", "отлично выдатна".
  Since 0.23.0 the phrase language kept the Russian layout, and half of the Belarusian words after Russian stayed as
  typed.
  The price: a Russian word that is not in the dictionary also goes to Belarusian anywhere in a phrase ("запасик" →
  "запасік"). Undo with ⌥; after three rollbacks the word goes to "My words".

## [0.24.0] - 2026-11-05

### Changed
- Typos in short words (4-5 letters): a miss on a neighboring key is fixed into a word you write yourself
  ("есои" → "если"). blalb remembers your own words from 4 letters instead of 6, both while typing (twice without a
  mistake) and from chat exports. A miss is not fixed into any dictionary word: measured on real chats, that gave
  one correct fix per three wrong ones.

## [0.23.0] - 2026-11-05

### Added
- A lock on the menu-bar icon while macOS secure input is on (a password field, including one forgotten in the
  background): blalb does not correct typing during that time. The menu shows, on its first line, the app macOS
  attributes the input to. Before, blalb just stayed silent in this state and the reason was not visible.

### Fixed
- In editors that close brackets and quotes on their own (Notepad++, VS Code), cycling with ⌥ no longer leaves extra
  "]": the English variant of Cyrillic types "[" ("хотел" → "[jntk"), the editor added "]", and after the full cycle
  the text did not return to the original.
- In a Russian sentence, a Russian word that is not in the dictionary no longer goes to Belarusian: "запасик" stayed
  "запасік", "андроид" stayed "андроід", and "беларускую" or "бургеры" switched the layout, so the following Russian
  words got "і" and "’". Now only clearly Belarusian words leave a Russian sentence: those with "ў" or with an ending
  that does not exist in Russian ("перакласці"). "вс’" typed in the Belarusian layout is fixed to "всё".

### Changed
- "Learn words from texts…": from a shared Telegram chat (group, channel) a word is learned only if it appears at
  least 4 times instead of 2, because many people write there and other people's typos repeat. Private chats and .txt
  files work as before, with 2 times.

## [0.22.0] - 2026-10-29

### Added
- blalb can be installed on another Mac: `scripts/dmg.sh` builds `build/blalb-<version>.dmg` (the app and an
  "Applications" shortcut). There is no Apple signature yet, so macOS blocks the first launch. To open it: System
  Settings → Privacy & Security → "Open Anyway", then grant "Accessibility".
- The app also runs on Intel Macs: it is built for Apple Silicon and Intel at once.
- Otherwise the app is the same as 0.21.2.

## [0.21.2] - 2026-10-29

### Fixed
- A word with a character from the numeric keypad is now fixed: "/ыфму" ("/" from the keypad, letters in the Russian
  layout) becomes "/save". Before, blalb did not see keypad keys and did not touch such a word at all, neither on the
  fly nor on space.

## [0.21.1] - 2026-10-23

### Fixed
- In the MuMu emulator blalb no longer breaks words ("Blue" → "ИBle", "Летает" → "КЛеает"). MuMu performs erasing
  later than the typed letters, and the fix ate part of the word. There is no reliable way to edit text there with
  key presses, so in MuMu blalb does not edit text: neither on its own, nor with ⌥, case or transliteration.
  Switching the layout with ⇧⌥ works.

## [0.21.0] - 2026-10-23

### Added
- The decision log ("Log decisions") shows typing resets: a click, a password field, a combination with ⌘ or ⌃, Esc
  and navigation keys, a layout that is not one of blalb's languages. It is written as "<reason> — session reset".
  Only a reset that had something to erase is written, so arrows and repeated clicks do not clutter the log.

## [0.20.0] - 2026-10-23

### Changed
- A word whose fix you undid three times is remembered by blalb itself: it goes to "My words" and is no longer
  corrected, and the notification only tells you about it. Before, the notification asked "Больше не исправлять?"
  once, came as a banner and disappeared while you were typing, so the word was corrected again and again. To bring
  the fix back, remove the word from "My words". "вуфирмы?" and "вуфирмы" are now counted as one word. Words already
  rolled back three times before the update are remembered on the first launch.

## [0.19.3] - 2026-10-23

### Fixed
- Custom replacements scroll: of a long list only four rows were visible, and the rest were cut off with no scroll
  bar. The "what" and "with what" fields now show a border even without a cursor, so it is clear where to click.
  "+" is above the list, and each row has "×" to delete it.

## [0.19.2] - 2026-10-22

### Fixed
- "b" after an English word becomes "и": after "API" the layout is English, and "и" was typed as "b", and the fix was
  blocked by the Belarusian "і" on the same key. Now such a tie between Cyrillic layouts is decided by the language of
  the text, also for words spelled the same ("мама"): Belarusian text typed in the English layout no longer goes to
  Russian.

## [0.19.1] - 2026-10-22

### Fixed
- A one-letter word no longer goes to another layout together with the next one: "был в wfirm" and "это и API" became
  "был d wfirm" and "это b API" when "wfirm" or "API" was fixed from the Russian layout. Only one-letter words that
  are not words in their own layout follow the word ("z ghbdtn" → "я привет"). Measured on a Russian chat: broken
  one-letter words in messages with Latin text went from 139 to 40.

## [0.19.0] - 2026-10-22

### Added
- blalb learns from your typing: a Russian or Belarusian word of 6 or more letters that you typed twice without a
  mistake becomes familiar, and a "wrong letter" is fixed into it too ("разбирвться" → "разбираться"). Before, such
  typos were fixed only into words from texts ("Learn words from texts…"). What is learned is kept only on this Mac,
  together with words from texts; the log says "learned from typing".

## [0.18.0] - 2026-10-22

### Added
- Names and cities in the dictionaries of all five languages: personal names and settlements from Wikidata with their
  cases ("Илона", "Илоны", "Илоне"…). A name no longer goes to another layout just because it is not in the
  dictionary: in a Russian chat, false switches on space went from 421 to 323, and "Илона" is no longer among them. A
  name is not added if its keys in another layout give an ordinary word ("Ши" would turn the Belarusian "ШІ" into
  Russian.) The price, by measurement: in Belarusian text typed in the Russian layout there are 40 fewer fixes out of
  21,037 (name collisions: "Тбилиси" — "Тбілісі"); in the Polish pairs of the test set, 1-2 words fewer out of 500.

## [0.17.5] - 2026-10-21

### Fixed
- ⌘V, ⌘C, ⌘X, ⌘A and ⌘Z work in settings fields ("My words", custom replacements): an app with no Dock icon had no
  Edit menu, which is how fields get these shortcuts.
- blalb hotkeys (⌥, ⌥⇧ and others) work in the settings window too; before, the layout could not be changed there.
  They do not work only while a new hotkey is being recorded.

## [0.17.4] - 2026-10-21

### Fixed
- After settings were opened (as well as the welcome window and the file picker for learning), blalb stopped noticing
  layout changes: choosing a language in the icon menu "did not go through", and the icon and typing stayed in the old
  layout although macOS had already changed it. macOS pauses delivery of notifications to an app that was active and
  went to the background; now the layout-change notification is always delivered.

## [0.17.3] - 2026-10-21

### Fixed
- A word in quotes or with a sign in front ("Словы", "#визы", "ШІ-кантэнт") no longer changes the language on the fly
  after two letters: the sign in front was counted as the "third letter". In Belarusian text "Слухай" turned into
  Russian, sometimes via the English "@Cke". Measured on chats: false switches between Cyrillic layouts on the fly
  went from 20 to 2 (Belarusian chat) and from 9 to 8 (Russian); correct fixes did not decrease.
- A surname or an unfamiliar word in Russian text no longer moves the layout to Belarusian on the fly after a period,
  a click or a pause: "Доброе утро. По дасни…" and "Переслал Дасни…" turned into "дасні". The language of the text is
  now remembered until the layout is changed manually. Measured on chats: false switches between Cyrillic layouts on
  the fly went from 89 to 9 (Russian chat) and from 51 to 20 (Belarusian).

## [0.17.1] - 2026-10-21

### Fixed
- The hint under "Learn words from texts…" talks about a "wrong letter", not about a neighboring key.

## [0.17.0] - 2026-10-21

### Changed
- A "wrong letter" typo is fixed for any letter, not only for a neighboring key: "симполов" → "символов", "никакаго" →
  "никакого", "людями" → "людьми". As before, only into familiar words from your texts. Measured on a Belarusian
  chat: about 58 correct fixes and 15 wrong ones ("третим" → "третий"); a wrong one is undone with ⌥, and after 3
  rollbacks the word goes to "do not correct".

## [0.16.1] - 2026-10-21

### Fixed
- The ⌥ cycle does not offer variants with ⌥-layer characters: "ыфмуl" (l is on ⌥L in "Russian – PC") no longer
  becomes the Belarusian "ыфму∆".

## [0.16.0] - 2026-10-21

### Added
- A particle written together is fixed: "почемуто" → "почему-то", "чемто" → "чем-то", "якоганебудзь" →
  "якога-небудзь". Measured on chats: 3 new fixes, all correct.
- "///" in the English layout → "..." — an ellipsis typed in the wrong layout; the layout does not change.
- A miss on a neighboring key at the end of a long word ("беспорядочныц" → "беспорядочный") — by an impossible
  ending; as before, only into familiar words from your texts.

## [0.15.0] - 2026-10-21

### Added
- A miss on a neighboring key is fixed ("теперт" → "теперь") — only into familiar words from your texts: "Learn
  words from texts…" now remembers them too (the word list only). Measured on chats: without this condition there are
  three times more wrong fixes than correct ones; with it, 17 out of 17 are correct.

## [0.14.0] - 2026-10-21

### Added
- "Auto-switch" as a checkmark right in the icon menu; an on/off hotkey in "Shortcuts" (not assigned by default,
  imported from Punto). While it is off, the menu-bar icon is dimmed.

## [0.13.1] - 2026-10-21

### Fixed
- Words with dead keys of "U.S. International – PC" are fixed: '"nj' → "Это", both on its own and with ⌥ on a
  selection (so are "её", "всё", "эти"). Before, blalb did not touch such words.
- Choosing a language in the icon menu works: before, macOS lost the choice while the menu was closing, and with
  settings open it reset the choice after they were closed. The log shows what was chosen in the menu and which
  layout it became.

### Changed
- With flags on, the language list in the menu also shows flags (RU keeps letters).

## [0.13.0] - 2026-10-21

### Added
- Custom replacements — a table "what / with what / case-insensitive": "what" may be a phrase ("Прык скок" → "Прыг
  Ског"), and "with what" is inserted as written. The case of "what" matters if the row is not ticked; the tooltip
  shows the difference on an example row. ⌥ restores the whole typed phrase.

### Fixed
- A Belarusian word that is spelled the same in the Russian layout ("прымай", "выдатна", "гэта", "з") now switches
  the layout to Belarusian; before, it stayed Russian, and then "і" was typed as "и". And the other way round: a
  Russian word spelled the same in the Belarusian layout moves to Russian. "я" and "о" are also Belarusian words: in
  the Belarusian layout they stay. Measured on the "Беларускі ШІ" chat (63,043 words): the Belarusian layout turns on
  for 23,952 words where it was silent before.

## [0.12.0] - 2026-10-21

### Added
- First-launch window: "Accessibility" (an "Open Settings" button, the status updates by itself) and import from
  Punto Switcher — exceptions and hotkeys. To open it again, launch with `--welcome`.

### Changed
- For new users, case change has no shortcut (⌘L is taken by the address bar in browsers); ⌘L comes with the import
  from Punto. Existing installations keep ⌘L.

## [0.11.0] - 2026-10-21

### Added
- A language's layout variant is on its row in "General" ("Russian – PC", "Russian", "U.S. International – PC"…).
  The chosen one is enabled in macOS and becomes the language's layout; the previous one is removed only if blalb
  added it.

### Fixed
- System names and windows (file picker) are in the system language, not in English.

## [0.10.0] - 2026-10-21

### Added
- A click on automatic correction (layout or typo) — a switch in "General", off by default; the macOS sound "Tink".

### Changed
- "Offer not to correct after 3 rollbacks" is on the "Words" tab, next to "My words".

## [0.9.0] - 2026-10-21

### Added
- Flags on the icon instead of letters (a switch on the "General" tab): EN — USA, BY — white-red-white, UA and PL —
  their own; RU is always letters.

### Changed
- "Apps" is the last settings tab; "General" is again without scrolling.

### Fixed
- ⌥ on "." in the Russian layout gave "/" but switched to Belarusian, and then "и" was typed as "і" ("шифтом" became
  "ibanjv"). The Belarusian layout types signs like "Russian – PC", while the ⌥ cycle counted by the signs of Apple's
  own layout. Now "." → "/" leads to English, and the Belarusian layout with the same "." is skipped; text typed in
  Belarusian with signs is translated with the same keys.

## [0.8.0] - 2026-10-21

### Added
- An "Apps" tab: apps where blalb corrects nothing by itself — neither layout, nor typos, nor custom replacements;
  hotkeys work there. Add from running apps or with "Other…".

## [0.7.0] - 2026-10-21

### Changed
- Settings are split into tabs: "General", "Shortcuts", "Words", "Statistics" — without scrolling. The window opens
  on the last opened tab.

## [0.6.0] - 2026-10-21

### Added
- Statistics in settings, only on this Mac: words typed, automatic switches, typos fixed, fixed manually (with the
  share of all layout fixes), rollbacks (with the share of automatic fixes), crashes (from macOS reports). Counting
  starts from the first launch of 0.6.0; "Reset" starts over.

## [0.5.0] - 2026-10-21

### Added
- All hotkeys are assigned in settings (the "Keyboard shortcuts" section): fix (⌥), cycle layouts (⌥⇧), case (⌘L),
  transliteration. A combination with ⌘, ⌃ or ⌥ works, as do modifiers alone: press and release. A combination given
  to another action is taken away from the previous one; "×" clears a hotkey. The menu and tooltips show the assigned
  shortcuts; the key is labeled in Latin letters in any layout.

### Changed
- In the blalb settings window hotkeys do not trigger, because that is where they are recorded.

### Fixed
- Labels in the settings window are no longer cut off to one line.

## [0.4.0] - 2026-10-21

### Added
- Transliteration: the selected text or the last word in Latin letters, as in a passport, without diacritics
  ("Канстанцін Берсенеў" → "Kanstantsin Berseneu", "привет" → "privet"). Russian follows ICAO; Belarusian and
  Ukrainian have their own passport rules (г → h); the language is taken from the letters of the text, otherwise from
  the layout. The hotkey is assigned in settings ("Assign…"), and ⌥ restores what you typed.

## [0.3.0] - 2026-10-21

### Added
- Custom replacements: in settings, rows of "abbreviation = text"; the abbreviation is replaced after a space, and the
  layout and case of the abbreviation do not matter ("мск", "МСК", "vcr" → "Москва"). ⌥ restores what you typed.
- Remembering corrections: after three ⌥ rollbacks of one auto-corrected word, a macOS notification offers "Не
  исправлять" (the word goes to "My words") or "Оставить". There is a switch in settings.

## [0.2.1] - 2026-10-21

### Fixed
- Swapped letters in short words are fixed again ("приевт", "привте" → "привет") if the ending of the typed word is
  rare (fewer than 15 dictionary words). Slang with a common ending ("каменты", "збаіць") is left alone. Measured on a
  chat: 58 fixes, one wrong one added — "промты" → "промыт".
- The decision log no longer repeats the previous decision on a space without a new word.

## [0.2.0] - 2026-10-21

### Added
- Typo fixing for Russian and Belarusian — the "Fix typos" switch in settings (off by default). Only unambiguous
  cases: a doubled consonant, a repeated letter, swapped neighboring letters, "не" with a verb, a hyphen with a
  particle; ⌥ restores what you typed. The strictness limits were chosen by measuring a real chat (35,779 words): 56
  fixes, about 90% correct. "Any missing or extra letter" is not fixed — in the measurement almost all such fixes
  were wrong.
- Check filters of words for ru and be (+6.4 MB): a typo variant counts only when both filters agree with it.

### Fixed
- ⌥ on a selection in VSCode and other Electron apps works on the first press.
- An unfamiliar Russian word with a Belarusian beginning ("класный" — "класны") no longer moves the layout to
  Belarusian on the fly.

## [0.1.1] - 2026-10-21

### Fixed
- A selected phrase with words in different layouts ("как save отработает") was corrupted into special characters
  ("saµe"): Latin letters were taken from the ⌥ layer of "Russian – PC". Now each word has its own layout; the first
  press brings the phrase to one layout, then it cycles.
- ⌫ right after a space reset the session, and ⌥ did not change the previous word. Now the word is unfinished again;
  the hotkey decision holds.
- The ⌥ cycle could stop after one turn: a repeated macOS layout-change notification was taken for a manual change.
  Now its own change is recognized by the layout, not by a flag.
- The decision log records every step of the ⌥ cycle and a session reset caused by an outside layout change.

## [0.1.0] - 2026-10-21

The first build, for trial testing.

### Added
- Requirements for the first version: `docs/spec.md`.
- Core: reading macOS layouts from the system for ru, be, uk, en, pl.
- Core: translating text between layouts through key presses, with Shift and Option taken into account (Polish
  diacritics).
- Dictionaries for ru, be, uk, en, pl (hunspell) and compact word filters built from them: 9.7 million word forms in
  22 MB.
- Detecting the language of a word by dictionaries, with punctuation at the edges of the word; on the test set 9,861
  decisions out of 10,000 are correct, be↔ru 98.0% / 98.4%.
- Typing session: "word / sentence" rules, quotes and brackets as a separate sentence.
- Menu-bar app: key interception, fixing with synthetic key presses without the clipboard.
- Icon menu: choosing a language with a click, and settings — languages as checkboxes, an auto-detect switch.
- On-the-fly fixing from the third letter: the beginning of the word is impossible in the current language and
  possible in exactly one other; this also catches words that are not in the dictionary ("косячок"). Only the
  differing tail is erased.
- One-letter words are fixed right on space; abbreviations and names count as words only in their own case ("nj" is
  no longer taken for "NJ").
- ⌥ with selected text translates the selection around the layout cycle (the variant with more words comes first, the
  cycle returns the original text); without the clipboard. A selection with a line break is not translated.
- Hotkeys: ⌥ — last word around the cycle (the first press undoes the auto-fix), ⇧⌥ — next layout in the cycle, ⌘L —
  lowercase ↔ uppercase.
- Exceptions (words that are never corrected) with import from Punto Switcher; launch at login.
- "Replace the standard layout switcher": the macOS layout icon is hidden while blalb runs.
- Interface language: the system language by default, with a choice of en, ru, be, uk, pl.
- A custom dictionary: the user's words are known to the program ("ягы" → zus); words from texts are picked only if
  met twice, not in the dictionaries and not typed in the wrong layout.
- "Learn words from texts…": a Telegram Desktop export (result.json) or .txt; only Cyrillic words are learned, since
  Latin text from chats (links, nicknames) turned slang into Latin.
- "Log decisions" — a debugging log, only on this Mac.
- Signs "as in Russian – PC" in the Belarusian layout: "?", ",", "." in the familiar places.
- Removing a language removes the layout blalb added from macOS; layouts that were there before blalb stay.

### Fixed (2)
- The decision log says why ⌥ did not get the selection: the app, the role of the field, the system's reply.
- An added layout brought back the hidden system layout icon.
- Context: in a Russian sentence the layout does not move to Belarusian on the fly by itself (and the other way
  round); a whole word that exists only in another language's dictionary is fixed even among words of the current one
  ("работает выпращляе" → "выпраўляе").
- A word changed with a hotkey is no longer fixed by itself; abbreviations with periods (т.е., e.g.); stretched vowels
  ("аааа").
- A mixed sentence: if it contains a word that exists only in the current language, one word is fixed, not the whole
  sentence.

### Fixed
- The settings window did not open: it appeared behind other windows and collapsed.
- "[" at the start of a word was treated as a bracket and switched off on-the-fly fixing, although in the Russian
  layout it is the letter "х": it is a bracket only if it stays a bracket after translation.
