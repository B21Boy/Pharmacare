import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/live_list.dart';
import '../domain/finance_expense.dart';

final class FinanceExpenseRepositoryImpl implements FinanceExpenseRepository {
  FinanceExpenseRepositoryImpl({required this.pharmacyId, required this.prefs, FirebaseFirestore? firestore}) : _firestore=firestore, _key='finance.expenses.$pharmacyId', _items=LiveList(_read(prefs,'finance.expenses.$pharmacyId'));
  final String pharmacyId, _key; final SharedPreferences prefs; final FirebaseFirestore? _firestore; final LiveList<FinanceExpense> _items;
  CollectionReference<Map<String,dynamic>> get _collection => _firestore!.collection('pharmacies').doc(pharmacyId).collection('financeExpenses');
  static List<FinanceExpense> _read(SharedPreferences p,String key) { try { return (jsonDecode(p.getString(key) ?? '[]') as List).whereType<Map>().map((x)=>FinanceExpense.fromMap(Map<String,dynamic>.from(x))).toList(); } catch (_) { return []; } }
  Future<void> _persist() => prefs.setString(_key,jsonEncode(_items.value.map((x)=>x.toMap()).toList()));
  @override Stream<List<FinanceExpense>> watch() {
    if (_firestore==null) return _items.watch();
    return Stream<List<FinanceExpense>>.multi((c) { c.add(_items.value); final s=_collection.orderBy('at',descending:true).snapshots().listen((x) async { final rows=x.docs.map((d)=>FinanceExpense.fromMap({...d.data(),'id':d.id})).toList(); _items.set(rows); await _persist(); c.add(rows); },onError:c.addError); c.onCancel=s.cancel; });
  }
  @override Future<void> add(FinanceExpense e) async { if (_firestore!=null) await _collection.doc(e.id).set(e.toMap()); _items.upsert(e, (old) => old.id == e.id); await _persist(); }
  @override Future<void> voidExpense(String id) async { final index=_items.value.indexWhere((e)=>e.id==id); if(index<0)return; final old=_items.value[index],next=FinanceExpense(id:old.id,at:old.at,category:old.category,amount:old.amount,note:old.note,by:old.by,voided:true); if(_firestore!=null) await _collection.doc(id).update({'voided':true}); final rows=List<FinanceExpense>.of(_items.value)..[index]=next; _items.set(rows); await _persist(); }
}
