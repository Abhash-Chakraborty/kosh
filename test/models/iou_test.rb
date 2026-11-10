require "test_helper"

class IouTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @iou = ious(:client_fee)
    @account = accounts(:depository)
  end

  test "needs a person, a description and a positive amount" do
    iou = @family.ious.new(direction: "owed_to_me", amount: 0)

    assert_not iou.valid?
    assert iou.errors.added?(:person, :blank)
    assert iou.errors.added?(:description, :blank)
    assert iou.errors.of_kind?(:amount, :greater_than)
  end

  test "rejects an unknown direction" do
    @iou.direction = "sideways"

    assert_not @iou.valid?
    assert iou_error?(:direction)
  end

  test "defaults to the family currency" do
    iou = @family.ious.create!(direction: "i_owe", person: "Sam", description: "Taxi", amount: 12)

    assert_equal @family.primary_currency_code, iou.currency
  end

  test "rejects an account or category from another family" do
    other_family = families(:empty)
    @iou.account = Account.new(family: other_family, name: "Elsewhere", currency: "USD")
    @iou.category = Category.new(family: other_family, name: "Elsewhere")

    assert_not @iou.valid?
    assert @iou.errors.added?(:account, :invalid)
    assert @iou.errors.added?(:category, :invalid)
  end

  test "remaining is the amount less what has been paid" do
    assert_equal 1500, @iou.remaining_amount
    assert_not @iou.settled?

    @iou.record_payment(amount: 500, date: Date.current, account: @account)

    assert_equal 500, @iou.paid_amount
    assert_equal 1000, @iou.remaining_amount
    assert @iou.partly_paid?
    assert_not @iou.settled?
    assert_includes @family.ious.outstanding, @iou

    @iou.record_payment(amount: 1000, date: Date.current, account: @account)

    assert_equal 0, @iou.remaining_amount
    assert @iou.settled?
    assert_includes @family.ious.settled, @iou
    assert_not_includes @family.ious.outstanding, @iou
  end

  test "the amount can't drop below what has been paid" do
    @iou.record_payment(amount: 800, date: Date.current, account: @account)

    @iou.amount = 700

    assert_not @iou.valid?
    assert @iou.errors.added?(:amount, :less_than_paid)
  end

  test "overdue only when the due date has passed and money is still owed" do
    @iou.due_on = Date.current - 1

    assert @iou.overdue?

    @iou.due_on = Date.current
    assert_not @iou.overdue?

    @iou.update!(due_on: Date.current - 1)
    @iou.record_payment(amount: 1500, date: Date.current, account: @account)
    assert_not @iou.overdue?
  end

  test "totals convert to one currency and count what can't be converted" do
    eur = @family.ious.create!(direction: "owed_to_me", person: "Lena", description: "Hotel", amount: 100, currency: "EUR")
    ExchangeRate.create!(from_currency: "EUR", to_currency: "USD", date: Date.current, rate: 1.1)

    total, skipped = Iou.remaining_total([ @iou, eur ], currency: "USD")

    assert_equal Money.new(1610, "USD"), total
    assert_equal 0, skipped
  end

  test "an amount with no exchange rate is left out of the total and counted" do
    eur = @family.ious.create!(direction: "owed_to_me", person: "Lena", description: "Hotel", amount: 100, currency: "EUR")
    ExchangeRate.stubs(:find_or_fetch_rate).returns(nil)

    total, skipped = Iou.remaining_total([ @iou, eur ], currency: "USD")

    assert_equal Money.new(1500, "USD"), total
    assert_equal 1, skipped
  end

  private
    def iou_error?(attribute)
      @iou.errors[attribute].any?
    end
end
