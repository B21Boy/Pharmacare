# Porting map: HTML to Dart

HTML file: `reference/pharmacare-preview28-fixed.html` (4,230 lines: CSS 10-870, markup 872-882, JS 883-4228).
Status: **Done** = ported and working, **Partial** = main flow only (see TODO comments), **No** = placeholder.

## Foundation
| Part | HTML lines | Dart | Status |
|---|---|---|---|
| CSS tokens, light and dark | 10-60 | `core/theme/app_colors.dart`, `app_theme.dart` | Done |
| Dates, Ethiopian calendar, money | 884-935 | `core/utils/app_format.dart`, `ethiopian_calendar.dart` | Done (tested against the JS) |
| Translations EN / AM / OM / TI | 915-942 + `Object.assign(AM,...)` lines | `core/l10n/` (generated, 952 Amharic keys) | Done |
| Icons | 944-988 | `core/widgets/app_icons.dart` (Material icons) | Done (swap for the exact SVG paths if you want identical strokes) |
| Sample data: suppliers, 12 medicines, 2 years of sales, customers, audit | 992-1130 | `data/seed/seed_data.dart` | Done (includes Rx, invoices, missed sales and monthly expenses for reports) |
| State `S`, roles, permissions | 1131, 1015-1030 | `state/app_state.dart`, `domain/permissions.dart` | Partial |
| Stock rules: sellable, FEFO, flags, risk, reorder plan, attention | 1141-1262 | `domain/inventory_rules.dart` | Done |
| Search with typos and brand names | 3501-3516 | `domain/medicine_search.dart` | Done |

## Screens
| Screen | HTML lines | Dart | Status |
|---|---|---|---|
| Header, dock, drawer, offline bar, sheets, toast | 1297-1348, 1751-1770, 1213-1224 | `features/shell/`, `core/widgets/app_overlays.dart` | Done |
| Sign in / register / code | 3427-3495 | `features/auth/auth_screen.dart` | Partial (no PIN, fingerprint, TIN/license, cloud directory) |
| Home (classic) | 1350-1369, 1263-1296 | `features/home/` | Partial (missing: `watchHtml` money to collect and orders on the way) |
| Home (modern) | 1771-1794 | - | No |
| Inventory (classic) + filter sheet + paging | 3521-3545, 1371-1389 | `features/inventory/inventory_screen.dart` | Done |
| Inventory (modern grid) | 1795-1813 | - | No |
| Barcode scan | 3547-3600 | - (`mobile_scanner`) | No |
| Medicine detail | 1415-1442, 1391-1410 | `features/inventory/medicine_detail_screen.dart` | Partial (missing: edit sheet, add batch, batch edit/block, price history, sales pace card, archive) |
| Sales: counter, cart, payment, checkout, today | 1445-1560 | `features/sales/sales_screen.dart` | Partial (missing: Rx form per item 1497, discount 1676, credit-limit checks 1651, receipt and PDF 1713, returns 1573, scanner) |
| Settings | 2926-3039, 3148-3200 | `features/settings/settings_screen.dart` | Partial (language, theme, calendar, layout, expiry window, role) |
| Audit log | 2171-2185, 3040-3147 | `features/audit/audit_screen.dart` | Partial (missing: hash-chain seal and verify, staff and risk cards, export) |
| Credit and customers | 2567-2701, 1630-1700 | `features/credit/credit_screen.dart` | Partial (list, ledger, payment; missing: debt age, reverse payment, merge, reminder, statement) |
| Suppliers | 2306-2333 | `features/suppliers/suppliers_screen.dart` | Partial (list only) |
| Orders | 2907-2925, 3571-3670 | `features/orders/orders_screen.dart` | Partial (low stock, order list, send; missing: receive delivery with batch/expiry/invoice, new order, cancel) |
| Register medicine | 1848-1975 | `features/inventory/register_medicine_screen.dart` | Done (form, validation, duplicate guard, first batch and audit; hardware scanning remains optional) |
| Stocktake | 2334-2409 | `features/stocktake/` | **No** |
| Rx and controlled log | 2702-2878, 3006-3039 | `features/rxlog/` | **No** |
| Reports | 2008-2170 | `features/reports/reports_screen.dart` | Done (all report tabs, date ranges, Rx register, PDF/XLSX/share, finance comparisons and monthly-send simulation) |
| Finance (owner) | 2186-2305, 2879-2906 | `features/finance/` | **No** |
| Alternatives | 2529-2566, 1032-1039 | `features/alternatives/` | **No** |
| Missed sales ("customer asked") | 2410-2528 | - | **No** |
| Chat assistant | 1976-2007 | `features/chat/` | Done (sample replies; a real Gemini integration still needs a secure backend proxy) |
| Action handlers (`const A={...}`) | 3674-4067 | split into AppState methods per module | Partial |

## Data layer (not in the HTML as real storage)
The HTML keeps everything in memory (`S`) and simulates sync (lines 3210-3426: change tracking, pending queue, hybrid logical clock).
Plan for the real app:
1. Local database first (Drift or Hive) behind `lib/data/repositories/pharmacy_repository.dart` (create the abstract class from the `AppState` lists).
2. Cloud sync later (Firebase or your own API): replay the pending queue when online, keep audit entries append-only.
3. Replace `SeedData` with first-run empty data or an import.
4. Phone sign-in: Firebase Phone Auth replaces the simulated code in `auth_screen.dart`.

## Known simplifications in the Dart version
- No phone frame (the HTML draws a 390x844 frame on desktop). It is a native app, so no frame.
- `AppIcon` uses Material icons instead of the custom stroke icons.
- Language/theme/layout are not persisted yet (add `shared_preferences` in `AppState`).
- The Dart code was written without a compiler available. Run `flutter analyze` first and fix anything it reports.
