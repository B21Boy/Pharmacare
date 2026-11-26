import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/app_user.dart';
import '../domain/role.dart';
import 'session_controller.dart';

/// Current user; only valid on screens behind the sign-in redirect.
final currentUserProvider = Provider<AppUser>((ref) {
  final u = ref.watch(sessionProvider);
  if (u == null) throw StateError('No signed-in user');
  return u;
});

/// `ref.watch(canProvider(Permission.cost))` - rebuilds only when the answer changes.
final canProvider = Provider.family<bool, Permission>(
  (ref, p) => ref.watch(sessionProvider.select((u) => u != null && Permissions.can(u.role, p))),
);
