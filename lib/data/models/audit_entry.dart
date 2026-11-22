/// Audit log entry (log() in the HTML).
/// type: sale | stock | count | credit | order | rx | miss | report | access | risk
class AuditEntry {
  AuditEntry({
    required this.ts,
    required this.user,
    required this.type,
    required this.action,
    this.detail = '',
    this.role = '',
    this.amount,
    this.ref = '',
    this.medId = '',
  });

  final int ts;
  final String user; // "Selam (Pharmacist)"
  final String type;
  final String action;
  final String detail;
  final String role;
  final double? amount;
  final String ref;
  final String medId;
}
