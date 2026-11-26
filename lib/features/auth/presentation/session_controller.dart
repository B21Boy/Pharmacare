import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../lock/presentation/app_lock_controller.dart';
import '../domain/app_user.dart';

/// The signed-in user, or null. The router redirects on this value.
final sessionProvider = NotifierProvider<SessionController, AppUser?>(SessionController.new);

class SessionController extends Notifier<AppUser?> {
  @override
  AppUser? build() => null;

  void signedIn(AppUser user) {
    state = user;
    ref.read(appLockProvider.notifier).unlockedByLogin();
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    await ref.read(appLockProvider.notifier).clear();
    state = null;
  }
}
