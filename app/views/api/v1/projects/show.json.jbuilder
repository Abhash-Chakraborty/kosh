# frozen_string_literal: true

json.partial! "api/v1/projects/project", project: @project

# Over the accounts the caller can see, in the project's currency.
json.totals do
  money = ->(value) { { amount: value.format, decimal: value.amount.to_d.to_s("F") } }

  json.spent money.call(@totals.spent)
  json.received money.call(@totals.received)
  json.net money.call(@totals.net)
  json.owed_to_you money.call(@totals.owed_to_you)
  json.you_owe money.call(@totals.you_owe)
  json.budget_left(@totals.budget_left && money.call(@totals.budget_left))
  json.budget_used_percent @totals.budget_used_percent
  json.transaction_count @totals.transaction_count
  json.unconverted_count @totals.unconverted_count

  json.by_category @totals.by_category do |row|
    json.category_id(row.key == "uncategorized" ? nil : row.key)
    json.name row.name
    json.spent_decimal row.spent.amount.to_d.to_s("F")
    json.received_decimal row.received.amount.to_d.to_s("F")
  end

  json.by_account @totals.by_account do |row|
    json.account_id row.key
    json.name row.name
    json.spent_decimal row.spent.amount.to_d.to_s("F")
    json.received_decimal row.received.amount.to_d.to_s("F")
  end
end
