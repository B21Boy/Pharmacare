import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/ui_extensions.dart';
import '../../../core/config/env.dart';
import '../../../core/error/failure_text.dart';
import '../../../core/i18n/tr.dart';
import '../../../data/providers.dart';
import '../../lock/data/biometric_auth.dart';
import '../../lock/domain/pin_policy.dart';
import '../../lock/presentation/app_lock_controller.dart';
import '../../settings/presentation/settings_controller.dart';
import '../domain/app_user.dart';
import '../domain/ethiopian_phone.dart';
import 'session_controller.dart';

/// Phone sign-in and the staged owner-registration flow from the HTML preview.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phone = TextEditingController();
  final _name = TextEditingController();
  final _codeControllers = List.generate(6, (_) => TextEditingController());
  final _codeFocus = List.generate(6, (_) => FocusNode());
  final _bio = BiometricAuth();
  final _pharmacy = <String, TextEditingController>{
    'name': TextEditingController(),
    'address': TextEditingController(),
    'phone': TextEditingController(),
    'tin': TextEditingController(),
    'licenseNumber': TextEditingController(),
    'responsiblePharmacist': TextEditingController(),
    'pharmacistLicense': TextEditingController(),
  };
  final _fieldErrors = <String, String>{};

  String? _verificationId;
  String? _error;
  String _pinFirst = '';
  String _pinValue = '';
  AppUser? _pendingUser;
  DateTime? _sentAt;
  Timer? _timer;
  bool _busy = false;
  bool _register = false;
  bool _acceptedTerms = false;
  bool _biometricAvailable = false;
  bool _useBiometric = false;
  String? _ownerNameError;
  int _step = 0;
  int _pinStage = 1;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _name.dispose();
    for (final c in _codeControllers) {
      c.dispose();
    }
    for (final f in _codeFocus) {
      f.dispose();
    }
    for (final c in _pharmacy.values) {
      c.dispose();
    }
    super.dispose();
  }

  String get _normalizedPhone => EthiopianPhone.normalize(_phone.text);
  String get _code => _codeControllers.map((c) => c.text).join();

  void _clearCode() {
    for (final c in _codeControllers) {
      c.clear();
    }
  }

  void _setMode(bool register) {
    setState(() {
      _register = register;
      _step = 0;
      _verificationId = null;
      _pendingUser = null;
      _sentAt = null;
      _error = null;
      _acceptedTerms = false;
      _ownerNameError = null;
      _fieldErrors.clear();
      _pinValue = '';
      _pinFirst = '';
      _pinStage = 1;
      _clearCode();
    });
  }

  void _setLanguage(AppLang language) =>
      ref.read(settingsProvider.notifier).setLanguage(language);

  Future<void> _sendCode() async {
    final tr = ref.read(trProvider).valueOrNull ?? Tr.empty;
    if (!EthiopianPhone.isValid(_normalizedPhone)) {
      setState(
        () => _error = tr.t(
          'Enter a valid Ethiopian mobile number, for example 0911 000 001.',
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = ref.read(authRepositoryProvider);
      final result = _register
          ? await auth.beginOwnerRegistration(_normalizedPhone)
          : await auth.sendCode(_normalizedPhone);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _verificationId = result.valueOrNull;
        if (_verificationId != null) {
          _sentAt = DateTime.now();
          _clearCode();
          _step = 1;
        }
        if (result.failureOrNull case final failure?) {
          _error = failureText(tr, failure);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = tr.t('Could not send the code. Please try again.');
      });
    }
  }

  Future<void> _verifyCode() async {
    final tr = ref.read(trProvider).valueOrNull ?? Tr.empty;
    final id = _verificationId;
    if (id == null || _busy) return;
    if (_code.length != 6) {
      setState(() => _error = tr.t('Enter the 6-digit code'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = ref.read(authRepositoryProvider);
      if (_register) {
        final result = await auth.verifyOwnerRegistrationCode(
          verificationId: id,
          code: _code,
        );
        if (!mounted) return;
        setState(() {
          _busy = false;
          if (result.valueOrNull == true) {
            _step = 2;
            _clearCode();
          } else {
            _error = failureText(tr, result.failureOrNull!);
            _clearCode();
          }
        });
        return;
      }

      final result = await auth.verifyCode(verificationId: id, code: _code);
      if (!mounted) return;
      final user = result.valueOrNull;
      if (user != null) {
        setState(() {
          _busy = false;
          _pendingUser = user;
          _step = 5;
          _clearCode();
        });
      } else {
        setState(() {
          _busy = false;
          _error = failureText(tr, result.failureOrNull!);
          _clearCode();
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = tr.t('Could not verify the code. Please try again.');
      });
    }
  }

  Future<void> _continue() async {
    final tr = ref.read(trProvider).valueOrNull ?? Tr.empty;
    setState(() => _error = null);
    if (_step == 0) {
      await _sendCode();
    } else if (_step == 1) {
      await _verifyCode();
    } else if (_step == 2) {
      final errors = <String, String>{};
      String value(String key) => _pharmacy[key]!.text.trim();
      if (value('name').length < 2) {
        errors['name'] = tr.t('Enter the pharmacy name');
      }
      if (value('address').isNotEmpty && value('address').length < 4) {
        errors['address'] = tr.t('Enter a complete pharmacy address');
      }
      final pharmacyPhone = value('phone');
      if (pharmacyPhone.isNotEmpty &&
          !EthiopianPhone.isValid(EthiopianPhone.normalize(pharmacyPhone))) {
        errors['phone'] = tr.t('Enter a valid Ethiopian mobile number');
      }
      if (value('tin').isNotEmpty &&
          !RegExp(r'^\d{10}$').hasMatch(value('tin'))) {
        errors['tin'] = tr.t('The TIN must be 10 digits');
      }
      if (value('licenseNumber').isNotEmpty &&
          value('licenseNumber').length < 3) {
        errors['licenseNumber'] = tr.t('Enter a valid license number');
      }
      if (value('responsiblePharmacist').isNotEmpty &&
          value('responsiblePharmacist').length < 2) {
        errors['responsiblePharmacist'] = tr.t('Enter the pharmacist name');
      }
      if (value('pharmacistLicense').isNotEmpty &&
          value('pharmacistLicense').length < 3) {
        errors['pharmacistLicense'] = tr.t('Enter a valid pharmacist license');
      }
      setState(() {
        _fieldErrors
          ..clear()
          ..addAll(errors);
        _error = null;
        if (errors.isEmpty) _step = 3;
      });
    } else if (_step == 3) {
      if (_name.text.trim().length < 2) {
        setState(() => _ownerNameError = tr.t('Enter your name'));
      } else if (!_acceptedTerms) {
        setState(() => _error = tr.t('Please agree to continue'));
      } else {
        setState(() => _ownerNameError = null);
        final available = await _bio.isAvailable();
        if (!mounted) return;
        setState(() {
          _biometricAvailable = available;
          _useBiometric = available;
          _step = 4;
          _pinStage = 1;
          _pinValue = '';
          _pinFirst = '';
        });
      }
    }
  }

  void _back() {
    setState(() {
      _error = null;
      if (_step == 1) {
        _step = 0;
      } else if (_step == 2) {
        _step = 1;
      } else if (_step == 3) {
        _step = 2;
      } else if (_step == 4) {
        _step = 3;
        _pinStage = 1;
        _pinFirst = '';
        _pinValue = '';
      }
      _clearCode();
    });
  }

  Future<void> _resendCode() async {
    if (_sentAt == null || DateTime.now().difference(_sentAt!).inSeconds < 30) {
      return;
    }
    await _sendCode();
  }

  Future<void> _pinKey(String key) async {
    if (_busy) return;
    if (key == 'delete') {
      setState(() {
        if (_pinValue.isNotEmpty) {
          _pinValue = _pinValue.substring(0, _pinValue.length - 1);
        }
        _error = null;
      });
      return;
    }
    if (_pinValue.length >= 4) return;
    final next = '$_pinValue$key';
    setState(() {
      _pinValue = next;
      _error = null;
    });
    if (next.length == 4) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted || _pinValue.length != 4) return;
      if (_pinStage == 1) {
        if (PinPolicy.isWeak(_pinValue)) {
          setState(() {
            _pinValue = '';
            _error = (ref.read(trProvider).valueOrNull ?? Tr.empty).t(
              'That PIN is too easy to guess. Choose a less predictable PIN.',
            );
          });
          return;
        }
        setState(() {
          _pinFirst = _pinValue;
          _pinValue = '';
          _pinStage = 2;
        });
      } else if (_pinValue != _pinFirst) {
        setState(() {
          _pinValue = '';
          _pinFirst = '';
          _pinStage = 1;
          _error = (ref.read(trProvider).valueOrNull ?? Tr.empty).t(
            'PINs do not match. Try again.',
          );
        });
      } else {
        await _finishRegistration();
      }
    }
  }

  Future<void> _finishRegistration() async {
    final tr = ref.read(trProvider).valueOrNull ?? Tr.empty;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final details = {
        for (final entry in _pharmacy.entries)
          if (entry.key != 'name') entry.key: entry.value.text.trim(),
      };
      final result = await ref
          .read(authRepositoryProvider)
          .completeOwnerRegistration(
            verificationId: _verificationId!,
            name: _name.text.trim(),
            pharmacyName: _pharmacy['name']!.text.trim(),
            pharmacyDetails: details,
            acceptedTerms: _acceptedTerms,
          );
      if (!mounted) return;
      final user = result.valueOrNull;
      if (user == null) {
        setState(() {
          _busy = false;
          _error = failureText(tr, result.failureOrNull!);
          _pinValue = '';
          _pinFirst = '';
          _pinStage = 1;
        });
        return;
      }
      final pinSaved = await ref
          .read(appLockProvider.notifier)
          .setupPin(_pinFirst, userId: user.id);
      if (!pinSaved) {
        throw StateError('PIN rejected by the app lock policy');
      }
      setState(() {
        _busy = false;
        _pendingUser = user;
        _pinValue = '';
        _step = 5;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _pinValue = '';
        _pinFirst = '';
        _pinStage = 1;
        _error = tr.t('Could not save your PIN. Please try again.');
      });
    }
  }

  Future<void> _openApp() async {
    final user = _pendingUser;
    if (user == null) return;
    if (_register) {
      await ref
          .read(appLockProvider.notifier)
          .setBiometricEnabled(_useBiometric, userId: user.id);
    }
    if (mounted) ref.read(sessionProvider.notifier).signedIn(user);
  }

  void _showLegal(bool terms) {
    final tr = ref.tr;
    final title = terms ? tr.t('Terms of service') : tr.t('Privacy policy');
    final paragraphs = terms
        ? const [
            'The pharmacy owner is responsible for the accuracy of stock, prices and prescription records.',
            'PharmaCare helps with records and alerts. It does not replace the pharmacist’s professional judgement or EFDA rules.',
            'Each person signs in with their own account. Shared accounts are not allowed.',
            'Every setting change, export and restore is recorded in the audit log and cannot be removed.',
          ]
        : const [
            'PharmaCare keeps medicine stock, sales, supplier orders, customer credit and prescription records for this pharmacy only.',
            'Only the owner sees everything. Pharmacists see prescription records. Cashiers do not see patient names.',
            'Data stays on this device and in the owner’s backup. It is not sold or shared with advertisers.',
            'The owner chooses how long prescription records are kept and can export data at any time.',
          ];
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final paragraph in paragraphs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(paragraph),
                ),
              Text(
                tr.t(
                  'Draft text for this preview. Have a lawyer review it before release.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr.t('Close')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.tr;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2557E8), Color(0xFF17369F), Color(0xFF0A1A5C)],
            stops: [0, .48, 1],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Column(
                children: [
                  _languagePicker(),
                  _hero(tr),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x52030A32),
                            blurRadius: 40,
                            offset: Offset(0, -12),
                          ),
                        ],
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 260),
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(0, .025),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  ),
                              child: KeyedSubtree(
                                key: ValueKey('$_register-$_step-$_pinStage'),
                                child: _screenBody(tr, colors),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _languagePicker() {
    const languages = [
      (AppLang.en, 'EN'),
      (AppLang.am, 'አማ'),
      (AppLang.om, 'OM'),
      (AppLang.ti, 'ትግ'),
    ];
    final selected = ref.watch(settingsProvider.select((s) => s.language));
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 0),
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (language, label) in languages)
                InkWell(
                  borderRadius: BorderRadius.circular(99),
                  onTap: () => _setLanguage(language),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: selected == language ? Colors.white : null,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: selected == language
                            ? const Color(0xFF17369F)
                            : Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero(Tr tr) {
    final compact = _step >= 2;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      padding: EdgeInsets.fromLTRB(26, compact ? 8 : 12, 26, compact ? 14 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            width: compact ? 46 : 58,
            height: compact ? 46 : 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(compact ? 14 : 18),
              border: Border.all(color: Colors.white.withValues(alpha: .28)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x55050F46),
                  blurRadius: 22,
                  offset: Offset(0, 9),
                ),
              ],
            ),
            child: Icon(
              Icons.local_pharmacy_rounded,
              color: Colors.white,
              size: compact ? 26 : 32,
            ),
          ),
          SizedBox(height: compact ? 10 : 14),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 240),
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 23 : 29,
              height: 1.1,
              letterSpacing: -.5,
              fontWeight: FontWeight.w800,
            ),
            child: const Text('PharmaCare'),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: compact
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      tr.t(
                        'Stock, sales and Rx records that work without internet.',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .86),
                        fontSize: 14,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _screenBody(Tr tr, ColorScheme colors) {
    if (_step == 5) return _doneScreen(tr);
    if (_step == 4) return _pinScreen(tr);
    if (_step == 3) return _ownerScreen(tr);
    if (_step == 2) return _pharmacyScreen(tr);
    if (_step == 1) return _otpScreen(tr);
    return _phoneScreen(tr, colors);
  }

  Widget _phoneScreen(Tr tr, ColorScheme colors) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _modeTabs(tr),
      const SizedBox(height: 20),
      _heading(
        _register ? tr.t('Create your pharmacy account') : tr.t('Welcome back'),
        _register
            ? tr.t('We will send a 6-digit code to verify your phone.')
            : tr.t('We will send a 6-digit code to this number.'),
      ),
      if (_register) _progress(tr, 0),
      _fieldLabel(tr.t('Phone number')),
      _ethiopianPhoneField(tr, colors),
      if (_error != null) _errorText(),
      _primaryButton(tr.t('Send code'), Icons.arrow_forward_rounded, _sendCode),
      if (!_register && !Env.useFirebase) _demoAccounts(tr),
    ],
  );

  Widget _modeTabs(Tr tr) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        _modeTab(tr.t('Sign in'), !_register, () => _setMode(false)),
        _modeTab(tr.t('Register'), _register, () => _setMode(true)),
      ],
    ),
  );

  Widget _modeTab(String label, bool selected, VoidCallback onTap) => Expanded(
    child: Material(
      color: selected
          ? Theme.of(context).colorScheme.surface
          : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: _busy ? null : onTap,
        child: SizedBox(
          height: 42,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _ethiopianPhoneField(Tr tr, ColorScheme colors) => Container(
    height: 58,
    decoration: BoxDecoration(
      color: colors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: colors.outlineVariant, width: 1.4),
    ),
    child: Row(
      children: [
        Container(
          height: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(12),
            ),
            border: Border(right: BorderSide(color: colors.outlineVariant)),
          ),
          child: Row(
            children: [
              _ethiopianFlag(),
              const SizedBox(width: 8),
              const Text('+251', style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        Expanded(
          child: TextField(
            controller: _phone,
            enabled: !_busy,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]')),
            ],
            decoration: InputDecoration(
              hintText: '9XX XXX XXX',
              border: InputBorder.none,
              filled: false,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              hintStyle: TextStyle(color: colors.onSurfaceVariant),
            ),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            onSubmitted: (_) => _sendCode(),
          ),
        ),
      ],
    ),
  );

  Widget _ethiopianFlag() => ClipRRect(
    borderRadius: BorderRadius.circular(3),
    child: SizedBox(
      width: 20,
      height: 14,
      child: Column(
        children: [
          Expanded(child: Container(color: const Color(0xFF0B7A43))),
          Expanded(child: Container(color: const Color(0xFFE8B400))),
          Expanded(child: Container(color: const Color(0xFFC62A37))),
        ],
      ),
    ),
  );

  Widget _demoAccounts(Tr tr) => Padding(
    padding: const EdgeInsets.only(top: 19),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: Theme.of(context).colorScheme.outlineVariant),
        const SizedBox(height: 9),
        Text(
          tr.t('Preview: tap a name to fill in the number.'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children:
              const [
                    ('Selam · Owner', '0911 000 001'),
                    ('Meron · Pharmacist', '0911 000 002'),
                    ('Dawit · Cashier', '0911 000 003'),
                  ]
                  .map(
                    (entry) => ActionChip(
                      label: Text(entry.$1),
                      onPressed: () => setState(() => _phone.text = entry.$2),
                    ),
                  )
                  .toList(),
        ),
        Text(
          tr.f('Demo code: {code}', {'code': Env.demoOtp}),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );

  Widget _otpScreen(Tr tr) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _backButton(tr),
      _heading(
        tr.t('Enter the code'),
        tr.f('Code sent to {p}', {
          'p': EthiopianPhone.international(_normalizedPhone),
        }),
      ),
      if (_register) _progress(tr, 0),
      const SizedBox(height: 4),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(6, (index) => _otpBox(index)),
      ),
      _errorText(center: true),
      if (!Env.useFirebase)
        _previewCallout(
          tr.f('Preview code: {c}. In the real app it arrives by SMS.', {
            'c': Env.demoOtp,
          }),
        ),
      _primaryButton(tr.t('Verify'), Icons.lock_open_rounded, _verifyCode),
      TextButton(
        onPressed: _busy || _secondsUntilResend > 0 ? null : _resendCode,
        child: Text(
          _secondsUntilResend > 0
              ? tr.f('Resend in {s} s', {'s': _secondsUntilResend})
              : tr.t('Resend code'),
        ),
      ),
    ],
  );

  int get _secondsUntilResend {
    final sentAt = _sentAt;
    if (sentAt == null) return 0;
    return (30 - DateTime.now().difference(sentAt).inSeconds).clamp(0, 30);
  }

  Widget _otpBox(int index) => Container(
    width: 47,
    height: 58,
    margin: EdgeInsets.only(left: index == 0 ? 0 : 7),
    decoration: BoxDecoration(
      color: _codeControllers[index].text.isEmpty
          ? Theme.of(context).colorScheme.surface
          : Theme.of(context).colorScheme.primaryContainer,
      border: Border.all(
        color: _error == null
            ? Theme.of(context).colorScheme.outlineVariant
            : Theme.of(context).colorScheme.error,
        width: 1.4,
      ),
      borderRadius: BorderRadius.circular(13),
    ),
    child: TextField(
      controller: _codeControllers[index],
      focusNode: _codeFocus[index],
      enabled: !_busy,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      maxLength: 1,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
      decoration: const InputDecoration(
        counterText: '',
        border: InputBorder.none,
        filled: false,
        contentPadding: EdgeInsets.only(top: 12),
      ),
      onChanged: (value) {
        if (value.isNotEmpty && index < 5) {
          _codeFocus[index + 1].requestFocus();
        }
        if (value.isEmpty && index > 0) {
          _codeFocus[index - 1].requestFocus();
        }
        setState(() => _error = null);
        if (_code.length == 6) {
          Future<void>.delayed(const Duration(milliseconds: 140), _verifyCode);
        }
      },
    ),
  );

  Widget _pharmacyScreen(Tr tr) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _backButton(tr),
      _progress(tr, 1),
      _heading(
        tr.t('Pharmacy details'),
        tr.t(
          'Shown on receipts and reports. You can change them later in Settings.',
        ),
      ),
      _formField(
        'name',
        tr.t('Pharmacy name'),
        icon: Icons.storefront_outlined,
      ),
      _formField('address', tr.t('Address'), icon: Icons.place_outlined),
      _formField(
        'phone',
        tr.t('Pharmacy phone'),
        icon: Icons.phone_outlined,
        keyboard: TextInputType.phone,
      ),
      _formField(
        'tin',
        tr.t('TIN (10 digits)'),
        icon: Icons.numbers_rounded,
        keyboard: TextInputType.number,
        maxLength: 10,
      ),
      _formField(
        'licenseNumber',
        tr.t('License number'),
        icon: Icons.badge_outlined,
      ),
      _formField(
        'responsiblePharmacist',
        tr.t('Responsible pharmacist'),
        icon: Icons.person_outline,
      ),
      _formField(
        'pharmacistLicense',
        tr.t('Pharmacist license'),
        icon: Icons.verified_user_outlined,
      ),
      _errorText(),
      _primaryButton(tr.t('Continue'), Icons.arrow_forward_rounded, _continue),
    ],
  );

  Widget _ownerScreen(Tr tr) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _backButton(tr),
      _progress(tr, 2),
      _heading(
        tr.t('Your details'),
        tr.t(
          'You will be the owner. You choose the role of everyone you add later.',
        ),
      ),
      _textField(
        _name,
        tr.t('Your full name'),
        icon: Icons.person_outline,
        capitalization: TextCapitalization.words,
        errorText: _ownerNameError,
        onChanged: (_) => setState(() => _ownerNameError = null),
      ),
      const SizedBox(height: 14),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: _acceptedTerms,
            onChanged: (value) =>
                setState(() => _acceptedTerms = value ?? false),
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(tr.t('I agree to the')),
                  _legalLink(tr.t('Terms of service'), terms: true),
                  Text(tr.t('and')),
                  _legalLink(tr.t('Privacy policy'), terms: false),
                ],
              ),
            ),
          ),
        ],
      ),
      _errorText(),
      _primaryButton(tr.t('Continue'), Icons.arrow_forward_rounded, _continue),
    ],
  );

  Widget _pinScreen(Tr tr) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _backButton(tr),
      _progress(tr, 3),
      _heading(
        _pinStage == 1 ? tr.t('Create a PIN') : tr.t('Confirm your PIN'),
        tr.t('Choose 4 digits. It opens the app on this phone.'),
      ),
      const SizedBox(height: 5),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          4,
          (index) => AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            width: 15,
            height: 15,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: index < _pinValue.length
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              border: Border.all(
                color: _error == null
                    ? Theme.of(context).colorScheme.outlineVariant
                    : Theme.of(context).colorScheme.error,
                width: 2,
              ),
            ),
          ),
        ),
      ),
      _errorText(center: true),
      _keypad(),
      if (_biometricAvailable)
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          value: _useBiometric,
          onChanged: (value) => setState(() => _useBiometric = value),
          title: Text(tr.t('Use fingerprint or face unlock')),
          secondary: const Icon(Icons.fingerprint_rounded),
        )
      else
        _previewCallout(
          tr.t(
            'Biometric unlock is not available on this device. You can continue with your PIN.',
          ),
        ),
    ],
  );

  Widget _keypad() {
    final numbers = [
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: numbers.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisExtent: 56,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
          ),
          itemBuilder: (context, index) {
            final value = numbers[index];
            if (value.isEmpty) return const SizedBox.shrink();
            return Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _busy
                    ? null
                    : () => _pinKey(value == 'delete' ? 'delete' : value),
                child: Center(
                  child: value == 'delete'
                      ? const Icon(Icons.backspace_outlined)
                      : Text(
                          value,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _doneScreen(Tr tr) {
    final registered = _register;
    final user = _pendingUser;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
            child: Icon(
              Icons.check_rounded,
              size: 50,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 20),
        _heading(
          registered
              ? tr.t('Pharmacy created')
              : tr.f('Welcome back, {name}', {'name': user?.name ?? ''}),
          registered
              ? tr.t(
                  'Next: add your staff in Settings so each person signs in with their own phone.',
                )
              : tr
                    .t('You are signed in as {role}.')
                    .replaceAll('{role}', user?.role.name ?? ''),
          center: true,
        ),
        _primaryButton(
          tr.t('Open PharmaCare'),
          Icons.arrow_forward_rounded,
          _openApp,
        ),
      ],
    );
  }

  Widget _progress(Tr tr, int index) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              tr.t('ACCOUNT SETUP'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 10,
                letterSpacing: 1,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              tr.f('Step {a} of {b}', {'a': index + 1, 'b': 4}),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(
            4,
            (i) => Expanded(
              child: Container(
                height: 5,
                margin: EdgeInsets.only(right: i == 3 ? 0 : 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  gradient: i <= index
                      ? const LinearGradient(
                          colors: [Color(0xFF1D4ED8), Color(0xFF34C98A)],
                        )
                      : null,
                  color: i <= index
                      ? null
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _heading(String title, String subtitle, {bool center = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: center
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Text(
              title,
              textAlign: center ? TextAlign.center : TextAlign.start,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: center ? TextAlign.center : TextAlign.start,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ),
      );

  Widget _backButton(Tr tr) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextButton.icon(
        onPressed: _busy ? null : _back,
        style: TextButton.styleFrom(
          backgroundColor: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest,
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        ),
        icon: const Icon(Icons.arrow_back_rounded, size: 17),
        label: Text(tr.t('Back')),
      ),
    ),
  );

  Widget _fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(left: 2, bottom: 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _formField(
    String key,
    String label, {
    required IconData icon,
    TextInputType keyboard = TextInputType.text,
    int? maxLength,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: _textField(
      _pharmacy[key]!,
      label,
      icon: icon,
      keyboard: keyboard,
      capitalization: TextCapitalization.words,
      maxLength: maxLength,
      dense: true,
      errorText: _fieldErrors[key],
      onChanged: (_) {
        if (_fieldErrors.containsKey(key)) {
          setState(() => _fieldErrors.remove(key));
        }
      },
    ),
  );

  Widget _textField(
    TextEditingController controller,
    String label, {
    required IconData icon,
    TextInputType keyboard = TextInputType.text,
    TextCapitalization capitalization = TextCapitalization.none,
    int? maxLength,
    bool dense = false,
    String? errorText,
    ValueChanged<String>? onChanged,
  }) => TextField(
    controller: controller,
    enabled: !_busy,
    keyboardType: keyboard,
    textCapitalization: capitalization,
    maxLength: maxLength,
    onChanged: onChanged,
    inputFormatters: keyboard == TextInputType.number
        ? [FilteringTextInputFormatter.digitsOnly]
        : null,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      counterText: '',
      filled: true,
      fillColor: Theme.of(context).colorScheme.surface,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: dense ? 14 : 17,
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      errorText: errorText,
    ),
  );

  Widget _legalLink(String text, {required bool terms}) => TextButton(
    onPressed: () => _showLegal(terms),
    style: TextButton.styleFrom(
      minimumSize: Size.zero,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    child: Text(text),
  );

  Widget _errorText({bool center = false}) => AnimatedSize(
    duration: const Duration(milliseconds: 160),
    child: SizedBox(
      width: double.infinity,
      child: Padding(
        padding: EdgeInsets.only(top: _error == null ? 4 : 8),
        child: Text(
          _error ?? ' ',
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    ),
  );

  Widget _previewCallout(String text) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 16,
          color: Theme.of(context).colorScheme.onTertiaryContainer,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              color: Theme.of(context).colorScheme.onTertiaryContainer,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _primaryButton(
    String label,
    IconData icon,
    Future<void> Function() onPressed,
  ) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Opacity(
      opacity: _busy ? .7 : 1,
      child: Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFF1D4ED8), Color(0xFF315FE7)],
          ),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.primary
                  .withValues(alpha: .28),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _busy ? null : onPressed,
            borderRadius: BorderRadius.circular(14),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_busy)
                    const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  else
                    Icon(icon, color: Colors.white),
                  const SizedBox(width: 9),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
