require "test_helper"

class ForkIconHelperTest < ActionView::TestCase
  include ApplicationHelper

  setup do
    drawn = @drawn = []
    singleton_class.send(:define_method, :lucide_icon) do |key, **_opts|
      drawn << key
      "<svg></svg>".html_safe
    end
  end

  teardown do
    singleton_class.send(:remove_method, :lucide_icon) if singleton_class.method_defined?(:lucide_icon)
  end

  test "sparkle icons are drawn as a plain one" do
    icon("sparkles")
    icon("Sparkles ", size: "sm")
    icon("wand-sparkles")

    assert_equal %w[zap zap zap], @drawn
  end

  test "other icons are left alone" do
    icon("pencil")

    assert_equal %w[pencil], @drawn
  end

  test "the swap sits in front of ApplicationHelper#icon for every caller" do
    ancestors = ApplicationHelper.ancestors

    assert_operator ancestors.index(ForkIconHelper), :<, ancestors.index(ApplicationHelper)
  end
end
