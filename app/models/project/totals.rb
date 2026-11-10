# What a project has cost and brought in, over the accounts the viewer may
# see (or one of them). Money is shown in the project's currency; an amount
# with no exchange rate is left out and counted in #unconverted_count.
#
# Transfers between the family's own accounts don't count, nor do excluded
# entries or split parents (their parts are the transactions that count).
class Project::Totals
  # Kinds that only move money between the family's own accounts.
  TRANSFER_KINDS = %w[funds_movement cc_payment].freeze

  Row = Data.define(:key, :name, :color, :spent, :received) do
    def net = received - spent
  end

  attr_reader :project, :currency

  def initialize(project, accounts:)
    @project = project
    @accounts = accounts
    @currency = project.currency
  end

  def entries
    @entries ||= Entry
      .where(entryable_type: "Transaction", entryable_id: @project.project_transactions.select(:transaction_id))
      .where(account_id: @accounts.select(:id), excluded: false)
      .excluding_split_parents
      .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id")
      .where.not(transactions: { kind: TRANSFER_KINDS })
      .includes(:account, entryable: :category)
      .order(date: :desc, created_at: :desc)
      .to_a
  end

  def spent = money(sums[:spent])
  def received = money(sums[:received])
  def net = money(sums[:received] - sums[:spent])

  def transaction_count = entries.size

  def unconverted_count
    sums
    @unconverted
  end

  # Budget left (negative once over), or nil without a budget.
  def budget_left
    @project.budget_money - spent if @project.budget
  end

  # Share of the budget spent, 0-100+, or nil without a budget.
  def budget_used_percent
    return unless @project.budget&.positive?

    (sums[:spent] / @project.budget.to_d * 100).round
  end

  def over_budget?
    budget_left&.negative? || false
  end

  # What is still open on this project's IOUs, in each direction. Only IOUs
  # on the given accounts, or on no account, count.
  def owed_to_you = open_iou_total("owed_to_me")
  def you_owe = open_iou_total("i_owe")

  def by_category
    rows do |entry|
      category = entry.entryable.category
      [ category&.id || "uncategorized", category&.name, category&.color ]
    end
  end

  def by_account
    rows { |entry| [ entry.account_id, entry.account.name, nil ] }
  end

  private
    def money(amount)
      Money.new(amount, @currency)
    end

    def converted
      @converted ||= begin
        @unconverted = 0
        entries.filter_map do |entry|
          amount = Money.new(entry.amount, entry.currency).exchange_to(@currency, date: entry.date).amount
          [ entry, amount ]
        rescue Money::ConversionError
          @unconverted += 1
          nil
        end
      end
    end

    # Sure stores money going out as positive amounts and money coming in as
    # negative ones.
    def sums
      @sums ||= converted.each_with_object({ spent: 0.to_d, received: 0.to_d }) do |(_entry, amount), totals|
        amount.positive? ? totals[:spent] += amount : totals[:received] += amount.abs
      end
    end

    def rows
      grouped = converted.group_by { |entry, _amount| yield(entry) }
      grouped.map do |(key, name, color), pairs|
        spent = pairs.sum(0.to_d) { |_entry, amount| amount.positive? ? amount : 0 }
        received = pairs.sum(0.to_d) { |_entry, amount| amount.negative? ? amount.abs : 0 }
        Row.new(key: key, name: name, color: color, spent: money(spent), received: money(received))
      end.sort_by { |row| [ -row.spent.amount, -row.received.amount ] }
    end

    def open_iou_total(direction)
      ious = @project.ious.outstanding.where(direction: direction).includes(:payments)
      ious = ious.where(account_id: nil).or(ious.where(account_id: @accounts.select(:id)))
      total, _skipped = Iou.remaining_total(ious.to_a, currency: @currency)
      total
    end
end
