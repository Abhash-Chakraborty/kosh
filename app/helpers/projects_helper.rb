module ProjectsHelper
  def project_kind_label(project)
    t("projects.kinds.#{project.kind}")
  end

  def project_kind_options
    Project::KINDS.map { |kind| [ t("projects.kinds.#{kind}"), kind ] }
  end

  # "12 Nov – 20 Nov", "From 12 Nov", "Until 20 Nov" or nil, written the way
  # the family writes dates (see IousHelper#iou_short_date).
  def project_dates(project)
    from = iou_short_date(project.start_on) if project.start_on
    to = iou_short_date(project.end_on) if project.end_on

    if from && to
      "#{from} – #{to}"
    elsif from
      t("projects.dates.from", date: from)
    elsif to
      t("projects.dates.until", date: to)
    end
  end

  # Kind and dates for the line under a project's name.
  def project_subtitle(project)
    [ project_kind_label(project), project_dates(project) ].compact.join(" · ")
  end

  # Width of the spent share of a budget bar, capped at 100.
  def project_budget_bar_width(totals)
    [ totals.budget_used_percent.to_i, 100 ].min
  end

  # "Paid · 12 Nov" or "To pay Saksham · 28 Nov", under a cost sheet line.
  def project_cost_line_detail(line)
    label = t("projects.cost_sheet.kinds.#{line.kind}", person: line.person)
    [ label, (iou_short_date(line.date) if line.date) ].compact.join(" · ")
  end

  # Money coming in carries a plus sign.
  def project_cost_line_amount(sheet, line)
    amount = format_money(sheet.money(line.amount))
    line.incoming? ? "+#{amount}" : amount
  end

  # Active projects for the strip that switches between Home and one project.
  def project_switcher_projects
    Current.family.projects.active.ordered.to_a
  end

  # Where a project stands, for its line on Home and on the projects page:
  # "₹1,752.02 left to pay · ₹6,005.17 in all". Nil when nothing has moved.
  def project_position(totals)
    sheet = Project::CostSheet.new(totals)
    return unless sheet.any?

    parts = []
    if sheet.open?
      left = sheet.left_to_pay
      parts << (left.negative? ? t("projects.position.to_receive", amount: format_money(left.abs)) : t("projects.position.to_pay", amount: format_money(left)))
    end
    parts << if sheet.earns?
      t("projects.position.profit", amount: format_money(sheet.profit))
    else
      t("projects.position.final_cost", amount: format_money(sheet.net_cost))
    end
    parts.join(" · ")
  end

  def project_account_options(accounts)
    accounts.map { |account| [ account.name, account.id ] }
  end

  # Choices for a transaction's Project select: active projects, plus the
  # one it is in now if that one is archived.
  def transaction_project_options(current)
    projects = Current.family.projects.active.ordered.to_a
    projects << current if current && !projects.include?(current)
    projects.map { |project| [ project.name, project.id ] }
  end
end
