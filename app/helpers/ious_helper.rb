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

  def iou_account_label(account, iou)
    return if account.nil?

    iou.owed_to_me? ? t("ious.iou.into_account", account: account.name) : t("ious.iou.from_account", account: account.name)
  end

  def iou_direction_options
    Iou::DIRECTIONS.map { |direction| [ t("ious.form.directions.#{direction}"), direction ] }
  end
end
