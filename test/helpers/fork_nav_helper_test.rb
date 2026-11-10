require "test_helper"

class ForkNavHelperTest < ActionView::TestCase
  # page_active? lives in ApplicationHelper.
  include ApplicationHelper

  test "adds the owed page before the phone-only items" do
    items = [ { name: "Home" }, { name: "Assistant", mobile_only: true } ]
    names = with_fork_nav_items(items).map { |item| item[:name] }
    assert_equal [ "Home", I18n.t("layouts.application.nav.owed"), "Assistant" ], names
  end

  test "adds the owed page at the end when nothing is phone-only" do
    names = with_fork_nav_items([ { name: "Home" } ]).map { |item| item[:name] }
    assert_equal [ "Home", I18n.t("layouts.application.nav.owed") ], names
  end
end
