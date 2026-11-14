require "test_helper"

class ItineraryItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @project = projects(:lisbon)
    @item = itinerary_items(:lisbon_flight)
  end

  test "a trip's page shows its itinerary by day" do
    get project_url(@project)

    assert_response :success
    assert_select "#itinerary h2", text: "Itinerary"
    assert_select "#itinerary [data-itinerary-day]", count: 2
    assert_select "[data-itinerary-day='#{@item.starts_on.iso8601}'] h3", text: /Day 1/
    assert_select "##{dom_id(@item)} p", text: /09:30\s+Flight to Lisbon/
    assert_select "##{dom_id(@item)} a[href*='google.com/maps'][target='_blank']", text: "Lisbon Airport"
    assert_select "##{dom_id(@item)} p", text: /Ref ABC123/
    assert_select "##{dom_id(itinerary_items(:lisbon_hostel))} p", text: /until/
    assert_select "#itinerary p", text: "Lisbon Airport → Alfama"
  end

  test "a project that isn't a trip has no itinerary" do
    project = @user.family.projects.create!(name: "Workshop", kind: "project")

    get project_url(project)

    assert_select "#itinerary", count: 0
    assert_select "#files"
  end

  test "the new form starts on the day asked for" do
    get new_project_itinerary_item_url(@project, date: "2026-11-27")

    assert_response :success
    assert_select "input[name='itinerary_item[starts_on]'][value='2026-11-27']"
  end

  test "adds a line to the itinerary" do
    assert_difference -> { @project.itinerary_items.count }, 1 do
      post project_itinerary_items_url(@project), params: { itinerary_item: {
        kind: "train", title: "Night train", starts_on: @project.start_on + 2, time_of_day: "21:15",
        location: "Santa Apolonia", reference: "PNR 42", notes: "Coach B"
      } }
    end

    assert_redirected_to project_url(@project, anchor: "itinerary")
    item = @project.itinerary_items.order(:created_at).last
    assert_equal [ "train", "Night train", "21:15", "Santa Apolonia", "PNR 42", "Coach B" ],
      [ item.kind, item.title, item.time_of_day, item.location, item.reference, item.notes ]
  end

  test "a line without a title isn't saved" do
    assert_no_difference -> { ItineraryItem.count } do
      post project_itinerary_items_url(@project), params: { itinerary_item: { kind: "train", title: "", starts_on: Date.current } }
    end

    assert_response :unprocessable_entity
  end

  test "changes a line" do
    patch project_itinerary_item_url(@project, @item), params: { itinerary_item: { title: "Flight to Porto", time_of_day: "" } }

    assert_redirected_to project_url(@project, anchor: "itinerary")
    assert_equal "Flight to Porto", @item.reload.title
    assert_nil @item.time_of_day
  end

  test "removes a line" do
    assert_difference -> { @project.itinerary_items.count }, -1 do
      delete project_itinerary_item_url(@project, @item)
    end

    assert_redirected_to project_url(@project, anchor: "itinerary")
  end

  test "can't reach another family's itinerary" do
    theirs = families(:empty).projects.create!(name: "Theirs", kind: "trip")
    item = theirs.itinerary_items.create!(title: "Bus", starts_on: Date.current)

    get new_project_itinerary_item_url(theirs)
    assert_response :not_found

    delete project_itinerary_item_url(theirs, item)
    assert_response :not_found
    assert ItineraryItem.exists?(item.id)
  end

  test "a line can't be reached through another project" do
    other = @user.family.projects.create!(name: "Other", kind: "trip")

    patch project_itinerary_item_url(other, @item), params: { itinerary_item: { title: "Moved" } }

    assert_response :not_found
    assert_equal "Flight to Lisbon", @item.reload.title
  end
end
