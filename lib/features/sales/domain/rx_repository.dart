import 'rx.dart';

/// Prescription log. Contains patient names, so only roles with the
/// `patients` permission may read it (enforce in Firestore rules too).
abstract interface class RxRepository {
  Stream<List<RxRecord>> watchRecent({int limit = 500});
  Future<int> nextSeq();
  /// Reserve a contiguous block so multi-Rx sales cannot collide with another device.
  Future<int> reserveSeqs(int count);
  Future<void> append(RxRecord record);
}
