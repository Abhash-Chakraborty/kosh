# Open IOUs for the cash flow chart, drawn as flows that haven't happened yet:
# money owed to the family beside income, money it owes beside spending. Only
# for a period that includes today, since that is when the money is still
# expected. Nothing here feeds a total or percentage; the chart draws these
# apart from the graph.
class Iou::PendingFlows
  # Up to this many people on a side get a node each; more share one.
  PER_PERSON_LIMIT = 3

  def initialize(family, period:, today: Date.current)
    @family, @period, @today = family, period, today
  end

  def as_json(*)
    return [] unless covers_today?

    open_ious = @family.ious.outstanding.includes(:payments).to_a
    Iou::DIRECTIONS.flat_map do |direction|
      nodes_for(direction, open_ious.select { |iou| iou.direction == direction })
    end
  end

  private
    def covers_today?
      @period.start_date <= @today && @period.end_date >= @today
    end

    def nodes_for(direction, ious)
      people = ious.group_by { |iou| iou.person.strip.downcase }.filter_map do |_, group|
        total, _skipped = Iou.remaining_total(group, currency: currency)
        { person: group.first.person.strip, amount: total.amount } if total.amount.positive?
      end
      return [] if people.empty?

      if people.size > PER_PERSON_LIMIT
        amount = people.sum { |person| person[:amount] }
        [ node(direction, 0, I18n.t("ious.pending_flows.#{direction}.everyone"), amount,
            I18n.t("ious.pending_flows.#{direction}.people", count: people.size)) ]
      else
        people.sort_by { |person| -person[:amount] }.each_with_index.map do |person, index|
          node(direction, index, person[:person], person[:amount],
            I18n.t("ious.pending_flows.#{direction}.person", person: person[:person]))
        end
      end
    end

    def node(direction, index, name, amount, description)
      {
        id: "pending_#{direction}_#{index}",
        direction: direction,
        name: name,
        description: description,
        note: I18n.t("ious.pending_flows.#{direction}.note"),
        value: amount.to_d.round(2).to_f
      }
    end

    def currency
      @family.primary_currency_code
    end
end
