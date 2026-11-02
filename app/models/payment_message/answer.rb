# Applies an answer to one of a message's questions.
#
# - account: posts the payment to the chosen account. With remember on, the
#   account keeps the message's last digits and sender, so the next text from
#   there goes straight in.
# - category: files the entry. With remember on, it becomes a rule for the
#   payee, so the same payee isn't asked about twice.
# - unreadable: the amount, direction and payee typed in by hand; then it goes
#   through like any other payment (and may ask for the account next).
# - dismiss (any question): not a payment, or leave it as it is.
class PaymentMessage::Answer
  include ActiveModel::Model

  attr_accessor :message, :account_id, :category_id, :amount, :direction, :counterparty, :remember, :dismiss

  validate :answer_matches_question

  def save
    return false unless valid?

    if ActiveModel::Type::Boolean.new.cast(dismiss)
      dismiss!
    else
      case message.question
      when "account" then answer_account
      when "category" then answer_category
      when "unreadable" then answer_unreadable
      end
    end
    true
  rescue ActiveRecord::RecordNotFound
    errors.add(:base, :invalid)
    false
  end

  private
    def remember?
      ActiveModel::Type::Boolean.new.cast(remember.nil? ? true : remember)
    end

    def family
      message.family
    end

    def answer_account
      account = PaymentMessage::AccountMatcher.new(message).choices.find(account_id)
      PaymentMessage::AccountMatcher.remember!(account, message) if remember?
      PaymentMessage::Processor.new(message).enter!(account)
    end

    def answer_category
      category = family.categories.find(category_id)
      transaction = message.entry.transaction
      transaction.update!(category: category)
      transaction.lock_attr!(:category_id)

      if remember? && message.counterparty.present?
        Rule.create_from_grouping(family, message.entry.name, category, transaction_type: message.debit? ? "expense" : "income")
      end

      message.update!(status: "entered", answered_at: Time.current)
    end

    def answer_unreadable
      result = PaymentMessage::Parser::Result.new(
        outcome: :payment,
        reason: nil,
        amount: BigDecimal(amount.to_s.delete(",")),
        currency: "INR",
        direction: direction.to_sym,
        counterparty: counterparty.to_s.strip.presence,
        upi_ref: message.upi_ref,
        account_hint: message.account_hint,
        occurred_on: message.received_at.to_date,
        kind: :spending,
        parser: "typed"
      )
      message.update!(status: "pending")
      PaymentMessage::Processor.new(message).apply(result)
    end

    def dismiss!
      if message.question == "category"
        message.update!(status: "entered", answered_at: Time.current)
      else
        message.update!(status: "ignored", reason: "dismissed", answered_at: Time.current)
      end
    end

    def answer_matches_question
      return errors.add(:base, :answered) unless message&.status == "question" && message.answered_at.nil?
      return if ActiveModel::Type::Boolean.new.cast(dismiss)

      case message.question
      when "account" then errors.add(:account_id, :blank) if account_id.blank?
      when "category" then errors.add(:category_id, :blank) if category_id.blank?
      when "unreadable"
        errors.add(:amount, :invalid) unless amount.to_s.delete(",").match?(/\A\d+(\.\d{1,2})?\z/) && amount.to_s.delete(",").to_d.positive?
        errors.add(:direction, :inclusion) unless %w[debit credit].include?(direction.to_s)
      end
    end
end
