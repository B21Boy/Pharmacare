import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/ui_extensions.dart';
import '../data/biometric_auth.dart';
import '../domain/pin_policy.dart';
import 'app_lock_controller.dart';

/// A device-local PIN gate. Every signed-in account on the device gets its
/// own PIN and biometric preference.
class PinScreen extends ConsumerStatefulWidget {
  const PinScreen({super.key, required this.setup});
  final bool setup;

  @override
  ConsumerState<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends ConsumerState<PinScreen> {
  final _bio = BiometricAuth();
  String _pin = '';
  String _firstPin = '';
  String? _error;
  bool _busy = false;
  bool _bioAvailable = false;
  bool _bioEnabled = false;
  int _stage = 1;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBiometric());
    if (!widget.setup) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _loadBiometric() async {
    final available = await _bio.isAvailable();
    final enabled = widget.setup
        ? false
        : await ref.read(appLockProvider.notifier).biometricEnabled();
    if (mounted) {
      setState(() {
        _bioAvailable = available;
        _bioEnabled = enabled;
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _press(String key) async {
    if (_busy) return;
    if (key == 'delete') {
      setState(() {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
        _error = null;
      });
      return;
    }
    if (_pin.length >= 4) return;
    setState(() {
      _pin += key;
      _error = null;
    });
    if (_pin.length == 4) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted || _pin.length != 4) return;
      if (widget.setup) {
        await _acceptSetupStage();
      } else {
        await _unlock();
      }
    }
  }

  Future<void> _acceptSetupStage() async {
    final value = _pin;
    if (_stage == 1) {
      if (PinPolicy.isWeak(value)) {
        setState(() {
          _pin = '';
          _error = ref.tr.t(
            'That PIN is too easy to guess. Choose a less predictable PIN.',
          );
        });
        return;
      }
      setState(() {
        _firstPin = value;
        _pin = '';
        _stage = 2;
      });
      return;
    }
    if (value != _firstPin) {
      setState(() {
        _pin = '';
        _firstPin = '';
        _stage = 1;
        _error = ref.tr.t('PINs do not match. Try again.');
      });
      return;
    }

    setState(() => _busy = true);
    final lock = ref.read(appLockProvider.notifier);
    final saved = await lock.setupPin(_firstPin);
    if (saved) await lock.setBiometricEnabled(_bioAvailable && _bioEnabled);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!saved) {
        _pin = '';
        _firstPin = '';
        _stage = 1;
        _error = ref.tr.t('Could not save your PIN. Please try again.');
      }
    });
  }

  Future<void> _unlock() async {
    setState(() => _busy = true);
    final outcome = await ref.read(appLockProvider.notifier).unlock(_pin);
    if (!mounted) return;
    final tr = ref.tr;
    setState(() {
      _busy = false;
      _pin = '';
      switch (outcome) {
        case UnlockOutcome.ok:
        case UnlockOutcome.signedOut:
          _error = null;
        case UnlockOutcome.wrong:
          _error = tr.t('Wrong PIN');
        case UnlockOutcome.lockedOut:
          _error = tr.t('Too many tries. Wait before trying again');
      }
    });
  }

  Future<void> _authenticateBiometric() async {
    final tr = ref.tr;
    if (await _bio.authenticate(tr.t('Unlock PharmaCare'))) {
      ref.read(appLockProvider.notifier).unlockedByBiometric();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.tr;
    final lock = ref.watch(appLockProvider);
    final secondsLeft = lock.lockedUntil == null
        ? 0
        : lock.lockedUntil!.difference(DateTime.now()).inSeconds;
    final lockedOut = !widget.setup && secondsLeft > 0;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2557E8), Color(0xFF17369F), Color(0xFF0A1A5C)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x52030A32),
                        blurRadius: 36,
                        offset: Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(17),
                          ),
                          child: Icon(
                            widget.setup
                                ? Icons.password_rounded
                                : Icons.lock_rounded,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.setup
                              ? tr.t(
                                  _stage == 1
                                      ? 'Create a PIN'
                                      : 'Confirm your PIN',
                                )
                              : tr.t('Enter your PIN'),
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.4,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.setup
                              ? tr.t(
                                  'Choose 4 digits. You will use it to open the app on this device.',
                                )
                              : tr.t('Enter your 4-digit PIN to continue.'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                        if (widget.setup) ...[
                          const SizedBox(height: 18),
                          _setupProgress(colors),
                        ],
                        const SizedBox(height: 20),
                        _pinDots(colors),
                        SizedBox(
                          height: 40,
                          child: Center(
                            child: Text(
                              _error ?? ' ',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: colors.error,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        _keypad(colors, lockedOut: lockedOut),
                        if (widget.setup && _bioAvailable)
                          SwitchListTile.adaptive(
                            contentPadding: const EdgeInsets.only(top: 12),
                            value: _bioEnabled,
                            onChanged: (value) =>
                                setState(() => _bioEnabled = value),
                            secondary: const Icon(Icons.fingerprint_rounded),
                            title: Text(tr.t('Use fingerprint or face unlock')),
                          )
                        else if (!widget.setup &&
                            _bioAvailable &&
                            _bioEnabled &&
                            !lockedOut)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: OutlinedButton.icon(
                              onPressed: _authenticateBiometric,
                              icon: const Icon(Icons.fingerprint_rounded),
                              label: Text(tr.t('Use fingerprint or face')),
                            ),
                          ),
                        if (lockedOut)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              tr.f('Too many tries. Try again in {n} seconds', {
                                'n': secondsLeft,
                              }),
                              style: TextStyle(color: colors.error),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        if (!widget.setup && !_bioAvailable)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              tr.t(
                                'Biometric unlock is not available on this device.',
                              ),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _setupProgress(ColorScheme colors) => Row(
    children: [
      for (var i = 1; i <= 2; i++) ...[
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 5,
            decoration: BoxDecoration(
              color: _stage >= i ? colors.primary : colors.outlineVariant,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
        if (i == 1) const SizedBox(width: 8),
      ],
    ],
  );

  Widget _pinDots(ColorScheme colors) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < 4; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          width: 15,
          height: 15,
          margin: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i < _pin.length ? colors.primary : Colors.transparent,
            border: Border.all(
              color: _error == null ? colors.outlineVariant : colors.error,
              width: 2,
            ),
          ),
        ),
    ],
  );

  Widget _keypad(ColorScheme colors, {required bool lockedOut}) {
    const keys = [
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '',
      '0',
      'delete',
    ];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: keys.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisExtent: 54,
          mainAxisSpacing: 9,
          crossAxisSpacing: 10,
        ),
        itemBuilder: (context, index) {
          final key = keys[index];
          if (key.isEmpty) return const SizedBox.shrink();
          return Material(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _busy || lockedOut
                  ? null
                  : () => _press(key == 'delete' ? 'delete' : key),
              child: Center(
                child: key == 'delete'
                    ? const Icon(Icons.backspace_outlined)
                    : Text(
                        key,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}
