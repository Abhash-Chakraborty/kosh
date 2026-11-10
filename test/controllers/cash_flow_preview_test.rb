require "test_helper"

class CashFlowPreviewTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    Rails.configuration.x.posthog.stubs(:development_enabled).returns(false)
  end

  test "development loads configured popup surveys only with testing override" do
    Rails.env.stubs(:development?).returns(true)
    Rails.configuration.x.posthog.stubs(:api_key).returns("configured-test-project")
    get root_path
    assert_select "head script", text: /posthog.init\('configured-test-project'/, count: 0
    Rails.configuration.x.posthog.stubs(:development_enabled).returns(true)
    get root_path
    assert_select "head script", text: /posthog.init\('configured-test-project'/
    assert_select "head script", text: /client.register\(\{ sure_version: #{Regexp.escape(Sure.version.to_s.to_json)}/
  end
end
