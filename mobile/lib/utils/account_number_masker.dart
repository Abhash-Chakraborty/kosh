/// Masks account, card and phone numbers in a payment text before it leaves
/// the phone.
///
/// Runs of 6–11 or 13–19 digits become `XX` plus their last four digits.
/// Runs of exactly 12 digits are kept: UPI reference numbers are 12 digits and
/// the server uses them to merge the bank text and the app notification for
/// the same payment. Amounts are left alone (a run right after ₹/Rs/INR, or
/// one followed by decimals), as are runs that are already short.
class AccountNumberMasker {
  AccountNumberMasker._();

  static final RegExp _digits = RegExp(r'\d+');
  static final RegExp _moneyPrefix =
      RegExp(r'(₹|\b(rs|inr))\.?\s*$', caseSensitive: false);
  static final RegExp _decimalTail = RegExp(r'^\.\d');

  static bool _shouldMask(int length) =>
      (length >= 6 && length <= 11) || (length >= 13 && length <= 19);

  static String mask(String text) {
    return text.replaceAllMapped(_digits, (match) {
      final run = match.group(0)!;
      if (!_shouldMask(run.length)) return run;

      final before = text.substring(0, match.start);
      final after = text.substring(match.end);
      // Part of an amount: "Rs.250000", "INR 1500000.00", "₹ 750000".
      if (_moneyPrefix.hasMatch(before)) return run;
      if (_decimalTail.hasMatch(after)) return run;
      // The fraction of a decimal number ("12.345678").
      if (before.endsWith('.') &&
          before.length > 1 &&
          _isDigit(before.codeUnitAt(before.length - 2))) {
        return run;
      }

      return 'XX${run.substring(run.length - 4)}';
    });
  }

  static bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;
}
