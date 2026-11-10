# frozen_string_literal: true

json.projects @projects do |project|
  json.partial! "api/v1/projects/project", project: project
end

json.pagination do
  json.page @pagy.page
  json.per_page @per_page
  json.total_count @pagy.count
  json.total_pages @pagy.pages
end
