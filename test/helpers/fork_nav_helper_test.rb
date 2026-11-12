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

  test "FORK_HIDE_NAV leaves pages out by the first part of their path" do
    items = [ { name: "Home", path: "/" }, { name: "Bills", path: "/bills" }, { name: "Portfolio", path: "/portfolio/holdings?tab=all" } ]

    ClimateControl.modify(FORK_HIDE_NAV: "bills, Portfolio ,ious") do
      names = with_fork_nav_items(items).map { |item| item[:name] }
      assert_equal [ "Home", I18n.t("layouts.application.nav.projects") ], names
    end
  end

  test "nothing is hidden without FORK_HIDE_NAV" do
    ClimateControl.modify(FORK_HIDE_NAV: nil) do
      assert_equal 3, with_fork_nav_items([ { name: "Bills", path: "/bills" } ]).size
    end
  end

  test "projects stay off the phone bar" do
    projects = with_fork_nav_items([ { name: "Home" } ]).find { |item| item[:path] == projects_path }
    assert projects[:desktop_only]
  end
end
