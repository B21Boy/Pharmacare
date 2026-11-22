/// Numbers that the HTML keeps in constants.
class PlanConfig {
  const PlanConfig._();
  static const int look = 30; // days of sales used to measure daily pace
  static const int safe = 1; // safety days
  static const int cover = 14; // days of sales an order should cover
  static const int minUnits = 5; // minimum units sold to trust auto-planning
}

const int overdueDays = 30; // OVERDUE_DAYS
const int latePoDays = 3; // LATE_PO_DAYS
const int defaultAlertDays = 90; // S.alertDays

/// Default credit limit per customer (CRED_DEF).
const double defaultCreditLimit = 2000;

/// Highest discount in percent each role may give (DMAX).
const Map<String, int> maxDiscountPercent = {
  'owner': 100,
  'pharmacist': 10,
  'cashier': 5,
};

/// Preview-only owner PIN (OWNER_PIN). Replace with real auth.
const String previewOwnerPin = '1234';
