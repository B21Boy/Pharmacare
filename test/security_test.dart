import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacare/core/i18n/tr.dart';
import 'package:pharmacare/core/security/pii_redactor.dart';
import 'package:pharmacare/core/security/pin_hasher.dart';
import 'package:pharmacare/features/auth/domain/ethiopian_phone.dart';
import 'package:pharmacare/features/auth/domain/role.dart';
import 'package:pharmacare/features/lock/domain/pin_policy.dart';
import 'package:pharmacare/features/lock/presentation/app_lock_controller.dart';

void main() {
  group('PinHasher', () {
    const hasher = PinHasher(iterations: 1000); // low only to keep the test fast

    test('verifies the right PIN and rejects a wrong one', () async {
      final stored = await hasher.hash('4821');
      expect(await hasher.verify('4821', stored), isTrue);
      expect(await hasher.verify('4822', stored), isFalse);
    });

    test('same PIN gives a different salt and hash every time', () async {
      final a = await hasher.hash('4821');
      final b = await hasher.hash('4821');
      expect(a.salt, isNot(b.salt));
      expect(a.hash, isNot(b.hash));
    });

    test('storage format round-trips and rejects garbage', () async {
      final stored = await hasher.hash('4821');
      final back = PinHash.decode(stored.encode())!;
      expect(await hasher.verify('4821', back), isTrue);
      expect(PinHash.decode(null), isNull);
      expect(PinHash.decode('nope'), isNull);
      expect(PinHash.decode(r'x$a$b'), isNull);
    });
  });

  group('PinPolicy', () {
    test('format', () {
      expect(PinPolicy.isFormatOk('4821'), isTrue);
      expect(PinPolicy.isFormatOk('482193'), isTrue);
      expect(PinPolicy.isFormatOk('123'), isFalse);
      expect(PinPolicy.isFormatOk('1234567'), isFalse);
      expect(PinPolicy.isFormatOk('48a1'), isFalse);
    });

    test('weak PINs are refused', () {
      for (final p in ['0000', '1111', '1234', '4321', '123456', '9876']) {
        expect(PinPolicy.isWeak(p), isTrue, reason: p);
      }
      expect(PinPolicy.isWeak('4821'), isFalse);
    });
  });

  group('lockout schedule', () {
    test('none for the first 4 mistakes, then 30 s and doubling, capped at 15 min', () {
      expect(AppLockController.lockoutFor(4), Duration.zero);
      expect(AppLockController.lockoutFor(5), const Duration(seconds: 30));
      expect(AppLockController.lockoutFor(6), const Duration(seconds: 60));
      expect(AppLockController.lockoutFor(7), const Duration(seconds: 120));
      expect(AppLockController.lockoutFor(9), const Duration(seconds: 480));
      expect(AppLockController.lockoutFor(12), const Duration(minutes: 15));
    });
  });

  group('PiiRedactor', () {
    test('removes phone numbers, emails and long numbers', () {
      expect(PiiRedactor.scrub('call 0911223344 now'), 'call [phone] now');
      expect(PiiRedactor.scrub('+251 911 22 33 44 asked'), '[phone] asked');
      expect(PiiRedactor.scrub('mail a.b@c.com'), 'mail [email]');
      expect(PiiRedactor.scrub('rx 12345678 ok'), 'rx [number] ok');
    });

    test('leaves ordinary questions alone', () {
      expect(PiiRedactor.scrub('How much Paracetamol 500mg is left?'), 'How much Paracetamol 500mg is left?');
    });
  });

  group('EthiopianPhone', () {
    test('normalises every common way of typing a number', () {
      for (final s in ['0911 22 33 44', '+251 911 223344', '251911223344', '911223344']) {
        expect(EthiopianPhone.normalize(s), '911223344', reason: s);
      }
      expect(EthiopianPhone.isValid('911223344'), isTrue);
      expect(EthiopianPhone.isValid('711223344'), isTrue);
      expect(EthiopianPhone.isValid('511223344'), isFalse);
      expect(EthiopianPhone.isValid('91122334'), isFalse);
    });
  });

  group('Permissions', () {
    test('owner sees everything, cashier sees nothing extra', () {
      for (final p in Permission.values) {
        expect(Permissions.can(Role.owner, p), isTrue);
        expect(Permissions.can(Role.cashier, p), isFalse);
      }
      expect(Permissions.can(Role.pharmacist, Permission.cost), isTrue);
      expect(Permissions.can(Role.pharmacist, Permission.profit), isFalse);
    });

    test('route guard', () {
      expect(Permissions.canOpen(Role.cashier, '/finance'), isFalse);
      expect(Permissions.canOpen(Role.cashier, '/sales'), isTrue);
      expect(Permissions.canOpen(Role.pharmacist, '/audit'), isTrue);
      expect(Permissions.canOpen(Role.pharmacist, '/finance'), isFalse);
    });
  });

  group('Tr', () {
    const tr = Tr({'a': 'X', 'Hi {name}': 'Selam {name}'}, {'a': 'Y', 'b': 'Z'});

    test('falls back: active language, English, then the key itself', () {
      expect(tr.t('a'), 'X');
      expect(tr.t('b'), 'Z');
      expect(tr.t('unknown'), 'unknown');
    });

    test('fills placeholders and keeps unknown ones', () {
      expect(tr.f('Hi {name}', {'name': 'Sam'}), 'Selam Sam');
      expect(tr.f('Hi {name}'), 'Selam {name}');
    });

    test('singular and plural', () {
      expect(tr.n('{n} item', '{n} items', 1), '1 item');
      expect(tr.n('{n} item', '{n} items', 3), '3 items');
    });
  });
}
