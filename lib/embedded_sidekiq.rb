# Runs the job worker inside the Puma process (Sidekiq's embedded mode), so a
# small server keeps one copy of the app in memory instead of two. Turned on
# with SIDEKIQ_EMBEDDED=true and started by config/puma.rb after boot; the
# separate worker container is then not needed.
#
# Queues, weights and the AI capsule come from config/sidekiq.yml, as for the
# standalone worker. Sidekiq replays the app's configure_server blocks (Redis,
# middleware, the startup hooks that schedule syncs) for the embedded instance.
# Its threads share the web process's database pool, so DB_POOL must cover
# Puma's threads plus the job threads.
module EmbeddedSidekiq
  CONFIG_PATH = File.expand_path("../config/sidekiq.yml", __dir__)

  class << self
    def enabled?
      %w[1 true yes].include?(ENV["SIDEKIQ_EMBEDDED"].to_s.downcase)
    end

    def start
      @instance = Sidekiq.configure_embed { |config| apply(config) }
      @instance.run
    end

    def stop
      @instance&.stop
      @instance = nil
    end

    # Applies config/sidekiq.yml to a Sidekiq config (the CLI reads the same file).
    def apply(config, settings = load_settings)
      config.concurrency = Integer(settings.fetch("concurrency"))
      config.queues = settings.fetch("queues")

      settings.fetch("capsules", {}).each do |name, capsule|
        config.capsule(name) do |cap|
          cap.concurrency = Integer(capsule.fetch("concurrency"))
          cap.queues = capsule.fetch("queues")
        end
      end

      config
    end

    def threads(settings = load_settings)
      Integer(settings.fetch("concurrency")) +
        settings.fetch("capsules", {}).values.sum { |capsule| Integer(capsule.fetch("concurrency")) }
    end

    def load_settings
      YAML.safe_load(ERB.new(File.read(CONFIG_PATH)).result)
    end
  end
end
