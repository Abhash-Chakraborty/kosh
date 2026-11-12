# See ForkIconHelper. to_prepare, so the swap survives code reloading.
Rails.application.config.to_prepare do
  ApplicationHelper.prepend(ForkIconHelper) unless ApplicationHelper.ancestors.include?(ForkIconHelper)
end
