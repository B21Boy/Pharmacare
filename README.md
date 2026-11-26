# PharmaCare (Flutter)

Flutter port of the HTML preview. Clean, feature-first architecture; the
business logic is ported 1:1 and unit-tested; Firebase, Gemini and other
services are **placeholders** behind interfaces, so you add them later without
touching screens or rules.

The Android and iOS runner projects are included. Use the Flutter **stable**
channel and install the Android SDK with Android Studio or the command-line tools.

## Run

```bash
flutter doctor -v
flutter pub get
flutter analyze
flutter devices
flutter run                                # choose a connected Android device or emulator
flutter run -d chrome                     # run in Chrome
```

If Chrome is not installed, use Flutter's browser server instead and open
`http://localhost:8080`:

```bash
flutter run -d web-server --web-hostname=0.0.0.0 --web-port=8080
```

For Android, install Android SDK Command-line Tools, Platform-Tools, and the
platform/build tools requested by `flutter doctor`; review and accept the SDK
licenses with `flutter doctor --android-licenses`. Connect a USB-debugging
enabled phone or start an emulator, then run `flutter run`.

Demo sign-in (debug builds only): `0911 000 001` owner, `0911 000 002`
pharmacist, `0911 000 003` cashier. Code: `123456`.

## Folder structure

```
lib/
  main.dart, bootstrap.dart        start-up, security gate, error hooks
  app/                             theme, router (role guards), shell, privacy guard
  core/
    config/        Env (--dart-define values, no secrets)
    security/      PIN hashing (PBKDF2), secure storage, PII redactor
    i18n/          Tr (en, am, om, ti from assets/i18n/*.json)
    utils/         Money (integer santim), Ethiopian calendar, ids, LiveList
    widgets/       StatusChip, EmptyState, FeaturePlaceholder
  data/
    providers.dart  COMPOSITION ROOT: demo repos vs Firebase repos
    demo/           demo seed (from the HTML preview)
  features/<feature>/
    domain/        pure Dart: entities, rules, repository INTERFACES
    data/          in-memory repo (demo) + firestore_* placeholder
    presentation/  screens, widgets, Riverpod controllers
  features: auth, lock, inventory, sales, credit, audit, chat, home, settings
android/                         Android Gradle project and native activity
ios/                             iOS Xcode runner project
web/                             browser entry point, icons, and manifest
```

Rule of thumb: `domain/` never imports Flutter UI or Firebase. Screens only see
repository interfaces. Switching backend = change `data/providers.dart`.

## What is ported (and tested)

| Logic | File |
|---|---|
| FEFO batch selling, expiry flags, at-risk value | `inventory/domain/stock_rules.dart` |
| Sales-based reorder plan, restock quantity | `inventory/domain/reorder_planner.dart` |
| "Needs attention" list | `inventory/domain/stock_overview.dart` |
| Ingredient groups / alternatives | `inventory/domain/ingredients.dart` |
| Sale review + checkout (discount limits, Rx rules, credit limits) | `sales/domain/sale_service.dart` |
| Customer credit (FIFO payments, ageing, limit check) | `credit/domain/credit_rules.dart` |
| Hash-chained audit log (now SHA-256) | `audit/domain/audit_chain.dart` |
| Ethiopian calendar | `core/utils/ethiopian_calendar.dart` |
| Roles and permissions | `auth/domain/role.dart` |

## Screens ready vs placeholder

Ready: sign-in, PIN lock, Home, Inventory, Medicine detail, Sales (POS), Credit,
Audit (with verify), Chat (offline rules), Settings.
Placeholder (`FeaturePlaceholder`, names the JS functions to port): Reports,
Finance, Suppliers, Orders, Stock count, Alternatives, Rx log.

## Wiring the placeholders

**Firebase** (`USE_FIREBASE=true`)
1. `flutterfire configure` (creates `lib/firebase_options.dart`, git-ignored).
2. Uncomment `firebase_*` packages in `pubspec.yaml`.
3. Uncomment the `Firebase.initializeApp` / App Check block in `bootstrap.dart`.
4. Implement the `firestore_*` classes (each file has the collection layout).
5. Deploy `firebase/firestore.rules`; build the functions in `firebase/functions_plan.md`.

**Gemini**: never put the key in the app. Implement `GeminiAssistant`
(`features/chat/data`) to call your Cloud Function; run with
`--dart-define=GEMINI_PROXY_URL=https://...`. Questions are already scrubbed
by `PiiRedactor` before they leave the phone.

**Others**: barcode (`mobile_scanner`), PDF/Excel (`pdf`, `excel` + embedded
Noto Sans Ethiopic), offline cache (`drift`), native PBKDF2
(`cryptography_flutter`).

## Security built in

- **No secrets in the app**: `Env` holds only public identifiers; Gemini key stays on the server.
- **Release gate**: release builds refuse to start without a real backend (demo auth cannot ship).
- **PIN**: no default PIN, weak PINs refused, PBKDF2-SHA256 + random salt, constant-time compare, hashed in a background isolate, stored in Keychain/Keystore, escalating lockouts (30 s → 15 min), sign-out + wipe after 10 failures.
- **Privacy guard**: blank screen in the app switcher; re-lock after 60 s in background. Add `FLAG_SECURE` (Android) to block screenshots.
- **Money as integers**: no floating-point drift.
- **Audit log**: SHA-256 chain, append-only; server anchoring planned (`anchorAuditHead`).
- **Server enforces roles**: client checks only hide screens; `firestore.rules` is the real gate.
- **Errors never show raw exceptions**; crash reports must exclude patient data.

Before release also: `flutter build apk --release --obfuscate --split-debug-info=build/symbols`,
enable Play Integrity / App Check enforcement, and run a dependency audit.

## Performance built in

- Riverpod `select` so widgets rebuild only for the data they show.
- `ListView.builder` / `separated` everywhere (only visible rows are built).
- Search is debounced (150 ms); stock overview computed once per change.
- Tabs kept alive with `StatefulShellRoute.indexedStack`.
- Only 35 days of sales are held in memory; history is queried from the backend.
- PBKDF2 runs in an isolate; move `StockOverview.build` to `Isolate.run` for very large catalogues.
- `const` constructors and immutable models throughout.

## Known gaps (from the HTML preview review)

Split payments UI (domain supports it), returns, receipts printing, barcode
camera, missed-demand log, sync engine (replaced by Firestore offline
persistence), Bluetooth printer, Telegram alerts. Plural handling for Amharic
uses the same one/many rule as English.
