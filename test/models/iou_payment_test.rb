require "test_helper"

class IouPaymentTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:depository)
  end

  test "money owed to you arrives as an income transaction" do
    iou = ious(:client_fee)

    payment = assert_difference -> { @account.entries.count }, 1 do
      iou.record_payment(amount: 500, date: Date.current, account: @account)
    end

    assert payment.persisted?
    entry = payment.entry
    assert_equal(-500, entry.amount)
    assert_equal "income", entry.classification
    assert_equal "Ravi: Website design", entry.name
    assert_equal "USD", entry.currency
    assert_equal categories(:income), entry.transaction.category
    assert_equal Date.current, entry.date
  end

  test "money you owe leaves as an expense transaction" do
    iou = ious(:dinner)

    payment = iou.record_payment(amount: 40, date: Date.current, account: @account)

    assert payment.persisted?
    assert_equal 40, payment.entry.amount
    assert_equal "expense", payment.entry.classification
    assert_nil payment.entry.transaction.category
    assert iou.settled?
  end

  test "recording a payment syncs the account" do
    iou = ious(:client_fee)
    Account.any_instance.expects(:sync_later).once

    iou.record_payment(amount: 100, date: Date.current, account: @account)
  end

  test "can't pay more than what's left" do
    iou = ious(:dinner)

    payment = assert_no_difference -> { Entry.count } do
      iou.record_payment(amount: 41, date: Date.current, account: @account)
    end

    assert_not payment.persisted?
    assert payment.errors.added?(:amount, :more_than_remaining)
  end

  test "needs an account in the family" do
    iou = ious(:dinner)

    payment = iou.record_payment(amount: 10, date: Date.current, account: nil)

    assert_not payment.persisted?
    assert payment.errors.added?(:account, :blank)

    other = Account.new(family: families(:empty), name: "Elsewhere", currency: "USD")
    payment = iou.record_payment(amount: 10, date: Date.current, account: other)

    assert_not payment.persisted?
    assert payment.errors.added?(:account, :invalid)
  end

  test "deleting a payment deletes its transaction and reopens the IOU" do
    iou = ious(:dinner)
    payment = iou.record_payment(amount: 40, date: Date.current, account: @account)
    entry_id = payment.entry_id
    assert iou.settled?

    payment.destroy!

    assert_not Entry.exists?(entry_id)
    assert_equal 40, iou.reload.remaining_amount
    assert_not iou.settled?
  end

  test "deleting the transaction elsewhere removes the payment" do
    iou = ious(:dinner)
    payment = iou.record_payment(amount: 15, date: Date.current, account: @account)

    payment.entry.destroy!

    assert_not IouPayment.exists?(payment.id)
    assert_equal 40, iou.reload.remaining_amount
  end

  test "deleting an IOU keeps the transactions its payments made" do
    iou = ious(:dinner)
    payment = iou.record_payment(amount: 15, date: Date.current, account: @account)

    iou.destroy!

    assert Entry.exists?(payment.entry_id)
    assert_not IouPayment.exists?(payment.id)
  end
end
