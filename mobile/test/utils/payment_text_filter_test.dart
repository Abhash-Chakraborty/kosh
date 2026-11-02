import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/utils/payment_text_filter.dart';

void main() {
  group('PaymentTextFilter.isTransactionalSender', () {
    test('accepts DLT bank headers with or without a category suffix', () {
      expect(PaymentTextFilter.isTransactionalSender('AD-HDFCBK-S'), isTrue);
      expect(PaymentTextFilter.isTransactionalSender('JM-ICICIT-T'), isTrue);
      expect(PaymentTextFilter.isTransactionalSender('VM-SBIUPI'), isTrue);
      expect(PaymentTextFilter.isTransactionalSender('BZ-AXISBK-G'), isTrue);
      expect(PaymentTextFilter.isTransactionalSender('ad-hdfcbk'), isTrue);
    });

    test('rejects promotional headers', () {
      expect(PaymentTextFilter.isTransactionalSender('AD-HDFCBK-P'), isFalse);
    });

    test('rejects personal numbers and other shapes', () {
      expect(PaymentTextFilter.isTransactionalSender('+919876543210'), isFalse);
      expect(PaymentTextFilter.isTransactionalSender('9876543210'), isFalse);
      expect(PaymentTextFilter.isTransactionalSender('HDFCBK'), isFalse);
      expect(PaymentTextFilter.isTransactionalSender('AD-HDFC'), isFalse);
      expect(PaymentTextFilter.isTransactionalSender('AD-HDFCBK-X'), isFalse);
      expect(PaymentTextFilter.isTransactionalSender(''), isFalse);
    });
  });

  group('PaymentTextFilter money and action words', () {
    test('finds rupee amounts in the usual spellings', () {
      expect(PaymentTextFilter.hasMoneyWords('₹40 paid'), isTrue);
      expect(PaymentTextFilter.hasMoneyWords('Rs.500.00 debited'), isTrue);
      expect(PaymentTextFilter.hasMoneyWords('Rs 500 debited'), isTrue);
      expect(PaymentTextFilter.hasMoneyWords('Rs500 debited'), isTrue);
      expect(PaymentTextFilter.hasMoneyWords('INR 1,200 credited'), isTrue);
      expect(PaymentTextFilter.hasMoneyWords('INR500 credited'), isTrue);
    });

    test('does not mistake words ending in rs for money', () {
      expect(PaymentTextFilter.hasMoneyWords('Spent 2 hours with others'),
          isFalse);
    });

    test('needs a word that says money moved', () {
      expect(PaymentTextFilter.hasActionWords('debited from a/c'), isTrue);
      expect(PaymentTextFilter.hasActionWords('Refunded to card'), isTrue);
      expect(PaymentTextFilter.hasActionWords('UPI txn successful'), isTrue);
      expect(PaymentTextFilter.hasActionWords('Get cashback on recharge'),
          isFalse);
      // "credit card" alone is not "credited".
      expect(PaymentTextFilter.hasActionWords('Your credit card bill'),
          isFalse);
    });
  });

  group('PaymentTextFilter.checkSms', () {
    test('keeps a bank debit text', () {
      expect(
        PaymentTextFilter.checkSms(
          sender: 'AD-HDFCBK-S',
          body: 'Rs.500.00 debited from A/c XX1234 on 03-11-26 to VPA '
              'sharma@okaxis. UPI Ref 412345678901.',
        ),
        PaymentTextDecision.keep,
      );
    });

    test('drops OTPs even when they mention an amount', () {
      expect(
        PaymentTextFilter.checkSms(
          sender: 'VM-HDFCBK',
          body: '123456 is your OTP for a txn of Rs 500 at Amazon',
        ),
        PaymentTextDecision.skipOtp,
      );
      expect(
        PaymentTextFilter.checkSms(
          sender: 'VM-ICICIB',
          body: 'Your One Time Password is 4321. Rs 20 paid.',
        ),
        PaymentTextDecision.skipOtp,
      );
      expect(
        PaymentTextFilter.checkSms(
          sender: 'VM-ICICIB',
          body: 'Verification code 99881 for INR 10 sent',
        ),
        PaymentTextDecision.skipOtp,
      );
    });

    test('drops promotional and personal senders before reading the text', () {
      const body = 'Rs 500 credited to your account';
      expect(
        PaymentTextFilter.checkSms(sender: 'AD-HDFCBK-P', body: body),
        PaymentTextDecision.skipSender,
      );
      expect(
        PaymentTextFilter.checkSms(sender: '+919876543210', body: body),
        PaymentTextDecision.skipSender,
      );
    });

    test('drops texts without an amount or an action', () {
      expect(
        PaymentTextFilter.checkSms(
          sender: 'AD-HDFCBK-S',
          body: 'Get Rs 500 cashback on your next recharge',
        ),
        PaymentTextDecision.skipNotPayment,
      );
      expect(
        PaymentTextFilter.checkSms(
          sender: 'AD-HDFCBK-S',
          body: 'Your account statement has been debited to your email',
        ),
        PaymentTextDecision.skipNotPayment,
      );
    });
  });

  group('PaymentTextFilter notifications', () {
    test('keeps payment-app notifications with an amount', () {
      expect(
        PaymentTextFilter.checkNotification('₹40 paid to Sharma Tea Stall'),
        PaymentTextDecision.keep,
      );
    });

    test('drops notifications without an amount and OTPs', () {
      expect(
        PaymentTextFilter.checkNotification('You have a new reward'),
        PaymentTextDecision.skipNotPayment,
      );
      expect(
        PaymentTextFilter.checkNotification('Use OTP 4455 to pay ₹100'),
        PaymentTextDecision.skipOtp,
      );
    });

    test('joins title and text with a newline, skipping empty parts', () {
      expect(
        PaymentTextFilter.joinNotification('Google Pay', ' ₹40 paid '),
        'Google Pay\n₹40 paid',
      );
      expect(PaymentTextFilter.joinNotification(null, 'only text'),
          'only text');
      expect(PaymentTextFilter.joinNotification('  ', 'text'), 'text');
    });
  });
}
