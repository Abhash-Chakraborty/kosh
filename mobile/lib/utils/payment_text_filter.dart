/// Decides which bank texts and payment-app notifications are worth sending
/// to the server for auto-entry. Everything here runs on the phone; a text
/// that fails these checks never leaves it.
library;

/// Why a message was kept or dropped.
enum PaymentTextDecision {
  /// Looks like a payment: send it.
  keep,

  /// Not a transactional bank sender (personal number, promotional header).
  skipSender,

  /// A one-time password or verification code. Never sent, never stored.
  skipOtp,

  /// No amount, or no word that says money moved.
  skipNotPayment,
}

class PaymentTextFilter {
  PaymentTextFilter._();

  /// DLT sender headers used by Indian banks: a 2-letter operator/circle
  /// prefix, a dash, a 6-character entity id and an optional category suffix
  /// (S = service, T = transactional, G = government, P = promotional).
  /// e.g. `AD-HDFCBK-S`, `JM-ICICIT-T`, `VM-SBIUPI`.
  static final RegExp _dltSender =
      RegExp(r'^[A-Z]{2}-[A-Z0-9]{6}(-[STGP])?$');

  static final RegExp _money = RegExp(
    r'(₹|\b(rs|inr)\b|\b(rs|inr)\.?\s*\d)',
    caseSensitive: false,
  );

  static final RegExp _action = RegExp(
    r'\b(debited|credited|spent|paid|sent|received|withdrawn|txn|'
    r'transactions?|purchased?|refund(ed)?)\b',
    caseSensitive: false,
  );

  static final RegExp _otp = RegExp(
    r'\b(otp|one[\s-]?time[\s-]?password|verification[\s-]?code|passcode)\b',
    caseSensitive: false,
  );

  /// True for DLT headers that are not promotional (`-P`).
  static bool isTransactionalSender(String sender) {
    final normalized = sender.trim().toUpperCase();
    if (!_dltSender.hasMatch(normalized)) return false;
    return !normalized.endsWith('-P');
  }

  static bool hasMoneyWords(String text) => _money.hasMatch(text);

  static bool hasActionWords(String text) => _action.hasMatch(text);

  static bool isOtp(String text) => _otp.hasMatch(text);

  /// Checks a bank text. The OTP check runs before anything else so a code
  /// is dropped even when it mentions an amount.
  static PaymentTextDecision checkSms({
    required String sender,
    required String body,
  }) {
    if (!isTransactionalSender(sender)) return PaymentTextDecision.skipSender;
    if (isOtp(body)) return PaymentTextDecision.skipOtp;
    if (!hasMoneyWords(body) || !hasActionWords(body)) {
      return PaymentTextDecision.skipNotPayment;
    }
    return PaymentTextDecision.keep;
  }

  /// Checks a payment-app notification. The package allowlist is applied
  /// before this; here only the text matters. Payment apps word their
  /// notifications loosely ("₹40 to Sharma Tea Stall"), so an amount is enough.
  static PaymentTextDecision checkNotification(String text) {
    if (isOtp(text)) return PaymentTextDecision.skipOtp;
    if (!hasMoneyWords(text)) return PaymentTextDecision.skipNotPayment;
    return PaymentTextDecision.keep;
  }

  /// Joins a notification's title and text the way the server expects.
  static String joinNotification(String? title, String? text) {
    return [title, text]
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join('\n');
  }
}
