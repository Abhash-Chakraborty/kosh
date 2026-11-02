# Turns one PaymentMessage into what it means for the books:
#
# 1. Read it, with patterns first (PaymentMessage::Parser). Texts the patterns
#    can't place wait for PaymentMessage::AiReader in a job.
# 2. Merge it if the same payment already came in: the bank's text and the
#    app's notification share a 12-digit UPI reference; without one, the same
#    amount and direction from a different sender within a few minutes.
# 3. Find the account from the hints accounts remember (last digits, sender,
#    app). Unknown account: ask which one, and create nothing yet.
# 4. Create the entry, run the family's rules on it, and ask for a category
#    when no rule set one. Answers can become rules (PaymentMessage::Answer),
#    so the same payee isn't asked about twice.
class PaymentMessage::Processor
  MERGE_WINDOW = 15.minutes
  ENTRY_SOURCE = "payment_messages".freeze

  attr_reader :message

  def initialize(message)
    @message = message
  end

  def process
    return message unless message.status == "pending"

    result = PaymentMessage::Parser.parse(body: message.body, sender: message.sender, source: message.source, received_at: message.received_at)

    case result.outcome
    when :ignored
      message.update!(status: "ignored", reason: result.reason.to_s)
    when :unreadable
      message.update!(upi_ref: result.upi_ref, account_hint: result.account_hint)
      if PaymentMessage::AiReader.available?
        PaymentMessageJob.perform_later(message)
      else
        message.update!(status: "question", question: "unreadable")
      end
    when :payment
      apply(result)
    end

    message
  end

  # Applies a reading, from the patterns or from the AI.
  def apply(result)
    with_family_lock do
      message.assign_attributes(
        amount: result.amount,
        currency: result.currency || "INR",
        direction: result.direction.to_s,
        counterparty: result.counterparty,
        upi_ref: result.upi_ref || message.upi_ref,
        account_hint: result.account_hint || message.account_hint,
        occurred_on: result.occurred_on || message.received_at.to_date,
        kind: (result.kind || :spending).to_s,
        parser: result.parser,
        question: nil
      )

      account = PaymentMessage::AccountMatcher.new(message).account

      if (twin = find_twin)
        message.update!(status: "merged", merged_into: twin, account: twin.account || account, entry: twin.entry)
        # The twin may be waiting to hear which account it was; this message knows.
        PaymentMessage::Processor.new(twin).enter!(account) if account && twin.question == "account" && twin.answered_at.nil?
      elsif account
        enter!(account)
      else
        message.update!(status: "question", question: "account")
      end
    end

    message
  end

  # Creates the entry on the given account, then asks for a category if no
  # rule found one.
  def enter!(account)
    entry = account.entries.create!(
      name: message.entry_name,
      date: message.occurred_on || message.received_at.to_date,
      amount: message.debit? ? message.amount : -message.amount,
      currency: message.currency.presence || account.currency,
      source: ENTRY_SOURCE,
      external_id: message.id,
      entryable: Transaction.new(kind: message.kind == "investment" ? "investment_contribution" : "standard")
    )

    apply_rules(entry.transaction)
    entry.sync_account_later

    needs_category = entry.transaction.reload.category_id.nil? && message.kind != "investment"
    message.update!(
      account: account,
      entry: entry,
      status: needs_category ? "question" : "entered",
      question: needs_category ? "category" : nil,
      answered_at: nil
    )
    PaymentMessage.where(merged_into_id: message.id).update_all(entry_id: entry.id, account_id: account.id)
    entry
  end

  private
    def family
      message.family
    end

    def find_twin
      candidates = family.payment_messages
        .where(status: %w[entered question], merged_into_id: nil)
        .where.not(id: message.id)

      if message.upi_ref.present?
        twin = candidates.find_by(upi_ref: message.upi_ref)
        return twin if twin
      end

      nearby = candidates
        .where(amount: message.amount, direction: message.direction)
        .where(received_at: (message.received_at - MERGE_WINDOW)..(message.received_at + MERGE_WINDOW))
        .where.not(sender: message.sender)
      # Two different UPI references are two different payments.
      nearby = nearby.where(upi_ref: nil) if message.upi_ref.present?

      nearby.min_by { |m| (m.received_at - message.received_at).abs }
    end

    def apply_rules(transaction)
      family.rules.where(active: true, resource_type: "transaction").ordered.each do |rule|
        rule.apply(scope: rule.matching_scope(only_id: transaction.id))
      rescue StandardError => e
        Rails.logger.warn("PaymentMessage rule #{rule.id} failed: #{e.class}: #{e.message}")
      end
    end

    # Two batches about the same payment can arrive together (a text and a
    # notification a second apart); one family's messages go through in turn.
    def with_family_lock
      PaymentMessage.transaction do
        Family.lock.find(family.id)
        yield
      end
    end
end
