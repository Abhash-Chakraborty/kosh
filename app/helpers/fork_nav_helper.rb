# Sidebar items this fork adds. They're inserted here instead of in the layout's
# list so upstream changes to that list merge without conflicts.
module ForkNavHelper
  def fork_nav_items
    [
      { name: t("layouts.application.nav.owed"), path: ious_path, icon: "hand-coins", icon_custom: false, active: page_active?(ious_path) }
    ]
  end

  # Puts the fork's items before the first phone-only item (the assistant),
  # or at the end when there is none.
  def with_fork_nav_items(items)
    at = items.index { |item| item[:mobile_only] } || items.size
    items.dup.insert(at, *fork_nav_items)
  end
end
