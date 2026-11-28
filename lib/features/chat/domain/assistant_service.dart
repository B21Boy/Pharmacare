import '../../inventory/domain/stock_overview.dart';
import '../../inventory/domain/stock_rules.dart';
import '../../sales/domain/sale.dart';

/// A snapshot of the stock the assistant may talk about.
class AssistantData {
  const AssistantData({required this.stock, required this.rules, this.recentSales = const [], this.returnedSaleIds = const {}});
  final List<MedStock> stock;
  final StockRules rules;
  final List<SaleRecord> recentSales;
  final Set<String> returnedSaleIds;
}

/// The pharmacy assistant. Two implementations:
///  - [RuleBasedAssistant]: works offline, answers from the stock data.
///  - GeminiAssistant: calls the configured backend, which calls Gemini.
abstract interface class AssistantService {
  /// true = the question leaves the phone, so personal data is scrubbed first.
  bool get isRemote;

  Future<String> reply(String question, {String? medicineId, required AssistantData data});
}
