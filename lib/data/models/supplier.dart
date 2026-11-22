/// Supplier (SUPS in the HTML).
class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    required this.phone,
    required this.termsDays, // days to pay after delivery (0 = pay on delivery)
    required this.leadDays, // days the supplier takes to deliver
  });

  final String id;
  final String name;
  final String phone;
  final int termsDays;
  final int leadDays;
}
