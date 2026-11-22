# PharmaCare (Flutter)

Flutter port of `reference/pharmacare-preview28-fixed.html`.

## Run
```bash
flutter pub get
flutter create --project-name pharmacare_app --platforms=android,ios .   # once: adds android/ and ios/ (keeps lib/)
flutter run
flutter test
```
Requires Flutter 3.24 or newer (Dart 3.3+).

Preview login (no backend yet): tap a demo name on the sign-in screen, then use the code shown on screen.

## Structure
```
lib/
  main.dart, app.dart          app root, theme, Auth or Shell
  core/
    constants/                 categories, roles, plan numbers
    l10n/                      t(), tf(), tn() + EN/AM/OM/TI maps (generated)
    theme/                     AppColors (CSS tokens), AppTheme
    utils/                     AppFormat (money, dates), Ethiopian calendar, ids
    widgets/                   card, badge, buttons, chips, sheets, toast, icons
  data/
    models/                    Medicine, Batch, Customer, SaleLine, PurchaseOrder ...
    seed/                      sample data from the HTML
    repositories/              (empty) future Hive/Drift/Firestore layer
  domain/                      pure rules: stock, expiry, reorder plan, FEFO, search, permissions
  state/app_state.dart         single ChangeNotifier (the HTML `S` object)
  features/
    shell/ auth/ home/ inventory/ sales/            ported
    audit/ credit/ orders/ suppliers/ settings/     simplified
    chat/ reports/ finance/ stocktake/ rxlog/ alternatives/   placeholders
reference/                     the HTML + extracted translations
docs/                          CODEX_PROMPT.md, PORTING_MAP.md, DESIGN_TOKENS.md
test/                          unit tests
```
