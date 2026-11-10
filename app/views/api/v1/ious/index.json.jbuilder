# frozen_string_literal: true

json.ious @ious do |iou|
  json.partial! "api/v1/ious/iou", iou: iou
end

json.pagination do
  json.page @pagy.page
  json.per_page @per_page
  json.total_count @pagy.count
  json.total_pages @pagy.pages
end
