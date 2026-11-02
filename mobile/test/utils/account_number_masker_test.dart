import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/utils/account_number_masker.dart';

void main() {
  group('AccountNumberMasker.mask', () {
    test('masks account, card and phone numbers to XX + last 4', () {
      expect(AccountNumberMasker.mask('A/c 50100123456789 debited'),
          'A/c XX6789 debited');
      expect(AccountNumberMasker.mask('Card 0000000000004321 used'),
          'Card XX4321 used');
      expect(AccountNumberMasker.mask('from 9876543210'), 'from XX3210');
      expect(AccountNumberMasker.mask('ref 123456'), 'ref XX3456');
      expect(AccountNumberMasker.mask('Ref 4123456789012'), 'Ref XX9012');
    });

    test('keeps 12-digit UPI reference numbers', () {
      expect(AccountNumberMasker.mask('UPI Ref 412345678901'),
          'UPI Ref 412345678901');
      expect(AccountNumberMasker.mask('UPI:412345678901.'),
          'UPI:412345678901.');
    });

    test('leaves short runs, long runs and already masked numbers alone', () {
      expect(AccountNumberMasker.mask('OTP-free 12345'), 'OTP-free 12345');
      expect(AccountNumberMasker.mask('a/c XX1234'), 'a/c XX1234');
      expect(AccountNumberMasker.mask('id 12345678901234567890'),
          'id 12345678901234567890');
    });

    test('does not mask amounts', () {
      expect(AccountNumberMasker.mask('Rs.150000.00 debited'),
          'Rs.150000.00 debited');
      expect(AccountNumberMasker.mask('INR 2500000 credited'),
          'INR 2500000 credited');
      expect(AccountNumberMasker.mask('₹ 750000 sent'), '₹ 750000 sent');
      expect(AccountNumberMasker.mask('Rs1500000 paid'), 'Rs1500000 paid');
      expect(AccountNumberMasker.mask('Avl bal 123456.78'),
          'Avl bal 123456.78');
    });

    test('masks every number in a full bank text', () {
      expect(
        AccountNumberMasker.mask(
          'Rs.500.00 debited from a/c 50100123456789 to 9876543210@ybl. '
          'UPI Ref 412345678901. Avl bal Rs 250000.50',
        ),
        'Rs.500.00 debited from a/c XX6789 to XX3210@ybl. '
        'UPI Ref 412345678901. Avl bal Rs 250000.50',
      );
    });
  });
}
