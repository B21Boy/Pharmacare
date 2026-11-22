import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/roles.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/id_gen.dart';
import '../../core/widgets/app_icons.dart';
import '../../data/models/staff_user.dart';
import '../../state/app_state.dart';

/// Sign in / register flow (authPaint / auScreen in the HTML, lines 3427-3490).
/// Steps implemented: phone -> code -> done (or denied). Registration asks for
/// the pharmacy and owner name in one step.
/// TODO(port): PIN step and fingerprint (au_pin, auBio), full pharmacy details
/// (TIN, license), terms/privacy sheets (legalSheet), cloud directory
/// (CLOUD.dir), suspended accounts, pending-sync guard.
/// TODO(backend): replace the simulated code with Firebase Phone Auth.
enum _Step { phone, otp, setup, done, denied }

/// Digits only, without country code or leading 0 (normPhone).
String normPhone(String p) {
  var d = p.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('251')) d = d.substring(3);
  if (d.startsWith('0')) d = d.substring(1);
  return d;
}

bool phoneOk(String p) {
  final d = normPhone(p);
  return d.length == 9 && (d.startsWith('9') || d.startsWith('7'));
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  _Step _step = _Step.phone;
  bool _register = false;
  final _phone = TextEditingController();
  final _pharmacy = TextEditingController();
  final _owner = TextEditingController();
  final List<TextEditingController> _otp =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(6, (_) => FocusNode());
  String _code = '';
  String _error = '';
  bool _busy = false;
  int _sentAt = 0;
  Timer? _tick;
  StaffUser? _user;

  // Demo staff directory. Replace by the real backend lookup.
  static final List<StaffUser> _demo = [
    StaffUser(
        id: 'u1',
        name: 'Selam Alemu',
        phone: '911000001',
        role: UserRole.owner),
    StaffUser(
        id: 'u2',
        name: 'Meron Tadesse',
        phone: '911000002',
        role: UserRole.pharmacist),
    StaffUser(
        id: 'u3',
        name: 'Abel Girma',
        phone: '911000003',
        role: UserRole.cashier),
  ];

  @override
  void dispose() {
    _tick?.cancel();
    _phone.dispose();
    _pharmacy.dispose();
    _owner.dispose();
    for (final c in _otp) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  int get _secondsLeft =>
      max(0, 30 - ((DateTime.now().millisecondsSinceEpoch - _sentAt) ~/ 1000));

  void _send() {
    if (!phoneOk(_phone.text)) {
      setState(() => _error = t('Enter a valid Ethiopian mobile number'));
      return;
    }
    final d = normPhone(_phone.text);
    final known = _demo.where((u) => u.phone == d).firstOrNull;
    if (!_register && known == null) {
      setState(() {
        _step = _Step.denied;
        _error = '';
      });
      return;
    }
    if (_register && known != null) {
      setState(() => _error = t('This number already has an account'));
      return;
    }
    _user = known;
    _code = (100000 + Random().nextInt(900000)).toString();
    _sentAt = DateTime.now().millisecondsSinceEpoch;
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    for (final c in _otp) {
      c.clear();
    }
    setState(() {
      _error = '';
      _step = _Step.otp;
    });
  }

  Future<void> _verify() async {
    final entered = _otp.map((c) => c.text).join();
    if (entered.length < 6) {
      setState(() => _error = t('Enter all 6 digits'));
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    if (entered != _code) {
      setState(() {
        _busy = false;
        _error = t('Wrong code. Try again.');
      });
      return;
    }
    setState(() {
      _busy = false;
      _step = _register ? _Step.setup : _Step.done;
    });
  }

  void _finishSetup() {
    if (_pharmacy.text.trim().isEmpty || _owner.text.trim().isEmpty) {
      setState(() => _error = t('Fill in both names'));
      return;
    }
    final s = context.read<AppState>();
    s.profile.name = _pharmacy.text.trim();
    _user = StaffUser(
        id: uid(),
        name: _owner.text.trim(),
        phone: normPhone(_phone.text),
        role: UserRole.owner);
    setState(() {
      _error = '';
      _step = _Step.done;
    });
  }

  void _enter() => context.read<AppState>().signIn(_user!);

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = context.c;
    final compact =
        _step != _Step.phone && _step != _Step.done && _step != _Step.denied;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-.4, -1),
            end: Alignment(.4, 1),
            colors: [Color(0xFF2557E8), Color(0xFF17369F), Color(0xFF0A1A5C)],
            stops: [0, .48, 1],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(children: [
            // language pills
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                      color: const Color(0x24FFFFFF),
                      borderRadius: BorderRadius.circular(99)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final l in AppLang.values)
                      GestureDetector(
                        onTap: () => s.setLang(l),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 30),
                          padding: const EdgeInsets.symmetric(horizontal: 11),
                          decoration: BoxDecoration(
                              color: s.lang == l ? Colors.white : null,
                              borderRadius: BorderRadius.circular(99)),
                          alignment: Alignment.center,
                          child: Text(
                            switch (l) {
                              AppLang.en => 'EN',
                              AppLang.am => 'አማ',
                              AppLang.om => 'OM',
                              AppLang.ti => 'ትግ'
                            },
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: s.lang == l
                                  ? const Color(0xFF17369F)
                                  : Colors.white.withAlpha(210),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
            // hero
            AnimatedPadding(
              duration: const Duration(milliseconds: 250),
              padding: EdgeInsets.fromLTRB(26, 10, 26, compact ? 14 : 24),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: compact ? 46 : 58,
                        height: compact ? 46 : 58,
                        decoration: BoxDecoration(
                          color: const Color(0x29FFFFFF),
                          borderRadius:
                              BorderRadius.circular(compact ? 14 : 18),
                          border: Border.all(color: const Color(0x47FFFFFF)),
                        ),
                        alignment: Alignment.center,
                        child: const AppIcon('pill',
                            size: 28, color: Colors.white),
                      ),
                      SizedBox(height: compact ? 10 : 14),
                      Text('PharmaCare',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: compact ? 23 : 29,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.5,
                              height: 1.1)),
                      if (!compact)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: SizedBox(
                            width: 290,
                            child: Text(t('Run your pharmacy from your phone.'),
                                style: const TextStyle(
                                    color: Color(0xDBFFFFFF), fontSize: 14)),
                          ),
                        ),
                    ]),
              ),
            ),
            // card
            Expanded(
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                    20, 22, 20, 22 + MediaQuery.of(context).padding.bottom),
                decoration: BoxDecoration(
                  color: c.bg,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x520A1A5C),
                        blurRadius: 40,
                        offset: Offset(0, -14))
                  ],
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: SingleChildScrollView(child: _stepBody(context)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _stepBody(BuildContext context) {
    final c = context.c;
    final errorText = Container(
      constraints: const BoxConstraints(minHeight: 20),
      margin: const EdgeInsets.fromLTRB(2, 8, 2, 0),
      child: Text(_error,
          style: TextStyle(
              color: c.red, fontSize: 13, fontWeight: FontWeight.w500)),
    );

    Widget primary(String label, VoidCallback? onTap, {bool busy = false}) =>
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: GestureDetector(
            onTap: busy ? null : onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 54),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(colors: [c.pr, c.pr2]),
                boxShadow: [
                  BoxShadow(
                      color: c.pr.withAlpha(82),
                      blurRadius: 22,
                      offset: const Offset(0, 10))
                ],
              ),
              alignment: Alignment.center,
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 3, color: Colors.white))
                  : Text(label,
                      style: TextStyle(
                          color: c.onpr,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600)),
            ),
          ),
        );

    Widget backBtn(VoidCallback onTap) => Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.fromLTRB(8, 7, 12, 7),
              decoration: BoxDecoration(
                  color: c.card2, borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AppIcon('back', size: 16, color: c.tx),
                const SizedBox(width: 6),
                Text(t('Back'),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        );

    Widget heading(String h, String p) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(h,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.3)),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 16),
            child: Text(p, style: TextStyle(color: c.mu)),
          ),
        ]);

    switch (_step) {
      case _Step.phone:
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                    color: c.card2, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  for (final reg in [false, true])
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _register = reg;
                          _error = '';
                        }),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 42),
                          decoration: BoxDecoration(
                            color: _register == reg ? c.card : null,
                            borderRadius: BorderRadius.circular(11),
                            boxShadow: _register == reg
                                ? const [
                                    BoxShadow(
                                        color: Color(0x1F0E1A33),
                                        blurRadius: 8,
                                        offset: Offset(0, 2))
                                  ]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Text(reg ? t('Register') : t('Sign in'),
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _register == reg ? c.pr : c.mu)),
                        ),
                      ),
                    ),
                ]),
              ),
              heading(
                _register
                    ? t('Create your pharmacy account')
                    : t('Welcome back'),
                _register
                    ? t('We will send a 6-digit code to verify your phone.')
                    : t('We will send a 6-digit code to this number.'),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 6),
                child: Text(t('Phone number'),
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: c.mu)),
              ),
              Container(
                decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.ln2, width: 1.5)),
                clipBehavior: Clip.antiAlias,
                child: IntrinsicHeight(
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                          color: c.card2,
                          border: Border(right: BorderSide(color: c.ln))),
                      child: Row(children: [
                        // Ethiopian flag swatch (green / yellow / red)
                        SizedBox(
                          width: 20,
                          height: 14,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: const Column(children: [
                              Expanded(
                                  child: ColoredBox(
                                      color: Color(0xFF0B7A43),
                                      child: SizedBox.expand())),
                              Expanded(
                                  child: ColoredBox(
                                      color: Color(0xFFE8B400),
                                      child: SizedBox.expand())),
                              Expanded(
                                  child: ColoredBox(
                                      color: Color(0xFFC62A37),
                                      child: SizedBox.expand())),
                            ]),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('+251',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]'))
                        ],
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: .6),
                        decoration: const InputDecoration(
                          hintText: '9XX XXX XXX',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 15),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
              errorText,
              primary(t('Send code'), _send),
              if (!_register) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: c.card2, borderRadius: BorderRadius.circular(12)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('Preview: tap a name to fill in the number.'),
                            style: TextStyle(fontSize: 12.5, color: c.mu)),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final u in _demo)
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _phone.text = u.phone),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 11, vertical: 7),
                                decoration: BoxDecoration(
                                    color: c.card,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: c.ln2)),
                                child: Text('${u.name} · ${t(u.role.label)}',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500)),
                              ),
                            ),
                        ]),
                      ]),
                ),
              ],
            ]);

      case _Step.otp:
        final left = _secondsLeft;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              backBtn(() => setState(() {
                    _step = _Step.phone;
                    _error = '';
                  })),
              heading(
                  t('Enter the code'),
                  t('Code sent to {p}')
                      .replaceAll('{p}', '+251 ${normPhone(_phone.text)}')),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < 6; i++)
                  Container(
                    width: 46,
                    height: 58,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    child: TextField(
                      controller: _otp[i],
                      focusNode: _nodes[i],
                      autofocus: i == 0,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 1,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        counterText: '',
                        contentPadding: EdgeInsets.zero,
                        fillColor: _otp[i].text.isNotEmpty ? c.prc : c.card,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: c.ln2, width: 1.5)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                                color: _otp[i].text.isNotEmpty ? c.pr : c.ln2,
                                width: 1.5)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: c.pr, width: 1.5)),
                      ),
                      onChanged: (v) {
                        if (v.isNotEmpty && i < 5) _nodes[i + 1].requestFocus();
                        if (v.isEmpty && i > 0) _nodes[i - 1].requestFocus();
                        setState(() {});
                      },
                    ),
                  ),
              ]),
              errorText,
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  AppIcon('alert', size: 14, color: c.mu),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        t('Preview code: {c}. In the real app it arrives by SMS.')
                            .replaceAll('{c}', _code),
                        style: TextStyle(fontSize: 12.5, color: c.mu)),
                  ),
                ]),
              ),
              primary(t('Verify'), _verify, busy: _busy),
              TextButton(
                onPressed: left > 0 ? null : _send,
                child: Text(left > 0
                    ? t('Resend in {s} s').replaceAll('{s}', '$left')
                    : t('Resend code')),
              ),
            ]);

      case _Step.setup:
        Widget field(String label, TextEditingController ctl) => Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextField(
                controller: ctl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: label),
              ),
            );
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              backBtn(() => setState(() => _step = _Step.phone)),
              heading(t('Pharmacy details'),
                  t('You will be the owner. You choose the role of everyone you add later.')),
              field('Pharmacy name', _pharmacy),
              field(t('Your full name'), _owner),
              errorText,
              primary(t('Continue'), _finishSetup),
            ]);

      case _Step.done:
        final u = _user;
        return Column(children: [
          const SizedBox(height: 10),
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(shape: BoxShape.circle, color: c.grnc),
            alignment: Alignment.center,
            child: AppIcon('check', size: 46, color: c.grn),
          ),
          const SizedBox(height: 16),
          Text(
              _register
                  ? t('Pharmacy created')
                  : '${t('Welcome back')}, ${u?.name ?? ''}',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 16),
            child: Text(
              _register
                  ? t('Next: add your staff in Settings so each person signs in with their own phone.')
                  : t(u?.role.label ?? ''),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.mu),
            ),
          ),
          primary(t('Open PharmaCare'), _enter),
        ]);

      case _Step.denied:
        return Column(children: [
          const SizedBox(height: 10),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(shape: BoxShape.circle, color: c.ambc),
            alignment: Alignment.center,
            child: AppIcon('alert', size: 34, color: c.amb),
          ),
          const SizedBox(height: 16),
          Text(t('This number is not added to any pharmacy'),
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 16),
            child: Text(
                t('Ask the owner to add you in Settings, or register a new pharmacy.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.mu)),
          ),
          primary(t('Back'), () => setState(() => _step = _Step.phone)),
          TextButton(
            onPressed: () => setState(() {
              _register = true;
              _step = _Step.phone;
            }),
            child: Text(t('Register a new pharmacy')),
          ),
        ]);
    }
  }
}
