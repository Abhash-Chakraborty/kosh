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

  # Kind, dates and where today falls in them, for the line under a
  # project's name: "Trip · 26 Nov – 6 Dec · Starts in 12 days".
  def project_subtitle(project)
    [ project_kind_label(project), project_dates(project), project_timeline(project) ].compact.join(" · ")
  end

  # "Starts in 12 days", "Day 3 of 11" or "Ended 6 Dec". Nil for a project
  # that is on hold or completed (its status says more) or has no dates.
  def project_timeline(project, today = Date.current)
    return unless project.status == "active"

    case project.phase(today)
    when :upcoming
      days = (project.start_on - today).to_i
      days == 1 ? t("projects.timeline.starts_tomorrow") : t("projects.timeline.starts_in", count: days)
    when :ongoing
      if project.total_days
        t("projects.timeline.day_of", day: project.day_number(today), total: project.total_days)
      else
        t("projects.timeline.day", day: project.day_number(today))
      end
    when :past
      t("projects.timeline.ended", date: iou_short_date(project.end_on))
    end
  end

  def project_status_options
    Project::STATUSES.map { |status| [ t("projects.statuses.#{status}"), status ] }
  end

  # The pill beside a project that is on hold or completed; nothing while
  # it is underway.
  def project_status_pill(project)
    return if project.status == "active"

    render DS::Pill.new(label: t("projects.statuses.#{project.status}"), tone: project.completed? ? :green : :amber)
  end

  # An itinerary grouped by day: [ [ date, items ], ... ] in date order.
  def itinerary_days(items)
    items.group_by(&:starts_on).sort_by(&:first)
  end

  # "Thu 26 Nov · Day 1"; the day number only inside the trip's dates.
  def itinerary_day_heading(project, date)
    day = project.day_number(date)
    heading = "#{I18n.l(date, format: "%a")} #{iou_short_date(date)}"
    day ? t("projects.itinerary.day_heading", date: heading, day: day) : heading
  end

  # Kind, place and booking reference under an itinerary line. The place
  # opens in a map.
  def itinerary_item_details(item)
    parts = [ t("itinerary_items.kinds.#{item.kind}") ]
    parts << t("projects.itinerary.until", date: iou_short_date(item.ends_on)) if item.multi_day?
    if item.location
      parts << link_to(item.location, itinerary_map_url(item.location), target: "_blank", rel: "noopener noreferrer",
        class: "underline underline-offset-2 hover:text-primary")
    end
    parts << t("projects.itinerary.reference", reference: item.reference) if item.reference
    safe_join(parts, " · ")
  end

  def itinerary_map_url(place)
    "https://www.google.com/maps/search/?api=1&query=#{ERB::Util.url_encode(place)}"
  end

  def itinerary_kind_options
    ItineraryItem::KINDS.map { |kind| [ t("itinerary_items.kinds.#{kind}"), kind ] }
  end

  # The places a plan names, in the order it reaches them, each once.
  def itinerary_places(items)
    items.filter_map(&:location).uniq { |place| place.downcase }
  end

  # A thumbnail for a picture the server can resize; nil for other files.
  def project_file_thumbnail(file)
    return unless file.variable?

    image_tag url_for(file.variant(resize_to_limit: [ 480, 480 ])), alt: file.filename.to_s, loading: "lazy",
      class: "w-full h-full object-contain"
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
  # Underway projects, plus the one being looked at if it is on hold,
  # completed or archived.
  def project_switcher_projects(current = nil)
    projects = Current.family.projects.underway.ordered.to_a
    projects << current if current && !projects.include?(current)
    projects
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
