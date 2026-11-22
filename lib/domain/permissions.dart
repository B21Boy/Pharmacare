import '../core/constants/roles.dart';

/// Who sees what. To change a role's rights, edit this one table (PERM in the HTML).
const Map<UserRole, Set<Perm>> rolePermissions = {
  UserRole.owner: {
    Perm.profit,
    Perm.cost,
    Perm.finance,
    Perm.ops,
    Perm.patients,
    Perm.export
  },
  UserRole.pharmacist: {Perm.cost, Perm.ops, Perm.patients, Perm.export},
  UserRole.cashier: <Perm>{},
};

bool roleCan(UserRole role, Perm p) =>
    rolePermissions[role]?.contains(p) ?? false;

/// Screens that need a permission (NEED in the HTML). Others are open to all.
const Map<String, Perm> screenNeeds = {
  'finance': Perm.finance,
  'audit': Perm.ops,
  'orders': Perm.ops,
  'suppliers': Perm.ops,
  'stocktake': Perm.ops,
  'rxlog': Perm.ops,
  'credit': Perm.ops,
  'customer': Perm.ops,
  'register': Perm.ops,
};

/// Owner and pharmacist may edit stock; cashier may not (canEdit()).
bool roleCanEdit(UserRole role) =>
    role == UserRole.owner || role == UserRole.pharmacist;
