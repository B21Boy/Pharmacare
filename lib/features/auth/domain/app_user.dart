import 'package:flutter/foundation.dart';

import 'role.dart';

@immutable
final class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.role,
    required this.deviceTag,
    required this.phone,
    this.pharmacyId = '',
  });

  final String id;
  final String name;
  final Role role;

  /// Short tag used in receipt / Rx numbers and the audit chain, e.g. `OWN-01`.
  final String deviceTag;
  final String phone;
  final String pharmacyId;

  /// "Selam (Pharmacist)" - the form used in audit entries.
  String get audited => '$name (${role.name[0].toUpperCase()}${role.name.substring(1)})';
}
