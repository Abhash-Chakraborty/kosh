# frozen_string_literal: true

json.id project.id
json.name project.name
json.kind project.kind
json.color project.display_color
json.icon project.icon
json.start_on project.start_on&.iso8601
json.end_on project.end_on&.iso8601
json.currency project.currency
json.budget project.budget_money&.format
json.budget_decimal project.budget&.to_d&.to_s("F")
json.notes project.notes
json.archived project.archived?
json.archived_at project.archived_at&.iso8601
json.created_at project.created_at.iso8601
json.updated_at project.updated_at.iso8601
