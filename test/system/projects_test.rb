require "application_system_test_case"

class ProjectsTest < ApplicationSystemTestCase
  include EntriesTestHelper

  PHONE = [ 390, 844 ].freeze

  setup do
    sign_in @user = users(:family_admin)
    @family = @user.family
    @project = projects(:lisbon)
  end

  teardown do
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "make a project and add a transaction to it from the drawer" do
    visit projects_url
    click_on "New project"

    within "dialog[open]" do
      fill_in "Name", with: "Garden"
      select "Trip", from: "Kind"
      click_button "Create"
    end

    assert_selector "h1", text: "Garden"
    garden = @family.projects.find_by!(name: "Garden")
    assert garden.trip?

    entry = entries(:transaction)
    visit transactions_url
    page.execute_script <<~JS
      document.querySelector("turbo-frame#drawer").src = "#{transaction_url(entry)}"
    JS

    within "turbo-frame#drawer", visible: :all do
      # It sits with merchant and tags, under Details.
      find("summary", text: /\A\s*details\s*\z/i).click
      select "Garden", from: "Project"
      assert_selector "##{ActionView::RecordIdentifier.dom_id(entry, :project)} option[selected]", text: "Garden", visible: :all
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/projects-drawer.png"))

    visit project_url(garden)
    assert_selector "a[href='#{transaction_path(entry)}']", text: entry.name
  end

  test "project pages and the Home section fit a phone" do
    fill_project
    visit_and_check(project_url(@project), "the project page")
    page.save_screenshot(Rails.root.join("tmp/screenshots/projects-show-desktop.png"))

    page.driver.browser.manage.window.resize_to(*PHONE)

    visit_and_check(projects_url, "the projects list")
    page.save_screenshot(Rails.root.join("tmp/screenshots/projects-index-phone.png"))

    visit_and_check(project_url(@project), "the project page")
    page.save_screenshot(Rails.root.join("tmp/screenshots/projects-show-phone.png"))

    visit_and_check(root_url, "Home")
    page.execute_script("document.querySelector(\"section[data-section-key='projects']\").scrollIntoView({ block: 'center' })")
    page.save_screenshot(Rails.root.join("tmp/screenshots/projects-home-phone.png"))
  end

  private
    # A long name, a few categories, an IOU each way and a budget nearly used.
    def fill_project
      @project.update!(name: "Two weeks in Lisbon and Porto with the whole family", budget: 600)
      [
        [ "Hotel Avenida Palace, three nights including breakfast", 320, categories(:food_and_drink) ],
        [ "Train Lisbon to Porto", 48, nil ],
        [ "Refund from the airline for the delayed flight", -75, categories(:income) ]
      ].each do |name, amount, category|
        entry = create_transaction(name: name, amount: amount, category: category, date: Date.current - 12)
        @project.assign_transactions!([ entry.entryable_id ])
      end
      ious(:client_fee).update!(project: @project)
      ious(:dinner).update!(project: @project)
    end

    def visit_and_check(url, label)
      visit url
      assert_selector "#main"
      overflow = page.evaluate_script(<<~JS)
        (() => {
          const main = document.querySelector("#main");
          return {
            doc: document.documentElement.scrollWidth - document.documentElement.clientWidth,
            main: main ? main.scrollWidth - main.clientWidth : 0
          };
        })()
      JS
      assert_operator overflow["doc"], :<=, 1, "#{label} scrolls the document sideways"
      assert_operator overflow["main"], :<=, 1, "#{label} scrolls its main content sideways"
    end
end
