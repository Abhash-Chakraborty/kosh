require "test_helper"

class IouPeopleControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @iou = ious(:client_fee)
  end

  test "the Owed page sets a person's IOUs against each other" do
    @user.family.ious.create!(direction: "i_owe", person: "ravi", description: "Lunch", amount: 200, currency: "USD")

    get ious_url

    assert_response :success
    assert_select "p", text: "Ravi owes you $1,300.00 in all"
    assert_select "p", text: "You owe Maya $40.00 in all"
  end

  test "opens the rename form for a person" do
    get edit_iou_person_url(name: "Ravi")

    assert_response :success
    assert_select "input[name='iou_person[new_name]'][value='Ravi']"
  end

  test "renames a person on all of their IOUs, whatever the case" do
    other = @user.family.ious.create!(direction: "i_owe", person: " ravi ", description: "Lunch", amount: 20, currency: "USD")

    patch iou_person_url, params: { iou_person: { name: "Ravi", new_name: "Ravi Kumar" } }

    assert_redirected_to ious_url
    assert_equal "Ravi Kumar", @iou.reload.person
    assert_equal "Ravi Kumar", other.reload.person
    assert_equal "Maya", ious(:dinner).reload.person
  end

  test "a blank name isn't saved" do
    patch iou_person_url, params: { iou_person: { name: "Ravi", new_name: "  " } }

    assert_response :unprocessable_entity
    assert_equal "Ravi", @iou.reload.person
  end

  test "an unknown person isn't found" do
    get edit_iou_person_url(name: "Nobody")

    assert_response :not_found
  end

  test "another family's person isn't found" do
    theirs = families(:empty).ious.create!(direction: "i_owe", person: "Zed", description: "Lunch", amount: 20, currency: "USD")

    patch iou_person_url, params: { iou_person: { name: "Zed", new_name: "Changed" } }

    assert_response :not_found
    assert_equal "Zed", theirs.reload.person
  end

  test "the IOU form suggests people already on the page" do
    get new_iou_url

    assert_select "datalist#iou-people option[value='Ravi']"
    assert_select "input[name='iou[person]'][list='iou-people']"
  end
end
