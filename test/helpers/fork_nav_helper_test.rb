require "test_helper"

class ForkNavHelperTest < ActionView::TestCase
  # page_active? lives in ApplicationHelper.
  include ApplicationHelper

  test "adds the owed page before the phone-only items" do
    items = [ { name: "Home" }, { name: "Assistant", mobile_only: true } ]
    names = with_fork_nav_items(items).map { |item| item[:name] }
    assert_equal [ "Home", I18n.t("layouts.application.nav.owed"), I18n.t("layouts.application.nav.projects"), "Assistant" ], names
  end

  test "adds the owed page at the end when nothing is phone-only" do
    names = with_fork_nav_items([ { name: "Home" } ]).map { |item| item[:name] }
    assert_equal [ "Home", I18n.t("layouts.application.nav.owed"), I18n.t("layouts.application.nav.projects") ], names
  end

  test "projects stay off the phone bar" do
    projects = with_fork_nav_items([ { name: "Home" } ]).find { |item| item[:path] == projects_path }
    assert projects[:desktop_only]
  end
end
