# A project's money line by line, grouped by category: what was paid, what
# came in, what is still to pay and what is still to come back. Every amount
# appears once, so the lines add up to what the project ends up costing.
#
# Built on Project::Totals, so it covers the same accounts and leaves out the
# same entries (transfers, excluded ones, split parents).
class Project::CostSheet
  Line = Data.define(:kind, :name, :date, :amount, :person, :note) do
    # Money coming to the family, moved already or still expected.
    def incoming? = kind.in?(%i[received to_receive])

    # Not moved yet: an open IOU.
    def pending? = kind.in?(%i[to_pay to_receive])
  end

  Group = Data.define(:key, :name, :color, :lines) do
    def total(kind)
      lines.sum(0.to_d) { |line| line.kind == kind ? line.amount : 0 }
    end

    # What this group ends up costing once its open IOUs are settled.
    def net_cost
      total(:paid) - total(:received) + total(:to_pay) - total(:to_receive)
    end
  end

  attr_reader :currency

  def initialize(totals)
    @totals = totals
    @currency = totals.currency
  end

  def groups
    @groups ||= lines
      .group_by(&:first)
      .map { |category, pairs| group_for(category, pairs.map(&:last)) }
      .sort_by { |group| [ -group.net_cost, group.name.to_s ] }
  end

  def any?
    groups.any?
  end

  def paid = money(sum(:paid))
  def received = money(sum(:received))
  def to_pay = money(sum(:to_pay))
  def to_receive = money(sum(:to_receive))

  # What the project ends up costing once everything open is settled.
  # Negative when it brings in more than it costs.
  def net_cost
    money(groups.sum(0.to_d, &:net_cost))
  end

  # Everything the project brings in, received or still expected: for client
  # work, what the client pays in all.
  def coming_in
    money(sum(:received) + sum(:to_receive))
  end

  # A project that brings in more than it costs is judged by its profit. A
  # trip where a friend pays back their half brings money in too, but still
  # costs: that one keeps its final cost.
  def earns?
    net_cost.negative?
  end

  # What is left of the money coming in after every cost, including ones
  # nobody is paying back.
  def profit
    money(-net_cost.amount)
  end

  # What still has to leave the family's pocket, after what comes back.
  # Negative when more is still to come in than to go out.
  def left_to_pay
    money(sum(:to_pay) - sum(:to_receive))
  end

  def open?
    sum(:to_pay).positive? || sum(:to_receive).positive?
  end

  def money(amount)
    Money.new(amount, @currency)
  end

  private
    def sum(kind)
      groups.sum(0.to_d) { |group| group.total(kind) }
    end

    def group_for(category, lines)
      Group.new(
        key: category&.id || "uncategorized",
        name: category&.name,
        color: category&.color,
        lines: lines.sort_by { |line| [ line.date ? 0 : 1, line.date || Date.current, line.name ] }
      )
    end

    # [ category, line ] pairs.
    def lines
      entry_lines + iou_lines
    end

    # Sure stores money going out as positive amounts.
    def entry_lines
      @totals.entry_amounts.map do |entry, amount|
        kind = amount.negative? ? :received : :paid
        [ entry.entryable.category, Line.new(kind: kind, name: entry.name, date: entry.date, amount: amount.abs, person: nil, note: entry.notes.presence) ]
      end
    end

    # An IOU in a currency with no exchange rate is left out, as in the totals.
    def iou_lines
      @totals.open_ious.filter_map do |iou|
        amount = iou.remaining_amount_money.exchange_to(@currency).amount
        kind = iou.i_owe? ? :to_pay : :to_receive
        [ iou.category, Line.new(kind: kind, name: iou.description, date: iou.due_on, amount: amount, person: iou.person, note: iou.notes.presence) ]
      rescue Money::ConversionError
        nil
      end
    end
end
