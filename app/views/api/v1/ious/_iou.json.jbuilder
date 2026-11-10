# frozen_string_literal: true

json.id iou.id
json.direction iou.direction
json.person iou.person
json.description iou.description
json.currency iou.currency

# Formatted strings for display, and fixed-point decimals ("1500.0") for
# clients that do arithmetic.
json.amount iou.amount_money.format
json.amount_decimal iou.amount.to_d.to_s("F")
json.paid_decimal iou.paid_amount.to_d.to_s("F")
json.remaining iou.remaining_amount_money.format
json.remaining_decimal iou.remaining_amount.to_d.to_s("F")

json.settled iou.settled?
json.overdue iou.overdue?
json.due_on iou.due_on&.iso8601
json.notes iou.notes

if iou.account
  json.account do
    json.id iou.account.id
    json.name iou.account.name
  end
else
  json.account nil
end

if iou.category
  json.category do
    json.id iou.category.id
    json.name iou.category.name
  end
else
  json.category nil
end

json.payments iou.payments do |payment|
  json.id payment.id
  json.amount payment.amount_money.format
  json.amount_decimal payment.amount.to_d.to_s("F")
  json.date payment.date.iso8601
  json.transaction_entry_id payment.entry_id
  json.account_id payment.entry&.account_id
end

json.created_at iou.created_at.iso8601
json.updated_at iou.updated_at.iso8601
