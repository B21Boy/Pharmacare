import '../../inventory/domain/ingredients.dart';
import '../../inventory/domain/medicine.dart';
import '../../inventory/domain/stock_overview.dart';
import '../../../core/utils/money.dart';
import '../domain/assistant_service.dart';

/// Offline assistant: a port of `botReply` from the preview. Plain text
/// (no HTML). Answers come only from the pharmacy's own stock data, so it can
/// never invent a medical claim.
final class RuleBasedAssistant implements AssistantService {
  const RuleBasedAssistant();

  @override
  bool get isRemote => false;

  @override
  Future<String> reply(String question, {String? medicineId, required AssistantData data}) async {
    final low = question.toLowerCase();
    final stock = data.stock.where((s) => !s.medicine.archived).toList();
    final rules = data.rules;

    // 1) a medicine named in the question wins over the picked one
    MedStock? hit;
    for (final s in stock) {
      final first = s.medicine.name.toLowerCase().split(' ').first;
      if (first.length > 2 && low.contains(first) || (s.medicine.barcode.isNotEmpty && low.contains(s.medicine.barcode))) {
        hit = s;
        break;
      }
    }
    hit ??= medicineId == null ? null : stock.where((s) => s.medicine.id == medicineId).firstOrNull;

    if (hit == null) {
      if (RegExp('expir').hasMatch(low)) {
        final rows = <(int, String)>[];
        for (final s in stock) {
          for (final b in s.medicine.batches.where((b) => b.qty > 0)) {
            final d = rules.daysToExpiry(b);
            if (d <= rules.alertDaysFor(s.medicine)) {
              rows.add((d, '• ${s.medicine.name} ${b.no}: ${d < 0 ? 'expired ${-d} days ago' : '$d days left'} (${b.qty} units)'));
            }
          }
        }
        rows.sort((a, b) => a.$1.compareTo(b.$1));
        return rows.isEmpty
            ? 'Nothing is expiring within ${rules.defaultAlertDays} days.'
            : 'Batches needing attention:\n${rows.take(6).map((r) => r.$2).join('\n')}';
      }
      if (RegExp('low|reorder|out of').hasMatch(low)) {
        final rows = stock.where((s) => s.needsReorder).toList();
        return rows.isEmpty
            ? 'All medicines are above their reorder level.'
            : 'Low or out of stock:\n${rows.map((s) => '• ${s.medicine.name}: ${s.sellable} left (reorder at ${s.plan.level})').join('\n')}';
      }
      if (RegExp('sold|sales|sell|month').hasMatch(low)) {
        final monthStart = DateTime(rules.today.year, rules.today.month);
        final sales = data.recentSales.where((sale) => !data.returnedSaleIds.contains(sale.id) && !sale.at.isBefore(monthStart) && sale.at.isBefore(rules.today.add(const Duration(days: 1)))).toList();
        final units = sales.fold<int>(0, (sum, sale) => sum + sale.units);
        final total = sales.fold(Money.zero, (sum, sale) => sum + sale.total);
        return 'This month: ${sales.length} sales, $units units, total ${total.format()}.';
      }
      return 'Pick or scan a medicine first, then ask about its stock, expiry, storage or alternatives.';
    }

    final m = hit.medicine;
    final title = m.strength.isEmpty ? m.name : '${m.name} (${m.strength})';

    if (RegExp('expir|when does').hasMatch(low)) {
      final live = [...m.batches.where((b) => b.qty > 0)]..sort((a, b) => a.expiry.compareTo(b.expiry));
      if (live.isEmpty) return '$title has no stock, so nothing is expiring.';
      final lines = live.map((b) {
        final d = rules.daysToExpiry(b);
        return '• ${b.no}: ${d < 0 ? 'EXPIRED' : '$d days left'}, ${b.qty} units';
      }).join('\n');
      final anyExpired = live.any((b) => rules.daysToExpiry(b) < 0);
      return '$title batches:\n$lines${anyExpired ? '\nExpired units cannot be sold and should be removed from the shelf.' : ''}';
    }

    if (RegExp('storage|fridge|cold|keep |how.*store').hasMatch(low)) {
      return '${m.name}: ${m.coldStorage ? 'keep in the fridge (2–8°C)' : 'room temperature'}.';
    }

    if (RegExp('alternativ|substitut|instead|similar').hasMatch(low)) {
      final same = stock.where((s) => s.medicine.id != m.id && Ingredients.sameIngredient(s.medicine, m)).toList();
      final exact = same.where((s) => Ingredients.match(m, s.medicine) == AltMatch.exact && s.sellable > 0).toList();
      final other = same.where((s) => Ingredients.match(m, s.medicine) != AltMatch.exact).toList();
      final b = StringBuffer();
      if (exact.isEmpty) {
        b.write('No in-stock item with the same ingredient, form and strength. A pharmacist can suggest a therapeutic alternative.');
      } else {
        b.writeln('In stock with the same active ingredient, form and strength:');
        for (final s in exact) {
          b.writeln('• ${s.medicine.name}: ${s.sellable} units, ${s.medicine.price.format()}');
        }
        b.write('A pharmacist should confirm the substitution.');
      }
      if (other.isNotEmpty) {
        b.write('\nNot offered (different form or strength): ${other.map((s) => s.medicine.name).join(', ')}');
      }
      return b.toString();
    }

    if (RegExp('sold|sales|demand|how fast|how much|month').hasMatch(low)) {
      final monthly = RegExp('month').hasMatch(low);
      final from = monthly ? DateTime(rules.today.year, rules.today.month) : rules.today.subtract(const Duration(days: 29));
      final rows = data.recentSales.where((sale) => !data.returnedSaleIds.contains(sale.id) && !sale.at.isBefore(from) && sale.at.isBefore(rules.today.add(const Duration(days: 1)))).toList();
      var units = 0;
      var revenue = Money.zero;
      for (final sale in rows) {
        for (final line in sale.lines.where((line) => line.medicineId == m.id)) {
          units += line.qty;
          revenue += line.total;
        }
      }
      if (RegExp('month|how much|sold|sales').hasMatch(low)) {
        return monthly
            ? '$title: $units units sold this month for ${revenue.format()}.'
            : '$title: $units units sold in the last 30 days for ${revenue.format()}.';
      }
      final p = hit.plan;
      return p.auto
          ? '$title sells about ${p.dailyDemand.toStringAsFixed(1)} units per day. ${hit.sellable} in stock lasts about ${p.daysLeft?.floor() ?? 0} days.'
          : '$title has too little sales history for a forecast yet.';
    }

    if (RegExp('used for|dose|dosage|side effect|how to use|safe|pregnan|child|what.*use').hasMatch(low)) {
      return 'This stock record does not include verified medicine-use information. Check the package leaflet or ask the pharmacist. I can help with stock, expiry, storage and in-stock alternatives.';
    }

    return '$title: ${hit.sellable} sellable units, price ${m.price.format()}, reorder at ${hit.plan.level}.'
        '${m.type != MedType.otc ? '\nThis is a ${m.type == MedType.controlled ? 'controlled' : 'prescription'} medicine.' : ''}';
  }
}
