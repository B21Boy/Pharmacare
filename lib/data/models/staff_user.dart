import '../../core/constants/roles.dart';

/// A person who signs in to one pharmacy. The owner adds staff and picks roles.
class StaffUser {
  StaffUser({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
    this.active = true,
  });

  final String id;
  String name;
  String phone; // national format, e.g. 911223344
  UserRole role;
  bool active; // false = suspended
}

/// Pharmacy profile shown on receipts and reports.
class PharmacyProfile {
  PharmacyProfile({
    this.name = 'PharmaCare Pharmacy',
    this.address = '',
    this.phone = '',
    this.tin = '',
    this.license = '',
    this.responsiblePharmacist = '',
    this.pharmacistLicense = '',
  });

  String name;
  String address;
  String phone;
  String tin; // 10 digits
  String license;
  String responsiblePharmacist;
  String pharmacistLicense;
}
