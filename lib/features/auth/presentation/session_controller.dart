import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../lock/presentation/app_lock_controller.dart';
import '../domain/app_user.dart';

/// The signed-in user, or null. The router redirects on this value.
final sessionProvider = NotifierProvider<SessionController, AppUser?>(
  SessionController.new,
);

class SessionController extends Notifier<AppUser?> {
  @override
  AppUser? build() => null;

  void signedIn(AppUser user, {bool restored = false}) {
    state = user;
    ref
        .read(appLockProvider.notifier)
        .activateForUser(user.id, authenticated: !restored);
  }

  void profileUpdated(AppUser user) {
    if (state?.id == user.id) state = user;
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = null;
    await ref.read(appLockProvider.notifier).activateForUser(null);
  }
}
