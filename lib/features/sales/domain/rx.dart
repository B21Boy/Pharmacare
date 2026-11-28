import 'package:flutter/foundation.dart';

import '../../../core/utils/date_utils.dart';
import '../../inventory/domain/medicine.dart';

/// What the pharmacist types for a prescription medicine.
@immutable
final class RxDetails {
  const RxDetails({this.patient = '', this.rxNo = '', this.prescriber = '', this.rxDate, this.age = '', this.sex = '', this.phone = '', this.patientId = '', this.license = '', this.facility = '', this.directions = ''});
  final String patient;
  final String rxNo;
  final String prescriber;
  final DateTime? rxDate;
  final String age, sex, phone, patientId, license, facility, directions;

  RxDetails copyWith({String? patient, String? rxNo, String? prescriber, DateTime? rxDate, String? age, String? sex, String? phone, String? patientId, String? license, String? facility, String? directions}) => RxDetails(
        patient: patient ?? this.patient,
        rxNo: rxNo ?? this.rxNo,
        prescriber: prescriber ?? this.prescriber,
        rxDate: rxDate ?? this.rxDate,
        age: age ?? this.age, sex: sex ?? this.sex, phone: phone ?? this.phone,
        patientId: patientId ?? this.patientId, license: license ?? this.license,
        facility: facility ?? this.facility, directions: directions ?? this.directions,
      );
}

/// One row of the Rx log. Rows are never edited or deleted (legal record);
/// a mistake is corrected with a NEW row that voids the old one.
@immutable
final class RxRecord {
  const RxRecord({
    required this.seq,
    required this.at,
    required this.saleId,
    required this.medicineId,
    required this.qty,
    required this.kind,
    required this.patient,
    required this.rxNo,
    required this.prescriber,
    this.rxDate,
    this.voided = false,
    this.age = '', this.sex = '', this.phone = '', this.patientId = '', this.license = '', this.facility = '', this.directions = '', this.soldBy = '', this.batches = const [],
    this.correctsSeq, this.correctionReason = '', this.correctionNote = '', this.correctedBy = '',
  });

  final int seq;
  final DateTime at;
  final String saleId;
  final String medicineId;
  final int qty;
  final MedType kind;
  final String patient;
  final String rxNo;
  final String prescriber;
  final DateTime? rxDate;
  final bool voided;
  final String age, sex, phone, patientId, license, facility, directions;
  final String soldBy;
  final List<String> batches;
  final int? correctsSeq;
  final String correctionReason, correctionNote;
  final String correctedBy;

  /// "RL-00007"
  String get id => 'RL-${seq.toString().padLeft(5, '0')}';
}

/// A rule message: [key] is a translation key, [args] fill its `{placeholders}`.
@immutable
final class RuleIssue {
  const RuleIssue(this.key, [this.args = const {}]);
  final String key;
  final Map<String, Object> args;
}

/// Prescription safety checks (`RF` + `rfRules` in the preview).
abstract final class RxPolicy {
  static const int windowDays = 7; // look-back for controlled drugs
  static const int controlledMaxInWindow = 2;
  static const int maxQtyControlled = 30;
  static const int maxQtyRx = 100;
  static const int validDaysControlled = 14;
  static const int validDaysRx = 30;

  static String _norm(String s) => s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Warnings for one prescription line. Empty = nothing suspicious.
  static List<RuleIssue> check({
    required Medicine medicine,
    required int qty,
    required RxDetails details,
    required List<RxRecord> history,
    required DateTime now,
  }) {
    if (medicine.type == MedType.otc) return const [];
    final out = <RuleIssue>[];
    final ctrl = medicine.type == MedType.controlled;
    final patient = _norm(details.patient);
    final rxNo = _norm(details.rxNo);
    final live = history.where((r) => !r.voided && !history.any((x) => x.correctsSeq == r.seq));

    final requiredFields = <String, String>{
      'Patient name': details.patient, 'Patient age': details.age,
      'Sex': details.sex, 'Rx number': details.rxNo,
      'Prescriber': details.prescriber, 'Prescriber license': details.license,
      'Dose and directions': details.directions,
    };
    if (details.rxDate == null) requiredFields['Prescription date'] = '';
    if (ctrl) {
      requiredFields['Patient phone'] = details.phone;
      requiredFields['Patient ID number'] = details.patientId;
      requiredFields['Facility'] = details.facility;
    }
    for (final item in requiredFields.entries) {
      if (item.value.trim().isEmpty) out.add(RuleIssue('Enter {field}', {'field': item.key}));
    }
    final ageValue = int.tryParse(details.age.trim());
    if (details.age.trim().isNotEmpty && (ageValue == null || ageValue < 0 || ageValue > 120)) {
      out.add(const RuleIssue('Patient age must be from 0 to 120'));
    }
    if (details.phone.trim().isNotEmpty && details.phone.replaceAll(RegExp(r'\D'), '').length < 9) {
      out.add(const RuleIssue('Patient phone number is too short'));
    }
    if (details.rxDate != null && details.rxDate!.isAfter(DateTime(now.year, now.month, now.day))) {
      out.add(const RuleIssue('Prescription date cannot be in the future'));
    }

    if (ctrl && patient.isNotEmpty) {
      final k = live
          .where((r) =>
              r.kind == MedType.controlled &&
              now.difference(r.at).inDays < windowDays &&
              _norm(r.patient) == patient)
          .length;
      if (k >= controlledMaxInWindow) {
        out.add(RuleIssue('This patient already took a controlled drug {k} times in {d} days',
            {'k': k, 'd': windowDays}));
      }
    }
    if (rxNo.isNotEmpty) {
      final k = live
          .where((r) =>
              _norm(r.rxNo) == rxNo &&
              now.difference(r.at).inDays < 30 &&
              (r.medicineId == medicine.id || _norm(r.patient) != patient))
          .length;
      if (k > 0) {
        out.add(RuleIssue('Rx number {no} was already used {k} time(s) in the last 30 days',
            {'no': details.rxNo.trim(), 'k': k}));
      }
    }
    final maxQty = ctrl ? maxQtyControlled : maxQtyRx;
    if (qty > maxQty) {
      out.add(RuleIssue('{q} units is above the usual limit of {m}', {'q': qty, 'm': maxQty}));
    }
    final rd = details.rxDate;
    if (rd != null) {
      final age = daysBetween(rd, now);
      final valid = ctrl ? validDaysControlled : validDaysRx;
      if (age > valid) {
        out.add(RuleIssue('The prescription is {a} days old (valid {v} days)', {'a': age, 'v': valid}));
      }
    }
    return out;
  }
}
