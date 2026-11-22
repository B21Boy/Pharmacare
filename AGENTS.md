# PharmaCare Flutter app: instructions for Codex

You are porting a working HTML/JS prototype into a real Flutter (Dart) mobile app.

## Source of truth
- `reference/pharmacare-preview28-fixed.html` is the exact design, layout and behaviour to copy.
  Read it before changing a screen. Line numbers are in `docs/PORTING_MAP.md`.
- `reference/i18n.json` holds all translations (already generated into `lib/core/l10n/strings_*.dart`).
- Do not redesign. Same colours, spacing, radii, wording, and the same business rules.

## Rules
1. Dart 3, Flutter 3.24+. State: `provider` (`AppState` in `lib/state/app_state.dart`).
2. Keep the folder structure: `core/` (theme, l10n, utils, widgets), `data/` (models, seed, repositories),
   `domain/` (pure business rules), `state/`, `features/<module>/`.
3. Business rules live in `lib/domain/` as pure Dart (no Flutter imports) and need a unit test in `test/`.
4. Colours only from `context.c` (`AppColors`). Never hard-code a colour that exists as a token.
5. Text: always `t('English text')`, `tf(...)`, `tn(...)`. The English text is the key, as in the HTML.
   When you add new text, add the Amharic to `reference/i18n.json` and regenerate with `tool/extract_i18n.js`.
6. Roles: check `state.can(Perm.x)`. Cashier must never see profit, cost or owner-only screens.
7. Every action that changes data calls `state.log(...)` (audit trail) and ends with a notify (`_touch()`).
8. Money: `AppFormat.etb(n)`. Dates: `AppFormat.fmtD / dsp / mon` (Gregorian or Ethiopian calendar).
9. Offline first. When the real database is added, put it behind `lib/data/repositories/` and keep
   `AppState` as the only thing screens talk to.
10. Do not add packages without saying why. Allowed next: `hive` or `drift` (local), `firebase_*` (cloud),
    `mobile_scanner` (barcode), `pdf` + `printing` (reports), `excel` (xlsx export), `flutter_local_notifications`.

## How to work
- Port one module at a time, in the order of `docs/PORTING_MAP.md`. After each module run:
  `dart format .`, `flutter analyze`, `flutter test`.
- Replace the `PortPlaceholder` screens one by one. Keep the file name and class name.
- Each `// TODO(port): ...` comment names the HTML function and line to port next.
- Commit after every module.

## Done means
Screen looks like the HTML on a 390x844 phone in light and dark mode, in English and Amharic,
for Owner, Pharmacist and Cashier, online and offline, and `flutter analyze` is clean.
