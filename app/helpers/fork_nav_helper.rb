# Sidebar items this fork adds. They're inserted here instead of in the layout's
# list so upstream changes to that list merge without conflicts.
module ForkNavHelper
  def fork_nav_items
    [
      { name: t("layouts.application.nav.owed"), path: ious_path, icon: "hand-coins", icon_custom: false, active: page_active?(ious_path) },
      # Phones reach projects from the Projects section on Home; the bottom
      # bar has no room for another item.
      { name: t("layouts.application.nav.projects"), path: projects_path, icon: "folder-kanban", icon_custom: false, active: page_active?(projects_path), desktop_only: true }
    ]
  end

  # Puts the fork's items before the first phone-only item (the assistant),
  # or at the end when there is none, then drops the hidden ones.
  def with_fork_nav_items(items)
    at = items.index { |item| item[:mobile_only] } || items.size
    items.dup.insert(at, *fork_nav_items).reject { |item| fork_nav_hidden?(item) }
  end

  # FORK_HIDE_NAV lists pages to leave out of the sidebar and the phone bar by
  # the first part of their path, such as "bills,portfolio". The pages
  # themselves still open by link.
  def fork_nav_hidden?(item)
    hidden = ENV.fetch("FORK_HIDE_NAV", "").split(",").map { |name| name.strip.downcase }.reject(&:blank?)
    return false if hidden.empty?

    hidden.include?(item[:path].to_s.split("?").first.to_s.delete_prefix("/").split("/").first.to_s.downcase)
  end
end
