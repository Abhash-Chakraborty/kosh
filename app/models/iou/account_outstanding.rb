# Open IOUs that settle through one account, for the account's page: what is
# still to leave it, what is still to arrive, and where its balance lands once
# both have happened. Amounts are in the account's currency; an IOU with no
# exchange rate is left out of the sums, as on the Owed page.
class Iou::AccountOutstanding
  attr_reader :account

  def initialize(account)
    @account = account
  end

  def ious
    @ious ||= account.family.ious.outstanding
      .where(account_id: account.id)
      .includes(:payments, :project, :category)
      .by_due_date
      .to_a
  end

  def any?
    ious.any?
  end

  def you_owe
    total(ious.select(&:i_owe?))
  end

  def owed_to_you
    total(ious.select(&:owed_to_me?))
  end

  # The balance after every open IOU is paid. Only for an account that holds
  # money: on a loan or a card the same payments move the balance the other
  # way, and the figure would mislead.
  def settled_balance
    return unless account.asset?

    Money.new(account.balance, account.currency) + owed_to_you - you_owe
  end

  private
    def total(list)
      sum, _skipped = Iou.remaining_total(list, currency: account.currency)
      sum
    end
end
