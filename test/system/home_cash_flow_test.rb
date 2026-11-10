require "application_system_test_case"

class HomeCashFlowTest < ApplicationSystemTestCase
  include EntriesTestHelper

  setup do
    @user = users(:family_admin)
    @user.update!(show_ai_sidebar: false, preferences: @user.preferences.merge("preview_features_enabled" => false))
    @month = Date.current.beginning_of_month
    @account = @user.family.accounts.create!(name: "Home checking", currency: "USD", balance: 0, accountable: Depository.new)
    parent = @user.family.categories.create!(name: "Home Shopping", color: "#123456")
    @child = @user.family.categories.create!(name: "Home Groceries", parent: parent)
    create_transaction(account: @account, category: parent, amount: 100, date: @month)
    create_transaction(account: @account, category: @child, amount: 50, date: @month)
  end

  test "the chart loads for everyone, expands from the header and opens transactions" do
    sign_in @user
    visit root_path(start_date: @month.iso8601, end_date: Date.current.iso8601)
    chart = find("#cashflow-preview [data-preview-sankey-chart-target='chart']", match: :first)
    assert_selector "#cashflow-preview svg .sankey-link"
    assert_no_selector "[data-controller='sankey-chart']"

    section = find("[data-section-key='cashflow_sankey']")
    section.hover
    section.find("button[data-action='click->cashflow-expand#open']").click
    within "#cashflow-preview-expanded-dialog[open]" do
      assert_selector "svg .sankey-link"
      find("button[data-action='DS--dialog#close']").click
    end
    assert_selector "[data-section-key='cashflow_sankey'][draggable='true']"

    chart.find("g[role='button'][aria-label^='Home Shopping,']").find("path").click
    chart.find("g[role='link'][aria-label^='Home Groceries,']").find("path").click
    assert_current_path(%r{/transactions\?})
    assert_equal [ "Home Groceries" ], Rack::Utils.parse_nested_query(URI.parse(page.current_url).query).dig("q", "categories")
  end

  test "open IOUs are drawn apart from the graph and open the Owed page" do
    sign_in @user
    visit root_path(start_date: @month.iso8601, end_date: Date.current.iso8601)
    chart = find("#cashflow-preview [data-preview-sankey-chart-target='chart']", match: :first)
    assert_selector "#cashflow-preview svg .sankey-link"

    chart.assert_selector "g[data-pending-id='pending_owed_to_me_0'][aria-label*='Ravi']"
    chart.assert_selector "g[data-pending-id='pending_i_owe_0'][aria-label*='Maya']"
    # Not part of the graph: no flow runs into or out of them.
    links = chart.all(".sankey-link").map { |link| link.evaluate_script("[this.__data__.source.id, this.__data__.target.id]") }.flatten
    assert links.none? { |id| id.start_with?("pending_") }

    chart.find("g[data-pending-id='pending_owed_to_me_0'] rect").click
    assert_current_path ious_path
  end

  test "many categories make the chart taller and keep labels apart on a phone" do
    16.times do |i|
      category = @user.family.categories.create!(name: "Home category with a long name #{i}", color: "#336699")
      create_transaction(account: @account, category: category, amount: 10 + i, date: @month)
    end
    page.current_window.resize_to(390, 844)
    sign_in @user
    visit root_path(start_date: @month.iso8601, end_date: Date.current.iso8601)
    chart = find("#cashflow-preview [data-preview-sankey-chart-target='chart']", match: :first)
    assert_selector "#cashflow-preview svg .sankey-link"

    assert_operator chart.find("svg").evaluate_script("this.getBoundingClientRect().height"), :>, 384
    overlaps = chart.evaluate_script(<<~JS)
      (() => {
        const boxes = Array.from(this.querySelectorAll("svg text"))
          .filter((text) => text.style.opacity !== "0")
          .map((text) => text.getBoundingClientRect());
        return boxes.filter((a, i) => boxes.some((b, j) => j > i &&
          a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom)).length;
      })()
    JS
    assert_equal 0, overlaps
  end
end
