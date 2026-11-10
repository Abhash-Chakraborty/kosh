# The Project select in the transaction drawer. Choosing a project moves the
# transaction into it; choosing none takes it out. Like a category, this is
# an annotation: read-write shares may change it.
class TransactionProjectsController < ApplicationController
  include AccountAuthorizable

  before_action :require_non_guest!

  def update
    @entry = Current.family.entries.joins(:account).merge(Account.accessible_by(Current.user))
      .where(entryable_type: "Transaction").find(params[:transaction_id])
    return unless require_account_permission!(@entry.account, :annotate, redirect_path: transaction_path(@entry))

    transaction = @entry.transaction
    project = Current.family.projects.find_by(id: params.dig(:transaction_project, :project_id).presence)
    if project
      project.assign_transactions!([ transaction.id ])
    else
      ProjectTransaction.where(transaction_id: transaction.id).delete_all
    end

    respond_to do |format|
      format.html { redirect_back_or_to transaction_path(@entry), status: :see_other }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          helpers.dom_id(@entry, :project),
          partial: "projects/transaction_project",
          locals: { entry: @entry, can_annotate: true }
        )
      end
    end
  end
end
