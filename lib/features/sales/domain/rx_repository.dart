import 'rx.dart';

/// Prescription log. Contains patient names, so only roles with the
/// `patients` permission may read it (enforce in Firestore rules too).
abstract interface class RxRepository {
  Stream<List<RxRecord>> watchRecent({int limit = 500});
  Future<int> nextSeq();
  Future<void> append(RxRecord record);
}
