# Prompt to paste into Codex (VS Code)

Open this folder in VS Code, then paste:

---
Read `AGENTS.md` and `docs/PORTING_MAP.md` first.

This Flutter project is a port of `reference/pharmacare-preview28-fixed.html`. The shell, theme,
translations, data models, stock rules, Home, Inventory, Medicine detail, Sales and Login are done.

Task: port the next module from the table in `docs/PORTING_MAP.md` (top of the "Not ported" list).
1. Open the HTML at the listed lines and copy the exact layout, wording and rules.
2. Replace the `PortPlaceholder` screen (same file and class name).
3. Put business rules in `lib/domain/` with a unit test.
4. Use `context.c` colours, `t()` text, `AppFormat` for money and dates, `state.can(...)` for roles.
5. Run `dart format .`, `flutter analyze`, `flutter test`. Fix everything.
6. Tell me what you ported and what is still missing from that module.

Start with: **Register medicine** (`lib/features/inventory/register_medicine_screen.dart`).
---

Suggested order after that: Stocktake, Orders (receive delivery), Rx log, Reports (+ PDF/Excel),
Finance, Alternatives, Chat, Settings cards, Modern layout (Home + Inventory), Sync / database.
