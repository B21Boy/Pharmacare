# PharmaCare (Flutter)

Flutter port of the HTML preview. The feature-first architecture keeps
business logic separate from the Firebase and assistant service adapters.
Authentication, Firestore repositories, and the Chat UI are connected; remote
Gemini replies use an authenticated Firebase callable and keep the API key on
the server.

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

**Firebase on Android**

The sign-in and owner-registration screens use phone OTP. Firebase assigns the
role and pharmacy on the server; the app reads those from verified custom
claims. Run the Firebase launch configuration in VS Code, or start it directly:

```bash
flutter run --dart-define=USE_FIREBASE=true
```

The Android Firebase app must match `com.pharmacare`, and
`android/app/google-services.json` must belong to project `pharmacare-a43c3`.
Enable Phone sign-in in Firebase Authentication and allow the regions where
SMS should be sent. Owner and invited-staff registration also require these
callable functions to be deployed:

```bash
./.tools/firebase/node_modules/.bin/firebase deploy --only functions:completeOwnerRegistration,functions:completeStaffRegistration,functions:createStaffInvitation,functions:updatePharmacyProfile --project pharmacare-a43c3
```

The project currently has a Firestore database, but Cloud Functions API is
disabled. Firebase requires this project to use the Blaze (pay-as-you-go) plan
before Cloud Build and these callables can be deployed. Until then, new owner
registration and staff invitations cannot complete. Review and deploy
`firebase/firestore.rules` before connecting production data.
The iOS runner still needs its own Firebase app registration and
`GoogleService-Info.plist`. Firebase web options are not configured; web runs
in demo mode.

**Gemini**: the Chat screen calls the authenticated `assistant` Firebase
callable. The Android Firebase launch configuration points to
`https://us-central1-pharmacare-a43c3.cloudfunctions.net/assistant`. The
callable sends only the question, selected medicine, and bounded stock/sales
summary to Gemini; `PiiRedactor` scrubs the question and the request disables
conversation storage. The local rules assistant remains available when the
callable is unavailable.

The Gemini key note at `gemini/geminiapi.js` is excluded from Git. After this
Firebase project is upgraded to Blaze, store the key without printing it by
running `python3 firebase/set_gemini_secret.py`, then deploy the Functions
backend. Secret Manager and Cloud Functions cannot be enabled on the current
plan, so remote Gemini replies are not live yet.

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
