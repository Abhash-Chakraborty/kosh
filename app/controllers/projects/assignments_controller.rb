# "Add to project" in the transactions selection bar. Only transactions in
# accounts the user may annotate are moved; split parents are skipped, as in
# bulk edit, since their parts are what count.
class Projects::AssignmentsController < ApplicationController
  before_action :require_non_guest!

  def new
    @projects = Current.family.projects.active.ordered
  end

  def create
    entry_ids = Array.wrap(params.dig(:project_assignment, :entry_ids))
    transaction_ids = Current.annotatable_entries
      .excluding_split_parents
      .where(id: entry_ids, entryable_type: "Transaction")
      .pluck(:entryable_id)

    project = Current.family.projects.find_by(id: params.dig(:project_assignment, :project_id).presence)
    if project
      count = project.assign_transactions!(transaction_ids)
      redirect_back_or_to transactions_path, notice: t(".added", count: count, project: project.name), status: :see_other
    else
      count = ProjectTransaction.where(transaction_id: transaction_ids).delete_all
      redirect_back_or_to transactions_path, notice: t(".removed", count: count), status: :see_other
    end
  end
end
