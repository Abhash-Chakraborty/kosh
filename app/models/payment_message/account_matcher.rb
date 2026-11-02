# Finds the account a message is about from what accounts remember
# (accounts.message_hints): the last digits a bank writes ("4821"), a bank's
# sender code ("hdfcbk") or an app ("slice", "google pay").
#
# Digits win over the sender, since one bank can hold several accounts. Digits
# no account knows yet mean a new account, so nothing is guessed: the message
# asks, and the answer adds the hints.
class PaymentMessage::AccountMatcher
  def initialize(message)
    @message = message
  end

  def account
    digits = message.account_hint.presence
    return single(candidates.select { |a| knows_digits?(a, digits) }) if digits

    sender = message.sender_hint
    return nil if sender.blank?

    single(candidates.select { |a| a.message_hints.include?(sender) })
  end

  # Accounts the message's sender may post to.
  def choices
    scope = message.family.accounts.visible
    scope = scope.writable_by(message.user) if message.user
    scope.alphabetically
  end

  def self.remember!(account, message)
    hints = [ message.account_hint, message.sender_hint ].compact_blank.map(&:downcase)
    account.update!(message_hints: (account.message_hints + hints).uniq)
  end

  private
    attr_reader :message

    def candidates
      @candidates ||= choices.where.not(message_hints: []).to_a
    end

    # ICICI writes three digits ("XX821"), most banks four.
    def knows_digits?(account, digits)
      account.message_hints.any? { |hint| hint.match?(/\A\d+\z/) && (hint.end_with?(digits) || digits.end_with?(hint)) }
    end

    def single(accounts)
      accounts.one? ? accounts.first : nil
    end
end
