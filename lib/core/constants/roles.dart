/// Staff roles (ROLES in the HTML).
enum UserRole { owner, pharmacist, cashier }

extension UserRoleX on UserRole {
  /// English label, also the translation key.
  String get label {
    switch (this) {
      case UserRole.owner:
        return 'Owner';
      case UserRole.pharmacist:
        return 'Pharmacist';
      case UserRole.cashier:
        return 'Cashier';
    }
  }

  String get key => name;

  /// One-line explanation shown in Settings (ROLE_NOTE).
  String get note {
    switch (this) {
      case UserRole.owner:
        return 'Owner: sees everything.';
      case UserRole.pharmacist:
        return 'Pharmacist: sales, Rx and stock. Profit and the Finance page are hidden.';
      case UserRole.cashier:
        return 'Cashier: sales only. Profit, purchase cost and stock work are hidden.';
    }
  }

  static UserRole fromKey(String k) => UserRole.values
      .firstWhere((r) => r.name == k, orElse: () => UserRole.cashier);
}

/// Permission keys used by `can(...)` in the HTML.
enum Perm { profit, cost, finance, ops, patients, export }
