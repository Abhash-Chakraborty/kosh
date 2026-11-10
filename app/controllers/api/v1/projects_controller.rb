# frozen_string_literal: true

module Api
  module V1
    # Projects and trips: transactions and IOUs gathered under one name.
    #
    # @example Make a trip with a budget
    #   POST /api/v1/projects
    #   { "project": { "name": "Lisbon in May", "kind": "trip", "budget": "2000", "start_on": "2027-05-02" } }
    #
    # @example Put transactions in it (ids of transactions, not entries)
    #   POST /api/v1/projects/:id/transactions
    #   { "transaction_ids": ["…", "…"] }
    #
    # Totals only count transactions in accounts the caller can see. A
    # transaction can be added or removed only when the caller may annotate
    # its account (owner, or a full_control or read_write share).
    class ProjectsController < BaseController
      include Pagy::Backend

      STATUSES = %w[active archived].freeze

      before_action -> { authorize_scope!(:read) }, only: %i[index show]
      before_action -> { authorize_scope!(:write) }, only: %i[create update destroy assign_transactions unassign_transactions]
      before_action :reject_guest_writes!, only: %i[create update destroy assign_transactions unassign_transactions]
      before_action :set_project, only: %i[show update destroy assign_transactions unassign_transactions]

      def index
        if params[:status].present? && !STATUSES.include?(params[:status])
          return render_validation_error("status must be one of: #{STATUSES.join(", ")}")
        end

        projects = family.projects.ordered
        projects = projects.active if params[:status] == "active"
        projects = projects.archived if params[:status] == "archived"

        @per_page = safe_per_page_param
        @pagy, @projects = pagy(projects, page: safe_page_param, limit: @per_page)

        render :index
      end

      def show
        @totals = @project.totals(accounts: visible_accounts)
        render :show
      end

      def create
        @project = family.projects.new(project_params)

        if @project.save
          @totals = @project.totals(accounts: visible_accounts)
          render :show, status: :created
        else
          render_record_errors(@project)
        end
      end

      def update
        attrs = project_params
        archived = params.dig(:project, :archived)
        unless archived.nil?
          attrs[:archived_at] = ActiveModel::Type::Boolean.new.cast(archived) ? (@project.archived_at || Time.current) : nil
        end

        if @project.update(attrs)
          @totals = @project.totals(accounts: visible_accounts)
          render :show
        else
          render_record_errors(@project)
        end
      end

      def destroy
        @project.destroy!
        head :no_content
      end

      def assign_transactions
        ids = transaction_ids_param
        return if performed?

        allowed = annotatable_transaction_ids(ids)
        @project.assign_transactions!(allowed)
        render_json({ project_id: @project.id, transaction_ids: allowed, ignored_ids: ids - allowed })
      end

      def unassign_transactions
        ids = transaction_ids_param
        return if performed?

        allowed = annotatable_transaction_ids(ids) & @project.project_transactions.where(transaction_id: ids).pluck(:transaction_id)
        @project.unassign_transactions!(allowed)
        render_json({ project_id: @project.id, transaction_ids: allowed, ignored_ids: ids - allowed })
      end

      private
        def family
          current_resource_owner.family
        end

        def visible_accounts
          family.accounts.accessible_by(current_resource_owner)
        end

        def set_project
          @project = family.projects.find_by(id: params[:id]) if valid_uuid?(params[:id].to_s)
          render_json({ error: "not_found", message: "Project not found" }, status: :not_found) unless @project
        end

        def project_params
          params.require(:project).permit(:name, :kind, :color, :lucide_icon, :start_on, :end_on, :budget, :currency, :notes)
        end

        def transaction_ids_param
          ids = params[:transaction_ids]
          unless ids.is_a?(Array) && ids.any? && ids.all? { |id| id.is_a?(String) }
            return render_validation_error("transaction_ids must be a non-empty array of ids")
          end
          return render_validation_error("transaction_ids can hold at most 500 ids") if ids.size > 500

          ids.uniq
        end

        # The ids, of those given, the caller may annotate. Split parents are
        # left out: their parts are what count.
        def annotatable_transaction_ids(ids)
          valid = ids.select { |id| valid_uuid?(id) }
          return [] if valid.empty?

          Entry.where(entryable_type: "Transaction", entryable_id: valid)
            .where(account_id: family.accounts.annotatable_by(current_resource_owner).select(:id))
            .excluding_split_parents
            .pluck(:entryable_id)
        end

        def render_record_errors(record)
          render_json({
            error: "validation_failed",
            message: record.errors.full_messages.to_sentence,
            errors: record.errors.full_messages
          }, status: :unprocessable_entity)
        end
    end
  end
end
