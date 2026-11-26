import 'dart:async';

/// A list that can be watched. Every in-memory repository uses this, so the
/// demo and the real (Firestore / Drift) repositories expose the same
/// `Stream<List<T>>` shape to the UI.
final class LiveList<T> {
  LiveList([Iterable<T>? initial]) : _items = List<T>.of(initial ?? <T>[]);

  List<T> _items;
  final StreamController<List<T>> _changes = StreamController<List<T>>.broadcast();

  /// Immutable snapshot.
  List<T> get value => List<T>.unmodifiable(_items);

  Stream<List<T>> watch() => Stream<List<T>>.multi((c) {
        c.add(value);
        final sub = _changes.stream.listen(c.add);
        c.onCancel = sub.cancel;
      });

  void set(Iterable<T> items) {
    _items = List<T>.of(items);
    _changes.add(value);
  }

  void add(T item) => set([..._items, item]);

  /// Replace the first element matching [test], or append when none matches.
  void upsert(T item, bool Function(T existing) test) {
    final i = _items.indexWhere(test);
    final next = List<T>.of(_items);
    if (i < 0) {
      next.add(item);
    } else {
      next[i] = item;
    }
    set(next);
  }
}
