module IousHelper
  # "15 Nov" or "Nov 15", following whether the family writes the day or the
  # month first. The year is added when it isn't this year.
  def iou_short_date(date)
    day_first = Current.family&.date_format.to_s.start_with?("%d", "%e")
    format = day_first ? "%-d %b" : "%b %-d"
    format += " %Y" unless date.year == Date.current.year
    I18n.l(date, format: format)
  end

  def iou_due_label(iou)
    return if iou.due_on.blank?

    date = iou_short_date(iou.due_on)
    iou.overdue? ? t("ious.iou.overdue", date: date) : t("ious.iou.due", date: date)
  end

  def iou_direction_label(iou)
    iou.owed_to_me? ? t("ious.iou.owed_to_me") : t("ious.iou.i_owe")
  end

  # IOUs are shared with the whole family; an account's name only shows to
  # members who can see that account.
  def iou_account_visible?(account)
    return false if account.nil? || Current.user.nil?

    @iou_accessible_account_ids ||= Current.user.accessible_accounts.pluck(:id).to_set
    @iou_accessible_account_ids.include?(account.id)
  end

  def iou_account_label(account, iou)
    return unless iou_account_visible?(account)

    iou.owed_to_me? ? t("ious.iou.into_account", account: account.name) : t("ious.iou.from_account", account: account.name)
  end

  # Direction, account and project, for the line under an IOU's description.
  # The project links to its page.
  def iou_details(iou)
    parts = [ iou_direction_label(iou), iou_account_label(iou.account, iou) ].compact
    parts << iou_project_link(iou) if iou.project
    safe_join(parts, " · ")
  end

  # The project an IOU belongs to. `_top`, because the link also sits on the
  # account page, inside that page's turbo frame.
  def iou_project_link(iou)
    link_to iou.project.name, project_path(iou.project), data: { turbo_frame: "_top" }, class: "underline-offset-2 hover:text-primary hover:underline"
  end

  # Who, when and what for, under an IOU on its account's page:
  # "You owe Zostel · Due 28 Nov · Bangalore trip · Stays".
  def iou_outstanding_details(iou)
    who = iou.owed_to_me? ? t("ious.account_outstanding.from", person: iou.person) : t("ious.account_outstanding.to", person: iou.person)
    parts = [ who, iou_due_label(iou) ]
    parts << iou_project_link(iou) if iou.project
    parts << iou.category.name if iou.category
    safe_join(parts.compact, " · ")
  end

  # Share of an IOU already paid, as a whole percent.
  def iou_paid_percent(iou)
    return 0 unless iou.amount.to_d.positive?

    (iou.paid_amount.to_d / iou.amount.to_d * 100).round
  end

  # One person's open IOUs set against each other, in the family's currency:
  # positive when they owe the family on balance.
  def iou_person_net(ious)
    currency = Current.family.primary_currency_code
    owed_to_you, _skipped = Iou.remaining_total(ious.select(&:owed_to_me?), currency: currency)
    you_owe, _skipped = Iou.remaining_total(ious.select(&:i_owe?), currency: currency)
    owed_to_you - you_owe
  end

  def iou_person_net_label(person, net)
    if net.positive?
      t("ious.person.owes_you", person: person, amount: format_money(net))
    elsif net.negative?
      t("ious.person.you_owe", person: person, amount: format_money(net.abs))
    else
      t("ious.person.even", person: person)
    end
  end

  def iou_direction_options
    Iou::DIRECTIONS.map { |direction| [ t("ious.form.directions.#{direction}"), direction ] }
  end

  # Open IOUs for the cash flow chart, each opening the Owed page.
  def iou_pending_flows(period)
    Iou::PendingFlows.new(Current.family, period: period).as_json.map { |flow| flow.merge(url: ious_path) }
  end
end
