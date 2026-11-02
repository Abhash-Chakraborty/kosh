# Cuts account, card and phone numbers down to their last four digits. The
# phone masks before sending; the server does it again so nothing longer is
# stored even if an older app version didn't.
#
# Two kinds of long number stay whole: runs of exactly 12 digits, the length of
# a UPI reference (RRN), which is how a bank text and an app notification
# about the same payment are matched; and amounts, which follow a currency
# sign or carry paise ("Rs.150000.00").
module PaymentMessage::Masker
  module_function

  LONG_NUMBER = /(?<![0-9])[0-9]{6,19}(?![0-9])/
  CURRENCY_BEFORE = /(?:₹|rs\.?|inr)\s*\z/i

  def mask(text)
    text.to_s.gsub(LONG_NUMBER) do |digits|
      match = Regexp.last_match
      amount = match.pre_match.match?(CURRENCY_BEFORE) || match.post_match.match?(/\A\.[0-9]{1,2}(?![0-9])/)

      digits.length == 12 || amount ? digits : "XX#{digits[-4..]}"
    end
  end
end
