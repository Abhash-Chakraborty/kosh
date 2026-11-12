require "test_helper"

class Iou::AccountOutstandingTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @account = accounts(:depository)
    # Already on the account: Ravi owes $1,500 (client_fee).
  end

  test "sums what is still to leave the account and what is still to arrive" do
    ious(:dinner).update!(account: @account)

    outstanding = Iou::AccountOutstanding.new(@account)

    assert_equal [ ious(:dinner), ious(:client_fee) ].sort_by(&:id), outstanding.ious.sort_by(&:id)
    assert_equal Money.new(40, "USD"), outstanding.you_owe
    assert_equal Money.new(1500, "USD"), outstanding.owed_to_you
    assert_equal Money.new(@account.balance + 1500 - 40, "USD"), outstanding.settled_balance
  end

  test "counts only what is left of a partly paid IOU" do
    ious(:client_fee).record_payment(amount: 500, date: Date.current, account: @account)

    assert_equal Money.new(1000, "USD"), Iou::AccountOutstanding.new(@account).owed_to_you
  end

  test "leaves out settled IOUs and IOUs on other accounts" do
    ious(:client_fee).record_payment(amount: 1500, date: Date.current, account: @account)

    outstanding = Iou::AccountOutstanding.new(@account)

    assert_not outstanding.any?
    assert_empty outstanding.ious
  end

  test "gives no settled balance for a debt account" do
    card = accounts(:credit_card)
    ious(:dinner).update!(account: card)

    outstanding = Iou::AccountOutstanding.new(card)

    assert outstanding.any?
    assert_nil outstanding.settled_balance
  end
end
