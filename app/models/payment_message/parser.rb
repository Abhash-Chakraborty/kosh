# Reads one Indian bank text or payment-app notification without any AI.
#
# Banks word their alerts differently, but the parts are the same: an amount in
# rupees, a verb that says which way the money went, often the last digits of
# the account or card, the other side (a UPI handle, a shop, a person) and, for
# UPI, a 12-digit reference. The patterns below look for those parts rather
# than for one bank's sentence, so a bank that isn't listed anywhere still
# reads. Anything they can't read is left to PaymentMessage::AiReader.
#
# Pure Ruby on purpose: no database, so it is cheap to test with any wording.
class PaymentMessage::Parser
  Result = Data.define(
    :outcome,       # :payment, :ignored or :unreadable
    :reason,        # why it was ignored: otp, promotion, reminder, declined, balance, not_money
    :amount,        # BigDecimal, always positive
    :currency,
    :direction,     # :debit (money out) or :credit (money in)
    :counterparty,  # who was paid or who paid, as written
    :upi_ref,       # 12-digit UPI/IMPS reference, when the text has one
    :account_hint,  # last 3-4 digits of the account or card
    :occurred_on,   # Date
    :kind,          # :spending or :investment
    :parser         # which pattern read it
  ) do
    def payment? = outcome == :payment
    def ignored? = outcome == :ignored
  end

  AMOUNT = /(?:₹|\brs\.?|\binr)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i
  # SBI and a few others write "debited by 40.0" with no currency sign.
  BARE_AMOUNT = /\b(?:debited|credited)\s+(?:by|for|with)\s+([0-9][0-9,]*(?:\.[0-9]{1,2})?)\b/i

  DEBIT_WORDS = /\b(debited|spent|paid|sent|withdrawn|withdrawal|purchase[ds]?|transferred|deducted|charged|dr\b|txn of|payment of)/i
  CREDIT_WORDS = /\b(credited|received|deposited|refund(?:ed)?|reversed|reversal|cashback|cr\b|added to)/i

  OTP = /\b(otp|one[\s-]?time[\s-]?pass(?:word|code)|verification code|passcode|cvv)\b/i
  DECLINED = /\b(declined|failed|unsuccessful|not processed|could not be processed|rejected)\b/i
  # Mandates, due dates and offers talk about money that hasn't moved yet.
  REMINDER = /\b(will be (?:debited|deducted|auto[\s-]?debited|charged)|is due|due on|due date|payment due|scheduled for|pre[\s-]?approved|loan of upto|apply now)/i
  BALANCE_ONLY = /\b(available balance|avl\.? bal|a\/c bal|balance is|closing balance)\b/i

  UPI_REF = /(?:upi|ref(?:erence)?|rrn|utr|txn\s*id|transaction\s*id)[^0-9a-z]{0,6}(?:no\.?|number|id)?[^0-9]{0,4}([0-9]{12})\b/i
  ANY_TWELVE_DIGITS = /(?<![0-9])([0-9]{12})(?![0-9])/
  ACCOUNT_HINT = /\b(?:a\/?c|acct|account|card|ac)\b\.?\s*(?:no\.?\s*)?(?:ending\s*(?:with|in)?\s*)?[x*•.\s]*([0-9]{3,4})\b/i
  ACCOUNT_HINT_X = /\b[x*•]{1,}([0-9]{3,4})\b/i

  # Notification phrasings from payment apps, checked before the bank patterns.
  APP_PATTERNS = [
    [ :app_paid_to,      /\b(?:you\s+)?paid\s+(?:₹|rs\.?\s*)([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s+to\s+(.+?)(?=\s+(?:using|via|from|on)\b|\.(?:\s|$)|$)/i, :debit ],
    [ :app_amount_paid,  /(?:₹|rs\.?\s*)([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s+(?:paid|sent)\s+to\s+(.+?)(?=\s+(?:using|via|from|on)\b|\.(?:\s|$)|$)/i, :debit ],
    [ :app_received,     /(?:received|got)\s+(?:₹|rs\.?\s*)([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s+from\s+(.+?)(?=\s+(?:on|in|via)\b|\.(?:\s|$)|$)/i, :credit ],
    [ :app_paid_you,     /(?:\A|\.\s)([^.]+?)\s+(?:paid|sent)\s+you\s+(?:₹|rs\.?\s*)([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i, :credit_reversed ],
    [ :app_amount_recv,  /(?:₹|rs\.?\s*)([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s+received\s+from\s+(.+?)(?=\s+(?:on|in|via)\b|\.(?:\s|$)|$)/i, :credit ]
  ].freeze

  INVESTMENT_NAME = /\b(?:sip|investment|order|lumpsum)\b.*?\bin\s+(.+?)(?=\s+(?:has|is|was|for|of)\b|\.(?:\s|$)|$)/i
  INVESTMENT = /\b(sip|mutual fund|lumpsum|folio|nav\b|units allotted|order (?:placed|executed)|bought \d|shares? of)\b/i

  COUNTERPARTY_PATTERNS = [
    /\bto\s+vpa\s+([^\s,;]+)/i,
    /\bby\s+vpa\s+([^\s,;]+)/i,
    /\bfrom\s+vpa\s+([^\s,;]+)/i,
    /;\s*([^;.]+?)\s+credited\b/i,                        # ICICI: "...debited for Rs 649; SWIGGY credited."
    /\btrf\s+to\s+(.+?)(?=\s+ref|\s+on\b|[.;]|$)/i,           # SBI: "trf to SHARMA TEA Refno ..."
    /\btransfer(?:red)?\s+(?:from|by)\s+(.+?)(?=\s+ref|\s+on\b|[.;]|$)/i, # SBI credit: "transfer from RAMESH K"
    /\bat\s+(.+?)(?=\s+on\s|\s+via\s|\s+ref|\s+txn|\s+using|\.\s|[;(]|$)/i,     # cards: "spent ... at AMAZON on ..."
    /\bto\s+(?!(?:your|a\/?c|acct|account|card)\b)(.+?)(?=\s+on\s|\s+via\s|\s+ref|\s+upi|\s+from\b|\.\s|[;(]|$)/i,
    /\bfrom\s+(?!(?:your|a\/?c|acct|account|card|hdfc|icici|sbi|axis|kotak)\b)(.+?)(?=\s+on\s|\s+via\s|\s+ref|\s+upi|\.\s|[;(]|$)/i,
    /\bby\s+(?!(?:vpa|upi|your)\b)(.+?)(?=\s+on\s|\s+ref|\s+upi|\.\s|[;(]|$)/i
  ].freeze

  MONTHS = %w[jan feb mar apr may jun jul aug sep oct nov dec].freeze

  def self.parse(...) = new(...).parse

  def initialize(body:, sender: nil, source: "sms", received_at: Time.current)
    # A notification's title and text arrive on separate lines; a line break
    # reads as the end of a sentence.
    @body = body.to_s.unicode_normalize(:nfkc).strip.gsub(/\s*\n+\s*/, ". ").gsub(/\s+/, " ")
    @sender = sender.to_s
    @source = source.to_s
    @received_at = received_at || Time.current
  end

  def parse
    return ignored(:otp) if body.match?(OTP)
    return ignored(:promotion) if promotional_sender?
    return ignored(:declined) if body.match?(DECLINED) && !body.match?(/\b(refund|reversed|reversal)\b/i)
    return ignored(:reminder) if body.match?(REMINDER)

    app_result || bank_result || fallback
  end

  private
    attr_reader :body, :sender, :source, :received_at

    def app_result
      APP_PATTERNS.each do |name, pattern, direction|
        match = body.match(pattern)
        next unless match

        amount, counterparty = direction == :credit_reversed ? [ match[2], match[1] ] : [ match[1], match[2] ]
        return payment(
          amount: amount,
          direction: direction == :debit ? :debit : :credit,
          counterparty: clean_counterparty(counterparty),
          parser: "app:#{name}"
        )
      end
      nil
    end

    def bank_result
      amount = body[AMOUNT, 1] || body[BARE_AMOUNT, 1]
      direction = direction_from_words
      return nil unless amount && direction

      payment(amount: amount, direction: direction, counterparty: counterparty_from_patterns, parser: "bank:generic")
    end

    def fallback
      looks_like_money = body.match?(AMOUNT) || body.match?(BARE_AMOUNT)
      return ignored(:balance) if looks_like_money && body.match?(BALANCE_ONLY) && direction_from_words.nil?
      return ignored(:not_money) unless looks_like_money

      Result.new(outcome: :unreadable, reason: nil, amount: nil, currency: "INR", direction: nil, counterparty: nil,
        upi_ref: upi_ref, account_hint: account_hint, occurred_on: nil, kind: nil, parser: nil)
    end

    # The first direction word wins: "debited for Rs 649; SWIGGY credited" is a
    # debit, "credited to a/c XX4821 by VPA ..." a credit.
    def direction_from_words
      debit = body =~ DEBIT_WORDS
      credit = body =~ CREDIT_WORDS
      return nil if debit.nil? && credit.nil?
      return :debit if credit.nil?
      return :credit if debit.nil?

      debit < credit ? :debit : :credit
    end

    def payment(amount:, direction:, counterparty:, parser:)
      value = BigDecimal(amount.delete(","))
      return ignored(:not_money) unless value.positive?

      kind = body.match?(INVESTMENT) || sender.match?(/groww/i) ? :investment : :spending
      counterparty ||= clean_counterparty(body[INVESTMENT_NAME, 1]) if kind == :investment

      Result.new(
        outcome: :payment,
        reason: nil,
        amount: value,
        currency: "INR",
        direction: direction,
        counterparty: counterparty,
        upi_ref: upi_ref,
        account_hint: account_hint,
        occurred_on: occurred_on,
        kind: kind,
        parser: parser
      )
    end

    def ignored(reason)
      Result.new(outcome: :ignored, reason: reason, amount: nil, currency: nil, direction: nil, counterparty: nil,
        upi_ref: nil, account_hint: nil, occurred_on: nil, kind: nil, parser: nil)
    end

    # DLT headers end in -P for promotions and -S/-T/-G for service,
    # transactional and government texts. App notifications have no header.
    def promotional_sender?
      source == "sms" && sender.match?(/-P\z/i)
    end

    def upi_ref
      body[UPI_REF, 1] || body[ANY_TWELVE_DIGITS, 1]
    end

    def account_hint
      body[ACCOUNT_HINT, 1] || body[ACCOUNT_HINT_X, 1]
    end

    def counterparty_from_patterns
      COUNTERPARTY_PATTERNS.each do |pattern|
        value = clean_counterparty(body[pattern, 1])
        return value if value
      end
      nil
    end

    def clean_counterparty(value)
      return nil if value.blank?

      cleaned = value
        .sub(/\s+(?:on|dt|dated)\s+\d.*\z/i, "")
        .sub(/\s*\((?:upi|ref).*\z/i, "")
        .sub(/\s+(?:ref|upi|rrn|utr|txn|avl|bal)\b.*\z/i, "")
        .gsub(/[*]+/, "")
        .strip
        .sub(/[\s.,;:\-]+\z/, "")
      return nil if cleaned.blank? || cleaned.length < 2
      return nil if cleaned.match?(/\A[x*•\d\s]+\z/i) # an account number, not a payee
      return nil if cleaned.match?(/\A(?:your|a\/?c|acct|account|card|bank|you)\b/i)

      cleaned.truncate(80, omission: "")
    end

    def occurred_on
      date = written_date
      today = received_at.to_date
      return today unless date
      # A date far from when the text arrived is a misread (or a due date).
      (date - today).abs <= 10 ? date : today
    end

    def written_date
      if (m = body.match(/\b(\d{4})-(\d{2})-(\d{2})\b/))
        safe_date(m[1].to_i, m[2].to_i, m[3].to_i)
      elsif (m = body.match(/\b(\d{1,2})[-\/.](\d{1,2})[-\/.](\d{2,4})\b/))
        safe_date(full_year(m[3]), m[2].to_i, m[1].to_i)
      elsif (m = body.match(/\b(\d{1,2})[-\s]?(#{MONTHS.join("|")})[a-z]*[-\s,]*(\d{2,4})\b/i))
        safe_date(full_year(m[3]), MONTHS.index(m[2].downcase) + 1, m[1].to_i)
      end
    end

    def full_year(value)
      year = value.to_i
      year < 100 ? 2000 + year : year
    end

    def safe_date(year, month, day)
      Date.new(year, month, day)
    rescue Date::Error
      nil
    end
end
