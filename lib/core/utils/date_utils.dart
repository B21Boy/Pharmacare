/// App-wide convention: calendar dates are LOCAL, date-only (midnight).
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Whole days from [from] to [to] (negative when [to] is earlier). Uses UTC
/// internally so daylight-saving shifts can never produce 23/25-hour days.
int daysBetween(DateTime from, DateTime to) => DateTime.utc(to.year, to.month, to.day)
    .difference(DateTime.utc(from.year, from.month, from.day))
    .inDays;

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? tryParseIsoDate(String s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s.trim());
  if (m == null) return null;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  final r = DateTime(y, mo, d);
  // reject 2026-02-31 style dates that DateTime silently rolls over
  return (r.year == y && r.month == mo && r.day == d) ? r : null;
}

/// Source of "now". Injected everywhere so logic is testable and a tampered
/// device clock can later be corrected from the server time.
typedef Clock = DateTime Function();
