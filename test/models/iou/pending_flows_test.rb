require "test_helper"

class Iou::PendingFlowsTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @this_month = Period.custom(start_date: Date.current.beginning_of_month, end_date: Date.current)
  end

  test "an open IOU on each side becomes a pending node on that side" do
    flows = pending(@this_month)

    assert_equal [ "owed_to_me", "i_owe" ], flows.map { |flow| flow[:direction] }
    assert_equal [ "Ravi", "Maya" ], flows.map { |flow| flow[:name] }
    assert_equal [ 1500.0, 40.0 ], flows.map { |flow| flow[:value] }
    assert_equal I18n.t("ious.pending_flows.owed_to_me.note"), flows.first[:note]
    assert_equal I18n.t("ious.pending_flows.i_owe.person", person: "Maya"), flows.last[:description]
  end

  test "nothing is drawn when nothing is open" do
    @family.ious.find_each { |iou| iou.record_payment(amount: iou.remaining_amount, date: Date.current, account: accounts(:depository)) }

    assert_equal [], pending(@this_month)
  end

  test "nothing is drawn for a period that doesn't include today" do
    last_month = Period.custom(start_date: 2.months.ago.to_date, end_date: 1.month.ago.to_date)

    assert_equal [], pending(last_month)
  end

  test "what is left after a part payment is what shows" do
    ious(:client_fee).record_payment(amount: 500, date: Date.current, account: accounts(:depository))

    assert_equal 1000.0, pending(@this_month).find { |flow| flow[:name] == "Ravi" }[:value]
  end

  test "one person's IOUs share a node, and many people share one" do
    @family.ious.create!(direction: "owed_to_me", person: " ravi ", description: "Logo", amount: 100)
    assert_equal 1600.0, pending(@this_month).find { |flow| flow[:name] == "Ravi" }[:value]

    %w[Asha Ben Chen].each { |person| @family.ious.create!(direction: "owed_to_me", person: person, description: "Tickets", amount: 10) }
    owed = pending(@this_month).select { |flow| flow[:direction] == "owed_to_me" }

    assert_equal 1, owed.size
    assert_equal I18n.t("ious.pending_flows.owed_to_me.everyone"), owed.first[:name]
    assert_equal 1630.0, owed.first[:value]
    assert_equal I18n.t("ious.pending_flows.owed_to_me.people", count: 4), owed.first[:description]
  end

  test "the cash flow graph's totals are the same with and without open IOUs" do
    account = accounts(:depository)
    create_transaction(account: account, amount: -1000, date: Date.current, category: categories(:income))
    create_transaction(account: account, amount: 200, date: Date.current, category: categories(:food_and_drink))
    statement = IncomeStatement.new(@family)
    with_ious = IncomeStatement::Sankey.new(statement, period: @this_month).as_json

    assert pending(@this_month).any?
    Iou.where(family: @family).delete_all
    without_ious = IncomeStatement::Sankey.new(IncomeStatement.new(@family), period: @this_month).as_json

    %i[income spending invested net_savings nodes links].each do |key|
      assert_equal without_ious[key], with_ious[key], "#{key} changed"
    end
  end

  private
    def pending(period)
      Iou::PendingFlows.new(@family.reload, period: period).as_json
    end
end
