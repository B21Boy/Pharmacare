import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/lock/presentation/app_lock_controller.dart';

/// Two protections for a screen full of patient and money data:
///  1. Covers the app with a blank screen while it is in the app switcher
///     (so the thumbnail shows nothing).
///  2. Locks the app (PIN needed again) after it was in the background for
///     more than [lockAfter].
///
/// Also turn on FLAG_SECURE on Android to block screenshots; see README.
class PrivacyGuard extends ConsumerStatefulWidget {
  const PrivacyGuard({super.key, required this.child, this.lockAfter = const Duration(seconds: 60)});

  final Widget child;
  final Duration lockAfter;

  @override
  ConsumerState<PrivacyGuard> createState() => _PrivacyGuardState();
}

class _PrivacyGuardState extends ConsumerState<PrivacyGuard> with WidgetsBindingObserver {
  bool _covered = false;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        final at = _backgroundedAt;
        if (at != null && DateTime.now().difference(at) >= widget.lockAfter) {
          ref.read(appLockProvider.notifier).lock();
        }
        _backgroundedAt = null;
        setState(() => _covered = false);
      case AppLifecycleState.inactive:
        setState(() => _covered = true);
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _backgroundedAt ??= DateTime.now();
        setState(() => _covered = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        if (_covered) ColoredBox(color: Theme.of(context).colorScheme.surface),
      ],
    );
  }
}
