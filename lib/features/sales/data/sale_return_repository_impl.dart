import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/storage/hive_cache.dart';
import '../../../core/utils/live_list.dart';
import '../domain/sale_return.dart';

final class SaleReturnRepositoryImpl implements SaleReturnRepository {
  SaleReturnRepositoryImpl({required this.pharmacyId, required this.cache, FirebaseFirestore? firestore}) : _firestore = firestore, _key = 'sale-returns.$pharmacyId', _items = LiveList((cache.readDocuments('sale-returns.$pharmacyId') ?? const []).map((x) => SaleReturn.fromMap(Map<String,dynamic>.from(x))));
  final String pharmacyId, _key;
  final HiveCacheStore cache;
  final FirebaseFirestore? _firestore;
  final LiveList<SaleReturn> _items;
  CollectionReference<Map<String,dynamic>> get _collection => _firestore!.collection('pharmacies').doc(pharmacyId).collection('saleReturns');
  @override Stream<List<SaleReturn>> watchReturns() {
    if (_firestore == null) return _items.watch();
    return Stream<List<SaleReturn>>.multi((controller) {
      controller.add(_items.value);
      final sub = _collection.orderBy('at', descending: true).snapshots().listen((s) async {
        final rows = s.docs.map((d) => SaleReturn.fromMap({...d.data(), 'id': d.id})).toList();
        _items.set(rows); await cache.writeDocuments(_key, rows.map((x) => x.toMap())); controller.add(rows);
      }, onError: controller.addError);
      controller.onCancel = sub.cancel;
    });
  }
  @override Future<void> append(SaleReturn record) async {
    if (_firestore != null) {
      final doc = _collection.doc(record.id);
      await _firestore!.runTransaction((tx) async {
        final old = await tx.get(doc);
        if (old.exists) throw StateError('This sale was already returned');
        tx.set(doc, record.toMap());
      });
    }
    _items.add(record); await cache.writeDocuments(_key, _items.value.map((x) => x.toMap()));
  }
}
