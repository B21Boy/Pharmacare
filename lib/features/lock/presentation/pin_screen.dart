import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/ui_extensions.dart';
import '../../../core/i18n/tr.dart';
import '../data/biometric_auth.dart';
import '../domain/pin_policy.dart';
import 'app_lock_controller.dart';

/// Used for both "create your PIN" ([setup] = true) and "enter your PIN".
class PinScreen extends ConsumerStatefulWidget {
  const PinScreen({super.key, required this.setup});
  final bool setup;

  @override
  ConsumerState<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends ConsumerState<PinScreen> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  final _bio = BiometricAuth();
  String? _error;
  bool _busy = false;
  bool _bioAvailable = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    if (!widget.setup) {
      unawaited(_bio.isAvailable().then((v) {
        if (mounted) setState(() => _bioAvailable = v);
      }));
      // refresh the lockout countdown
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final tr = (ref.read(trProvider).valueOrNull ?? Tr.empty);
    final p = _pin.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    if (widget.setup) {
      if (!PinPolicy.isFormatOk(p)) {
        _fail(tr.t('Use 4 to 6 digits'));
      } else if (PinPolicy.isWeak(p)) {
        _fail(tr.t('That PIN is too easy to guess. Avoid 1234, 0000 and repeats'));
      } else if (p != _confirm.text.trim()) {
        _fail(tr.t('The two PINs do not match'));
      } else {
        await ref.read(appLockProvider.notifier).setupPin(p);
      }
    } else {
      final r = await ref.read(appLockProvider.notifier).unlock(p);
      if (!mounted) return;
      switch (r) {
        case UnlockOutcome.ok:
        case UnlockOutcome.signedOut:
          break;
        case UnlockOutcome.wrong:
          _fail(tr.t('Wrong PIN'));
        case UnlockOutcome.lockedOut:
          _fail(tr.t('Too many tries. Wait before trying again'));
      }
      _pin.clear();
    }
    if (mounted) setState(() => _busy = false);
  }

  void _fail(String msg) => setState(() {
        _error = msg;
        _busy = false;
      });

  Future<void> _biometric() async {
    final tr = (ref.read(trProvider).valueOrNull ?? Tr.empty);
    if (await _bio.authenticate(tr.t('Unlock PharmaCare'))) {
      ref.read(appLockProvider.notifier).unlockedByBiometric();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.tr;
    final lock = ref.watch(appLockProvider);
    final until = lock.lockedUntil;
    final secondsLeft = until == null ? 0 : until.difference(DateTime.now()).inSeconds;
    final lockedOut = !widget.setup && secondsLeft > 0;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    widget.setup ? tr.t('Create your PIN') : tr.t('Enter your PIN'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  if (widget.setup)
                    Text(tr.t('4 to 6 digits. You will use it to open the app.'), textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _pin,
                    enabled: !lockedOut && !_busy,
                    autofocus: true,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: PinPolicy.maxLength,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 28, letterSpacing: 12),
                    decoration: const InputDecoration(counterText: ''),
                    onSubmitted: widget.setup ? null : (_) => _submit(),
                  ),
                  if (widget.setup) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirm,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: PinPolicy.maxLength,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 28, letterSpacing: 12),
                      decoration: InputDecoration(counterText: '', labelText: tr.t('Repeat your PIN')),
                      onSubmitted: (_) => _submit(),
                    ),
                  ],
                  if (lockedOut)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        tr.f('Too many tries. Try again in {n} seconds', {'n': secondsLeft}),
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: (_busy || lockedOut) ? null : _submit,
                      child: Text(widget.setup ? tr.t('Save PIN') : tr.t('Unlock')),
                    ),
                  ),
                  if (!widget.setup && _bioAvailable && !lockedOut)
                    TextButton.icon(
                      onPressed: _biometric,
                      icon: const Icon(Icons.fingerprint),
                      label: Text(tr.t('Use fingerprint or face')),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
