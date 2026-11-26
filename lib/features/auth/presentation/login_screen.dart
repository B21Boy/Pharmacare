import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/ui_extensions.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/error/failure_text.dart';
import '../../../data/providers.dart';
import '../domain/ethiopian_phone.dart';
import 'session_controller.dart';

/// Phone number -> SMS code. The server decides who you are and what role you
/// have; the app never trusts a role the phone claims for itself.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String? _verificationId;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final tr = (ref.read(trProvider).valueOrNull ?? Tr.empty);
    final n = EthiopianPhone.normalize(_phone.text);
    if (!EthiopianPhone.isValid(n)) {
      setState(() => _error = tr.t('Enter a valid Ethiopian mobile number, for example 0911 000 001'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await ref.read(authRepositoryProvider).sendCode(n);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _verificationId = r.valueOrNull;
      final f = r.failureOrNull;
      if (f != null) _error = failureText(tr, f);
    });
  }

  Future<void> _verify() async {
    final tr = (ref.read(trProvider).valueOrNull ?? Tr.empty);
    final id = _verificationId;
    if (id == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await ref.read(authRepositoryProvider).verifyCode(verificationId: id, code: _code.text.trim());
    if (!mounted) return;
    final user = r.valueOrNull;
    if (user != null) {
      ref.read(sessionProvider.notifier).signedIn(user);
      return; // the router moves on by itself
    }
    setState(() {
      _busy = false;
      _error = failureText(tr, r.failureOrNull!);
      _code.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.tr;
    final codeStep = _verificationId != null;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.local_pharmacy_outlined, size: 56, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 12),
                  Text('PharmaCare', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 28),
                  if (!codeStep) ...[
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      autofocus: true,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]'))],
                      decoration: InputDecoration(labelText: tr.t('Mobile number'), hintText: '0911 000 001', prefixText: '+251 '),
                      onSubmitted: (_) => _send(),
                    ),
                  ] else ...[
                    TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 24, letterSpacing: 8),
                      decoration: InputDecoration(labelText: tr.t('SMS code'), counterText: ''),
                      onSubmitted: (_) => _verify(),
                    ),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : (codeStep ? _verify : _send),
                    child: _busy
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(codeStep ? tr.t('Sign in') : tr.t('Send code')),
                  ),
                  if (codeStep)
                    TextButton(
                      onPressed: _busy ? null : () => setState(() {
                        _verificationId = null;
                        _error = null;
                      }),
                      child: Text(tr.t('Use a different number')),
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
