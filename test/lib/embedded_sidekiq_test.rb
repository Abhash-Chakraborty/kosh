require "test_helper"

class EmbeddedSidekiqTest < ActiveSupport::TestCase
  test "reads the switch from SIDEKIQ_EMBEDDED" do
    with_env_overrides("SIDEKIQ_EMBEDDED" => "true") { assert EmbeddedSidekiq.enabled? }
    with_env_overrides("SIDEKIQ_EMBEDDED" => "1") { assert EmbeddedSidekiq.enabled? }
    with_env_overrides("SIDEKIQ_EMBEDDED" => "false") { assert_not EmbeddedSidekiq.enabled? }
    with_env_overrides("SIDEKIQ_EMBEDDED" => nil) { assert_not EmbeddedSidekiq.enabled? }
  end

  test "uses the same queues, weights and AI capsule as config/sidekiq.yml" do
    with_env_overrides("RAILS_MAX_THREADS" => "3", "RAILS_AI_MAX_THREADS" => "1") do
      config = EmbeddedSidekiq.apply(Sidekiq::Config.new)
      default = config.default_capsule

      assert_equal 2, default.concurrency
      assert_equal :weighted, default.mode
      assert_equal 10, default.weights["scheduled"]
      assert_equal 4, default.weights["high_priority"]
      assert_includes default.queues, "default"

      ai = config.capsule("ai")
      assert_equal 1, ai.concurrency
      assert_equal :strict, ai.mode
      assert_equal %w[ai_high_priority ai_low_priority], ai.queues

      assert_equal 3, EmbeddedSidekiq.threads
    end
  end
end
