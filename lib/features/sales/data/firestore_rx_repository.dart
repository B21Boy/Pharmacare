import 'package:cloud_firestore/cloud_firestore.dart';

import '../../inventory/domain/medicine.dart';
import '../domain/rx.dart';
import '../domain/rx_repository.dart';

/// Append-only pharmacy prescription register.
final class FirestoreRxRepository implements RxRepository {
  FirestoreRxRepository({required this.pharmacyId, FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final String pharmacyId;
  final FirebaseFirestore _db;
  CollectionReference<Map<String, dynamic>> get _entries => _db.collection('pharmacies').doc(pharmacyId).collection('rxLog');
  DocumentReference<Map<String, dynamic>> get _counter => _db.collection('pharmacies').doc(pharmacyId).collection('rxMeta').doc('sequence');

  @override
  Stream<List<RxRecord>> watchRecent({int limit = 500}) => _entries
      .orderBy('at', descending: true).limit(limit).snapshots()
      .map((snapshot) => snapshot.docs.map((doc) => _fromMap((doc.data()['seq'] as num?)?.toInt() ?? int.tryParse(doc.id) ?? 0, doc.data())).toList());

  @override
  Future<int> nextSeq() => reserveSeqs(1);

  @override
  Future<int> reserveSeqs(int count) => _db.runTransaction((transaction) async {
    final snapshot = await transaction.get(_counter);
    final start = ((snapshot.data()?['lastSeq'] as num?)?.toInt() ?? 0) + 1;
    transaction.set(_counter, {'lastSeq': start + count.clamp(0, 1000).toInt() - 1});
    return start;
  });

  @override
  Future<void> append(RxRecord record) => _entries.doc(record.seq.toString().padLeft(8, '0')).set(_toMap(record));

  Map<String, Object?> _toMap(RxRecord r) => {
    'seq': r.seq, 'at': r.at.millisecondsSinceEpoch, 'saleId': r.saleId, 'medicineId': r.medicineId,
    'qty': r.qty, 'kind': r.kind.name, 'patient': r.patient, 'age': r.age, 'sex': r.sex,
    'phone': r.phone, 'patientId': r.patientId, 'rxNo': r.rxNo,
    'prescriptionDate': r.rxDate?.millisecondsSinceEpoch, 'prescriber': r.prescriber,
    'license': r.license, 'facility': r.facility, 'directions': r.directions,
    'soldBy': r.soldBy, 'batches': r.batches,
    'voided': r.voided, 'correctsSeq': r.correctsSeq, 'correctionReason': r.correctionReason,
    'correctionNote': r.correctionNote, 'correctedBy': r.correctedBy,
  };

  RxRecord _fromMap(int seq, Map<String, dynamic> x) => RxRecord(
    seq: seq, at: DateTime.fromMillisecondsSinceEpoch((x['at'] as num?)?.toInt() ?? 0),
    saleId: x['saleId'] as String? ?? '', medicineId: x['medicineId'] as String? ?? '',
    qty: (x['qty'] as num?)?.toInt() ?? 0,
    kind: MedType.values.firstWhere((t) => t.name == x['kind'], orElse: () => MedType.rx),
    patient: x['patient'] as String? ?? '', rxNo: x['rxNo'] as String? ?? '',
    prescriber: x['prescriber'] as String? ?? '',
    rxDate: x['prescriptionDate'] is num ? DateTime.fromMillisecondsSinceEpoch((x['prescriptionDate'] as num).toInt()) : null,
    age: x['age'] as String? ?? '', sex: x['sex'] as String? ?? '', phone: x['phone'] as String? ?? '',
    patientId: x['patientId'] as String? ?? '', license: x['license'] as String? ?? '',
    facility: x['facility'] as String? ?? '', directions: x['directions'] as String? ?? '',
    soldBy: x['soldBy'] as String? ?? '', batches: (x['batches'] as List? ?? const []).whereType<String>().toList(),
    voided: x['voided'] as bool? ?? false,
    correctsSeq: (x['correctsSeq'] as num?)?.toInt(),
    correctionReason: x['correctionReason'] as String? ?? '', correctionNote: x['correctionNote'] as String? ?? '',
    correctedBy: x['correctedBy'] as String? ?? '',
  );
}
