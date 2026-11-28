enum Role {
  owner,
  pharmacist,
  cashier;

  String get labelKey => switch (this) {
        Role.owner => 'Owner',
        Role.pharmacist => 'Pharmacist',
        Role.cashier => 'Cashier',
      };

  static Role fromName(String? n) =>
      Role.values.firstWhere((r) => r.name == n, orElse: () => Role.cashier);
}

enum Permission { profit, cost, finance, ops, patients, export }

/// Who sees what. To change a role's rights, edit this one table.
/// (Port of `PERM` from the HTML preview.) The SAME rules must also exist in
/// `firebase/firestore.rules`, because the phone can be tampered with.
abstract final class Permissions {
  static const Map<Role, Set<Permission>> _table = {
    Role.owner: {
      Permission.profit, Permission.cost, Permission.finance,
      Permission.ops, Permission.patients, Permission.export,
    },
    Role.pharmacist: {
      Permission.cost, Permission.ops, Permission.patients, Permission.export,
    },
    Role.cashier: {},
  };

  static bool can(Role role, Permission p) => _table[role]?.contains(p) ?? false;

  /// Maximum discount (percent of the sale) a role may give without approval.
  static const Map<Role, int> maxDiscountPercent = {
    Role.owner: 100,
    Role.pharmacist: 10,
    Role.cashier: 5,
  };

  /// Which permission each top-level route needs (`NEED` in the preview).
  static const Map<String, Permission> routeNeeds = {
    '/inventory/register': Permission.ops,
    '/finance': Permission.finance,
    '/audit': Permission.ops,
    '/orders': Permission.ops,
    '/suppliers': Permission.ops,
    '/stocktake': Permission.ops,
    '/rxlog': Permission.ops,
    '/credit': Permission.ops,
  };

  static bool canOpen(Role role, String path) {
    final need = routeNeeds[path];
    return need == null || can(role, need);
  }
}
