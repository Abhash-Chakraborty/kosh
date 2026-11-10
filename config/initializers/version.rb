module Sure
  class << self
    def version
      Calver.new(version_string)
    end

    # Where this build's commits live. A fork sets SOURCE_REPOSITORY_URL so the
    # commit link in the user menu opens its own repository, not upstream's.
    def source_repository_url
      ENV["SOURCE_REPOSITORY_URL"].presence || "https://github.com/we-promise/sure"
    end

    def commit_sha
      if Rails.env.production?
        ENV["BUILD_COMMIT_SHA"]
      else
        `git rev-parse HEAD`.chomp
      end
    rescue Errno::ENOENT
      nil
    end

    private
      def version_string
        stripped_content = Rails.root.join(".sure-version").read.strip
        stripped_content.presence || "0.0.0-dev.#{commit_sha.presence || 'unknown'}"
      rescue Errno::ENOENT
        "0.0.0-dev.#{commit_sha.presence || 'unknown'}"
      end
  end
end
