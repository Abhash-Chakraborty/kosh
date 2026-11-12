require "test_helper"

class Project::CostSheetTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @project = projects(:lisbon)
    @admin = users(:family_admin)
    @food = categories(:food_and_drink)
    @income = categories(:income)
    # Already in the project: Starbucks, $10 spent on food and drink.
  end

  test "groups what was paid and received by category" do
    add(amount: 40, category: @food, name: "Dinner")
    add(amount: -25, category: @income, name: "Refund")

    sheet = sheet_for(@admin)
    food = group_named(sheet, @food.name)
    income = group_named(sheet, @income.name)

    assert_equal %w[Dinner Starbucks], food.lines.map(&:name).sort
    assert_equal %i[paid paid], food.lines.map(&:kind)
    assert_equal 50, food.net_cost
    assert_equal %i[received], income.lines.map(&:kind)
    assert_equal(-25, income.net_cost)
    assert_equal Money.new(50, "USD"), sheet.paid
    assert_equal Money.new(25, "USD"), sheet.received
    assert_equal Money.new(25, "USD"), sheet.net_cost
    assert_not sheet.open?
    assert_equal Money.new(25, "USD"), sheet.coming_in
  end

  test "open IOUs are lines that haven't moved yet" do
    ious(:dinner).update!(project: @project, category: @food)
    ious(:client_fee).update!(project: @project)

    sheet = sheet_for(@admin)
    food = group_named(sheet, @food.name)
    to_pay = food.lines.find { |line| line.kind == :to_pay }

    assert_equal "Dinner split", to_pay.name
    assert_equal "Maya", to_pay.person
    assert_equal 40, to_pay.amount
    assert to_pay.pending?
    assert_not to_pay.incoming?
    assert_equal 50, food.net_cost

    assert_equal Money.new(40, "USD"), sheet.to_pay
    assert_equal Money.new(1500, "USD"), sheet.to_receive
    # $10 paid + $40 to pay - $1,500 to come back.
    assert_equal Money.new(-1450, "USD"), sheet.net_cost
    assert_equal Money.new(-1460, "USD"), sheet.left_to_pay
    assert sheet.open?
    # Money is coming in, so the sheet reads as profit: $1,500 - $50 of cost.
    assert sheet.earns?
    assert_equal Money.new(1500, "USD"), sheet.coming_in
    assert_equal Money.new(1450, "USD"), sheet.profit
  end

  test "paying a project's IOU moves it from to pay to paid without changing the cost" do
    iou = ious(:dinner)
    iou.update!(project: @project, category: @food)
    before = sheet_for(@admin).net_cost

    payment = iou.record_payment(amount: 15, date: Date.current, account: accounts(:depository))

    assert payment.persisted?
    assert_equal @project, ProjectTransaction.project_for(payment.entry.entryable)

    sheet = sheet_for(@admin)
    assert_equal Money.new(25, "USD"), sheet.paid
    assert_equal Money.new(25, "USD"), sheet.to_pay
    assert_equal before, sheet.net_cost
  end

  test "a settled IOU has no open line" do
    iou = ious(:dinner)
    iou.update!(project: @project)
    iou.record_payment(amount: 40, date: Date.current, account: accounts(:depository))

    sheet = sheet_for(@admin)

    assert_equal Money.new(0, "USD"), sheet.to_pay
    assert_equal Money.new(50, "USD"), sheet.paid
  end

  test "a line carries the note that explains it" do
    ious(:dinner).update!(project: @project, notes: "Half of the bill at the cafe")

    line = sheet_for(@admin).groups.flat_map(&:lines).find { |candidate| candidate.kind == :to_pay }

    assert_equal "Half of the bill at the cafe", line.note
  end

  test "is empty for a project with nothing in it" do
    assert_not Project::CostSheet.new(projects(:old_kitchen).totals(accounts: Account.accessible_by(@admin))).any?
  end

  private
    def sheet_for(user)
      Project::CostSheet.new(@project.totals(accounts: Account.accessible_by(user)))
    end

    def group_named(sheet, name)
      sheet.groups.find { |group| group.name == name }
    end

    def add(**attributes)
      create_transaction(**attributes).tap do |entry|
        @project.assign_transactions!([ entry.entryable_id ])
      end
    end
end
