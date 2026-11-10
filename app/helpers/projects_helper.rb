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
