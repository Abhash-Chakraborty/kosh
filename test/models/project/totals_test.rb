require "test_helper"

class Project::TotalsTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @project = projects(:lisbon)
    @admin = users(:family_admin)
    @member = users(:family_member)
    # Already in the project: Starbucks, $10 spent on depository.
    @coffee = entries(:transaction)
  end

  test "adds up what was spent and received" do
    add(amount: 40, category: categories(:food_and_drink))
    add(amount: -25, category: categories(:income))

    totals = totals_for(@admin)

    assert_equal Money.new(50, "USD"), totals.spent
    assert_equal Money.new(25, "USD"), totals.received
    assert_equal Money.new(-25, "USD"), totals.net
    assert_equal 3, totals.transaction_count
  end

  test "leaves out transfers and excluded entries" do
    add(amount: 200, kind: "funds_movement")
    add(amount: 300, kind: "cc_payment")
    add(amount: 70).update!(excluded: true)

    assert_equal Money.new(10, "USD"), totals_for(@admin).spent
  end

  test "only counts accounts the viewer can see" do
    add(amount: 90, account: accounts(:connected))

    assert_equal Money.new(100, "USD"), totals_for(@admin).spent
    assert_equal Money.new(10, "USD"), totals_for(@member).spent
  end

  test "can narrow to one account" do
    add(amount: 90, account: accounts(:connected))

    totals = @project.totals(accounts: Account.where(id: accounts(:connected).id))

    assert_equal Money.new(90, "USD"), totals.spent
  end

  test "measures spending against the budget" do
    add(amount: 540)

    totals = totals_for(@admin)

    assert_equal 110, totals.budget_used_percent
    assert_equal Money.new(-50, "USD"), totals.budget_left
    assert totals.over_budget?
  end

  test "has no budget figures without a budget" do
    @project.update!(budget: nil)

    totals = totals_for(@admin)

    assert_nil totals.budget_left
    assert_nil totals.budget_used_percent
    assert_not totals.over_budget?
  end

  test "counts what can't be converted instead of guessing" do
    ExchangeRate.stubs(:find_or_fetch_rate).returns(nil)
    add(amount: 30, currency: "GBP")

    totals = totals_for(@admin)

    assert_equal Money.new(10, "USD"), totals.spent
    assert_equal 1, totals.unconverted_count
  end

  test "breaks spending down by category and by account" do
    add(amount: 40, category: categories(:food_and_drink))
    add(amount: 5, account: accounts(:connected))

    totals = totals_for(@admin)
    food = totals.by_category.find { |row| row.key == categories(:food_and_drink).id }
    uncategorized = totals.by_category.find { |row| row.key == "uncategorized" }

    assert_equal Money.new(50, "USD"), food.spent
    assert_equal Money.new(5, "USD"), uncategorized.spent
    assert_equal [ accounts(:depository).id, accounts(:connected).id ], totals.by_account.map(&:key)
  end

  test "open IOUs count on each side" do
    ious(:client_fee).update!(project: @project)
    ious(:dinner).update!(project: @project)

    totals = totals_for(@admin)

    assert_equal Money.new(1500, "USD"), totals.owed_to_you
    assert_equal Money.new(40, "USD"), totals.you_owe
    # IOUs never change what was spent.
    assert_equal Money.new(10, "USD"), totals.spent
  end

  test "an IOU on an account the viewer can't see doesn't count" do
    ious(:client_fee).update!(project: @project, account: accounts(:connected))

    assert_equal Money.new(0, "USD"), totals_for(@member).owed_to_you
    assert_equal Money.new(1500, "USD"), totals_for(@admin).owed_to_you
  end

  private
    def totals_for(user)
      @project.totals(accounts: Account.accessible_by(user))
    end

    def add(**attributes)
      create_transaction(**attributes).tap do |entry|
        @project.assign_transactions!([ entry.entryable_id ])
      end
    end
end
