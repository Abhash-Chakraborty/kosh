require "test_helper"

class ItineraryItemTest < ActiveSupport::TestCase
  setup do
    @project = projects(:lisbon)
    @item = itinerary_items(:lisbon_flight)
  end

  test "needs a title, a date and a known kind" do
    item = @project.itinerary_items.new(kind: "teleport")

    assert_not item.valid?
    assert item.errors.added?(:title, :blank)
    assert item.errors.added?(:starts_on, :blank)
    assert item.errors.of_kind?(:kind, :inclusion)
  end

  test "can't end before it starts" do
    @item.ends_on = @item.starts_on - 1

    assert_not @item.valid?
    assert @item.errors.added?(:ends_on, :before_start)
  end

  test "takes a time as hours and minutes" do
    @item.time_of_day = "25:00"
    assert_not @item.valid?

    @item.time_of_day = "07:05:00"
    assert @item.valid?
    assert_equal "07:05", @item.time_of_day
  end

  test "blank details are stored as nothing" do
    @item.update!(time_of_day: "", location: "  ", reference: "", notes: "")

    assert_nil @item.time_of_day
    assert_nil @item.location
    assert_nil @item.reference
    assert_nil @item.notes
  end

  test "orders by day, then time, with untimed lines after timed ones" do
    late = @project.itinerary_items.create!(title: "Dinner", kind: "food", starts_on: @item.starts_on, time_of_day: "20:00")

    assert_equal [ @item, late, itinerary_items(:lisbon_hostel), itinerary_items(:lisbon_tram) ],
      @project.itinerary_items.chronological.to_a
  end

  test "a stay runs over several days" do
    assert itinerary_items(:lisbon_hostel).multi_day?
    assert_not @item.multi_day?
  end

  test "goes when its project is deleted" do
    assert_difference -> { ItineraryItem.count }, -3 do
      @project.destroy!
    end
  end
end
